/* =====================================================================
   03_clean_remittances_denials.sql
   clean.remittances       49,529 rows  (payments whose claim exists)
   clean.quarantine_remittances 40 rows (orphans: claim_id not in claims)
   clean.denials            7,424 rows
   ===================================================================== */
USE RCM;
GO

DROP TABLE IF EXISTS clean.denials;
DROP TABLE IF EXISTS clean.remittances;
DROP TABLE IF EXISTS clean.quarantine_remittances;
GO

/* ---- remittances ---- */
CREATE TABLE clean.remittances (
    remittance_id           INT           NOT NULL CONSTRAINT PK_clean_remittances PRIMARY KEY,
    claim_id                INT           NOT NULL CONSTRAINT FK_rem_claim REFERENCES clean.claims (claim_id),
    payment_date            DATE          NOT NULL,
    paid_amount             DECIMAL(12,2) NOT NULL,   -- rounds 483.79999999999995 -> 483.80
    patient_responsibility  DECIMAL(12,2) NOT NULL,
    contractual_adjustment  DECIMAL(12,2) NOT NULL,
    payment_type            NVARCHAR(10)  NOT NULL
        CONSTRAINT CK_rem_type CHECK (payment_type IN ('Initial', 'Appeal'))
);

INSERT INTO clean.remittances
SELECT TRY_CONVERT(INT, r.remittance_id),
       TRY_CONVERT(INT, r.claim_id),
       TRY_CONVERT(DATE, r.payment_date, 23),
       TRY_CONVERT(DECIMAL(12,2), r.paid_amount),
       TRY_CONVERT(DECIMAL(12,2), r.patient_responsibility),
       TRY_CONVERT(DECIMAL(12,2), r.contractual_adjustment),
       LTRIM(RTRIM(r.payment_type))
FROM stg.remittances AS r
WHERE EXISTS (SELECT 1 FROM clean.claims AS c WHERE c.claim_id = TRY_CONVERT(INT, r.claim_id));
GO

/* ---- orphan remittances are isolated, not deleted ---- */
CREATE TABLE clean.quarantine_remittances (
    remittance_id           NVARCHAR(50),
    claim_id                NVARCHAR(50),
    payment_date            NVARCHAR(50),
    paid_amount             NVARCHAR(50),
    patient_responsibility  NVARCHAR(50),
    contractual_adjustment  NVARCHAR(50),
    payment_type            NVARCHAR(50),
    reject_reason           VARCHAR(100) NOT NULL
);

INSERT INTO clean.quarantine_remittances
SELECT r.*, 'claim_id_not_found_in_claims'
FROM stg.remittances AS r
WHERE NOT EXISTS (SELECT 1 FROM clean.claims AS c WHERE c.claim_id = TRY_CONVERT(INT, r.claim_id));
GO

/* ---- denials ----
   appeal_date / appeal_outcome are empty strings when the claim was not
   appealed. NULLIF turns '' into a real NULL, which is the correct way to say
   "no value". */
CREATE TABLE clean.denials (
    denial_id         INT           NOT NULL CONSTRAINT PK_clean_denials PRIMARY KEY,
    claim_id          INT           NOT NULL CONSTRAINT FK_den_claim REFERENCES clean.claims (claim_id),
    denial_date       DATE          NOT NULL,
    denial_code       VARCHAR(10)   NOT NULL,
    denial_reason     NVARCHAR(100) NOT NULL,
    denied_amount     DECIMAL(12,2) NOT NULL,
    appealed          BIT           NOT NULL,
    appeal_date       DATE          NULL,
    appeal_outcome    NVARCHAR(20)  NULL
        CONSTRAINT CK_den_outcome CHECK (appeal_outcome IN ('Overturned', 'Upheld', 'In Review')),
    recovered_amount  DECIMAL(12,2) NOT NULL
);

INSERT INTO clean.denials
SELECT TRY_CONVERT(INT, denial_id),
       TRY_CONVERT(INT, claim_id),
       TRY_CONVERT(DATE, denial_date, 23),
       LTRIM(RTRIM(denial_code)),
       LTRIM(RTRIM(denial_reason)),
       TRY_CONVERT(DECIMAL(12,2), denied_amount),
       CASE LTRIM(RTRIM(appealed)) WHEN 'True' THEN 1 WHEN 'False' THEN 0 END,
       TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM(appeal_date)), ''), 23),
       NULLIF(LTRIM(RTRIM(appeal_outcome)), ''),
       TRY_CONVERT(DECIMAL(12,2), recovered_amount)
FROM stg.denials;
GO
