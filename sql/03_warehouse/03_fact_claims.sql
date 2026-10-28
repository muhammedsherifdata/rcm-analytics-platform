/* =====================================================================
   03_fact_claims.sql
   GRAIN: one row per VALID claim (59,586 rows).

   WHY THE GRAIN MATTERS
   Remittances and denials are rolled up to claim level BEFORE joining, so
   a claim can never be counted twice. If we joined the raw tables, one
   claim with two payments would double its claim_amount in every SUM.

   Only clean.v_claims_valid feeds the fact: the 414 quarantined claims
   (bad amount or reversed dates) never reach reporting.
   ===================================================================== */
USE RCM;
GO

DROP TABLE IF EXISTS dw.fact_claims;
GO

CREATE TABLE dw.fact_claims (
    claim_id               INT           NOT NULL CONSTRAINT PK_fact_claims PRIMARY KEY,

    /* foreign keys to dimensions. The four date keys are ROLE-PLAYING: all point to dim_date */
    service_date_key       INT           NOT NULL CONSTRAINT FK_fact_service_date    REFERENCES dw.dim_date (date_key),
    submission_date_key    INT           NOT NULL CONSTRAINT FK_fact_submission_date REFERENCES dw.dim_date (date_key),
    payment_date_key       INT           NULL     CONSTRAINT FK_fact_payment_date    REFERENCES dw.dim_date (date_key),
    denial_date_key        INT           NULL     CONSTRAINT FK_fact_denial_date     REFERENCES dw.dim_date (date_key),
    payer_id               INT           NOT NULL CONSTRAINT FK_fact_payer           REFERENCES dw.dim_payer (payer_id),
    provider_id            INT           NOT NULL CONSTRAINT FK_fact_provider        REFERENCES dw.dim_provider (provider_id),
    patient_id             INT           NOT NULL CONSTRAINT FK_fact_patient         REFERENCES dw.dim_patient (patient_id),
    denial_code            VARCHAR(10)   NULL     CONSTRAINT FK_fact_denial_reason   REFERENCES dw.dim_denial_reason (denial_code),

    /* descriptive attributes that stay on the fact (degenerate dimensions) */
    claim_type             NVARCHAR(20)  NOT NULL,
    cpt_code               VARCHAR(10)   NOT NULL,
    primary_icd10          VARCHAR(10)   NOT NULL,
    claim_status           NVARCHAR(10)  NOT NULL,

    /* measures: money */
    claim_amount           DECIMAL(12,2) NOT NULL,
    paid_amount            DECIMAL(12,2) NOT NULL,
    patient_responsibility DECIMAL(12,2) NOT NULL,
    contractual_adjustment DECIMAL(12,2) NOT NULL,
    denied_amount          DECIMAL(12,2) NOT NULL,
    recovered_amount       DECIMAL(12,2) NOT NULL,

    /* measures: time */
    filing_lag_days        SMALLINT      NOT NULL,   -- service -> submission
    days_to_pay            SMALLINT      NULL,       -- submission -> first payment (NULL = not paid)

    /* flags (0/1 so DAX can SUM them) */
    is_denied              BIT           NOT NULL,
    is_clean_claim         BIT           NOT NULL,
    is_appealed            BIT           NOT NULL,
    appeal_outcome         NVARCHAR(20)  NULL,
    prior_auth_required    BIT           NOT NULL,
    prior_auth_obtained    BIT           NOT NULL,
    eligibility_verified   BIT           NOT NULL,
    icd10_missing          BIT           NOT NULL
);
GO

WITH pay AS (          -- one row per claim (the data has at most one remittance per claim, but we do not rely on it)
    SELECT claim_id,
           MIN(payment_date)            AS first_payment_date,
           SUM(paid_amount)             AS paid_amount,
           SUM(patient_responsibility)  AS patient_responsibility,
           SUM(contractual_adjustment)  AS contractual_adjustment
    FROM clean.remittances
    GROUP BY claim_id
),
den AS (               -- one row per claim
    SELECT claim_id,
           MIN(denial_date)             AS denial_date,
           MIN(denial_code)             AS denial_code,
           SUM(denied_amount)           AS denied_amount,
           SUM(recovered_amount)        AS recovered_amount,
           MAX(CAST(appealed AS INT))   AS appealed,
           MIN(appeal_outcome)          AS appeal_outcome
    FROM clean.denials
    GROUP BY claim_id
)
INSERT INTO dw.fact_claims
SELECT
    c.claim_id,
    CONVERT(INT, CONVERT(CHAR(8), c.service_date,    112)),
    CONVERT(INT, CONVERT(CHAR(8), c.submission_date, 112)),
    CONVERT(INT, CONVERT(CHAR(8), p.first_payment_date, 112)),   -- NULL stays NULL
    CONVERT(INT, CONVERT(CHAR(8), d.denial_date, 112)),
    c.payer_id, c.provider_id, c.patient_id,
    d.denial_code,
    c.claim_type, c.cpt_code, c.primary_icd10, c.claim_status,
    c.claim_amount,
    COALESCE(p.paid_amount, 0),
    COALESCE(p.patient_responsibility, 0),
    COALESCE(p.contractual_adjustment, 0),
    COALESCE(d.denied_amount, 0),
    COALESCE(d.recovered_amount, 0),
    DATEDIFF(DAY, c.service_date, c.submission_date),
    DATEDIFF(DAY, c.submission_date, p.first_payment_date),
    CASE WHEN c.claim_status = 'Denied' THEN 1 ELSE 0 END,
    /* Clean claim = nothing wrong that we can see:
       eligibility verified, authorization (if required) obtained, filed within
       90 days, diagnosis code present, and not denied for a coding error. */
    CASE WHEN c.eligibility_verified = 1
          AND NOT (c.prior_auth_required = 1 AND c.prior_auth_obtained = 0)
          AND DATEDIFF(DAY, c.service_date, c.submission_date) <= 90
          AND c.icd10_missing = 0
          AND COALESCE(d.denial_code, '') <> 'CO-16'
         THEN 1 ELSE 0 END,
    COALESCE(d.appealed, 0),
    d.appeal_outcome,
    c.prior_auth_required, c.prior_auth_obtained, c.eligibility_verified,
    c.icd10_missing
FROM clean.v_claims_valid AS c
LEFT JOIN pay AS p ON p.claim_id = c.claim_id
LEFT JOIN den AS d ON d.claim_id = c.claim_id;
GO
