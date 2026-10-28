/* =====================================================================
   02_dimensions.sql
   dim_payer, dim_provider, dim_patient, dim_denial_reason.

   DESIGN DECISION: natural keys.
   Textbooks use surrogate keys (an extra identity column) so a dimension
   can keep history when attributes change (SCD Type 2). Our dimensions
   never change in this dataset, so we reuse the source ids (payer_id...).
   One less join, simpler DAX, and the choice is documented here.
   ===================================================================== */
USE RCM;
GO

/* ---- dim_payer (16) ---- */
CREATE TABLE dw.dim_payer (
    payer_id    INT           NOT NULL CONSTRAINT PK_dim_payer PRIMARY KEY,
    payer_name  NVARCHAR(100) NOT NULL,
    country     NVARCHAR(20)  NOT NULL,
    payer_type  NVARCHAR(20)  NOT NULL
);
INSERT INTO dw.dim_payer SELECT payer_id, payer_name, country, payer_type FROM clean.payers;

/* ---- dim_provider (12) ---- */
CREATE TABLE dw.dim_provider (
    provider_id    INT           NOT NULL CONSTRAINT PK_dim_provider PRIMARY KEY,
    provider_name  NVARCHAR(100) NOT NULL,
    city           NVARCHAR(50)  NOT NULL,
    country        NVARCHAR(20)  NOT NULL,
    provider_type  NVARCHAR(20)  NOT NULL
);
INSERT INTO dw.dim_provider SELECT provider_id, provider_name, city, country, provider_type FROM clean.providers;
GO

/* ---- dim_patient (20,000) ----
   age is measured at the extract date (2026-09-30) so the dimension is static.
   The formula subtracts 1 if the birthday has not happened yet this year:
   DATEDIFF(YEAR, ...) alone only subtracts the calendar years. */
CREATE TABLE dw.dim_patient (
    patient_id   INT         NOT NULL CONSTRAINT PK_dim_patient PRIMARY KEY,
    gender       NVARCHAR(10) NOT NULL,
    birth_date   DATE        NOT NULL,
    age          TINYINT     NOT NULL,
    age_group    VARCHAR(10) NOT NULL
);

DECLARE @asof DATE = '2026-09-30';

INSERT INTO dw.dim_patient (patient_id, gender, birth_date, age, age_group)
SELECT patient_id, gender, birth_date, age,
       CASE WHEN age < 18 THEN '0-17'
            WHEN age < 35 THEN '18-34'
            WHEN age < 50 THEN '35-49'
            WHEN age < 65 THEN '50-64'
            ELSE '65+' END
FROM (
    SELECT p.patient_id, p.gender, p.birth_date,
           DATEDIFF(YEAR, p.birth_date, @asof)
             - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, p.birth_date, @asof), p.birth_date) > @asof
                    THEN 1 ELSE 0 END AS age
    FROM clean.patients AS p
) AS x;
GO

/* ---- dim_denial_reason (6) ----
   is_preventable follows docs/kpi_definitions.md: eligibility, prior
   authorization, coding and timely filing can be prevented BEFORE submission;
   medical necessity and duplicate claims are not (in this project's definition). */
CREATE TABLE dw.dim_denial_reason (
    denial_code     VARCHAR(10)   NOT NULL CONSTRAINT PK_dim_denial_reason PRIMARY KEY,
    denial_reason   NVARCHAR(100) NOT NULL,
    root_cause      VARCHAR(20)   NOT NULL,
    is_preventable  BIT           NOT NULL
);

INSERT INTO dw.dim_denial_reason (denial_code, denial_reason, root_cause, is_preventable) VALUES
    ('CO-50',  'Not medically necessary',            'Medical necessity', 0),
    ('CO-29',  'Timely filing limit exceeded',       'Timely filing',     1),
    ('CO-16',  'Coding error / missing information','Coding',            1),
    ('CO-27',  'Coverage not active / eligibility',  'Eligibility',       1),
    ('CO-197', 'Prior authorization missing',        'Authorization',     1),
    ('CO-18',  'Duplicate claim',                    'Duplicate',         0);
GO
