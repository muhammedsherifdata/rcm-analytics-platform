/* =====================================================================
   02_clean_claims.sql
   Builds clean.claims (60,000 rows) from stg.claims (60,720 rows).

   PROBLEMS FIXED HERE
   - 720 duplicate claim_id rows  -> keep ONE row per claim (the best copy)
   - mixed date formats           -> parse yyyy-mm-dd and dd/mm/yyyy
   - amounts / flags stored as text -> DECIMAL(12,2) and BIT
   - missing ICD-10 (588 after dedup) -> 'UNKNOWN' + icd10_missing flag
   - amount <= 0, service after submission -> FLAGGED (dq_status), not deleted

   WHY FLAG INSTEAD OF DELETE?
   Remittances and denials point to these claims. If we removed the claim,
   its payments would become orphans. So every claim stays in clean.claims
   with dq_status = 'OK' or 'QUARANTINE'. Reports use clean.v_claims_valid.
   ===================================================================== */
USE RCM;
GO

DROP VIEW  IF EXISTS clean.v_claims_valid;
DROP VIEW  IF EXISTS clean.v_claims_quarantine;
DROP TABLE IF EXISTS clean.denials;
DROP TABLE IF EXISTS clean.remittances;
DROP TABLE IF EXISTS clean.quarantine_remittances;
DROP TABLE IF EXISTS clean.claims;
GO

CREATE TABLE clean.claims (
    claim_id              INT           NOT NULL CONSTRAINT PK_clean_claims PRIMARY KEY,
    patient_id            INT           NOT NULL CONSTRAINT FK_claims_patient  REFERENCES clean.patients  (patient_id),
    provider_id           INT           NOT NULL CONSTRAINT FK_claims_provider REFERENCES clean.providers (provider_id),
    payer_id              INT           NOT NULL CONSTRAINT FK_claims_payer    REFERENCES clean.payers    (payer_id),
    payer_name_submitted  NVARCHAR(100) NOT NULL,   -- kept only for audit; reports use clean.payers.payer_name
    claim_type            NVARCHAR(20)  NOT NULL,
    cpt_code              VARCHAR(10)   NOT NULL,
    primary_icd10         VARCHAR(10)   NOT NULL,   -- 'UNKNOWN' when missing
    icd10_missing         BIT           NOT NULL,
    service_date          DATE          NOT NULL,
    submission_date       DATE          NOT NULL,
    claim_amount          DECIMAL(12,2) NOT NULL,
    prior_auth_required   BIT           NOT NULL,
    prior_auth_obtained   BIT           NOT NULL,
    eligibility_verified  BIT           NOT NULL,
    claim_status          NVARCHAR(10)  NOT NULL
        CONSTRAINT CK_claims_status CHECK (claim_status IN ('Paid', 'Denied', 'Pending')),
    dq_status             VARCHAR(10)   NOT NULL
        CONSTRAINT CK_claims_dq_status CHECK (dq_status IN ('OK', 'QUARANTINE')),
    dq_reason             VARCHAR(100)  NULL
);
GO

WITH parsed AS (
    /* Step 1: convert every column to its real type. Nothing is dropped yet. */
    SELECT
        TRY_CONVERT(INT, claim_id)                    AS claim_id,
        TRY_CONVERT(INT, patient_id)                  AS patient_id,
        TRY_CONVERT(INT, provider_id)                 AS provider_id,
        TRY_CONVERT(INT, payer_id)                    AS payer_id,
        LTRIM(RTRIM(payer_name_submitted))            AS payer_name_submitted,
        LTRIM(RTRIM(claim_type))                      AS claim_type,
        LTRIM(RTRIM(cpt_code))                        AS cpt_code,
        NULLIF(LTRIM(RTRIM(primary_icd10)), '')       AS primary_icd10,
        /* try ISO first (style 23); if that fails try dd/mm/yyyy (style 103) */
        COALESCE(TRY_CONVERT(DATE, service_date,    23),
                 TRY_CONVERT(DATE, service_date,   103)) AS service_date,
        COALESCE(TRY_CONVERT(DATE, submission_date, 23),
                 TRY_CONVERT(DATE, submission_date,103)) AS submission_date,
        TRY_CONVERT(DECIMAL(12,2), claim_amount)      AS claim_amount,
        CASE LTRIM(RTRIM(prior_auth_required))  WHEN 'True' THEN 1 WHEN 'False' THEN 0 END AS prior_auth_required,
        CASE LTRIM(RTRIM(prior_auth_obtained))  WHEN 'True' THEN 1 WHEN 'False' THEN 0 END AS prior_auth_obtained,
        CASE LTRIM(RTRIM(eligibility_verified)) WHEN 'True' THEN 1 WHEN 'False' THEN 0 END AS eligibility_verified,
        LTRIM(RTRIM(claim_status))                    AS claim_status
    FROM stg.claims
),
ranked AS (
    /* Step 2: number the copies of each claim. rn = 1 is the copy we keep.
       The duplicates are not always identical: in 70 of the 720 pairs one copy
       had a problem injected (bad amount, wrong date, missing ICD-10).
       So we keep the copy with the FEWEST problems, not a random one. */
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY claim_id
               ORDER BY CASE WHEN claim_amount <= 0                THEN 1 ELSE 0 END,
                        CASE WHEN service_date > submission_date   THEN 1 ELSE 0 END,
                        CASE WHEN primary_icd10 IS NULL            THEN 1 ELSE 0 END
           ) AS rn
    FROM parsed
)
INSERT INTO clean.claims
    (claim_id, patient_id, provider_id, payer_id, payer_name_submitted, claim_type,
     cpt_code, primary_icd10, icd10_missing, service_date, submission_date, claim_amount,
     prior_auth_required, prior_auth_obtained, eligibility_verified, claim_status,
     dq_status, dq_reason)
SELECT
    claim_id, patient_id, provider_id, payer_id, payer_name_submitted, claim_type,
    cpt_code,
    COALESCE(primary_icd10, 'UNKNOWN'),
    CASE WHEN primary_icd10 IS NULL THEN 1 ELSE 0 END,
    service_date, submission_date, claim_amount,
    prior_auth_required, prior_auth_obtained, eligibility_verified, claim_status,
    /* Step 3: business-rule flags */
    CASE WHEN claim_amount <= 0 OR service_date > submission_date
         THEN 'QUARANTINE' ELSE 'OK' END,
    /* CONCAT_WS skips NULLs, so we only get the reasons that apply */
    NULLIF(CONCAT_WS('; ',
        CASE WHEN claim_amount <= 0              THEN 'non_positive_amount'       END,
        CASE WHEN service_date > submission_date THEN 'service_after_submission'  END), '')
FROM ranked
WHERE rn = 1;
GO

/* Convenience views: reports read the valid claims, auditors read the quarantine */
CREATE VIEW clean.v_claims_valid AS
SELECT * FROM clean.claims WHERE dq_status = 'OK';
GO

CREATE VIEW clean.v_claims_quarantine AS
SELECT * FROM clean.claims WHERE dq_status = 'QUARANTINE';
GO
