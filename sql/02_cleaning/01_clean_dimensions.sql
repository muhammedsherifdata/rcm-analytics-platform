/* =====================================================================
   01_clean_dimensions.sql
   Builds clean.payers, clean.providers, clean.map_gender, clean.patients
   from stg.* (stg is never modified).

   RULES USED THROUGHOUT THE CLEAN LAYER
   1. TRY_CONVERT returns NULL instead of an error when a value cannot be
      converted. Our clean columns are NOT NULL, so a bad value makes the
      INSERT fail LOUDLY instead of silently producing wrong data.
   2. LTRIM(RTRIM(x)) removes leading/trailing spaces (the payer-name problem).
   3. Always re-run the cleaning scripts in order: 01 -> 02 -> 03 -> 04.
   ===================================================================== */
USE RCM;
GO

/* ---- Reset: drop in dependency order (children first, parents last) ---- */
DROP VIEW  IF EXISTS clean.v_claims_valid;
DROP VIEW  IF EXISTS clean.v_claims_quarantine;
DROP TABLE IF EXISTS clean.denials;
DROP TABLE IF EXISTS clean.remittances;
DROP TABLE IF EXISTS clean.quarantine_remittances;
DROP TABLE IF EXISTS clean.claims;
DROP TABLE IF EXISTS clean.patients;
DROP TABLE IF EXISTS clean.map_gender;
DROP TABLE IF EXISTS clean.providers;
DROP TABLE IF EXISTS clean.payers;
GO

/* ---- clean.payers (16 rows) ---- */
CREATE TABLE clean.payers (
    payer_id    INT           NOT NULL CONSTRAINT PK_clean_payers PRIMARY KEY,
    payer_name  NVARCHAR(100) NOT NULL,
    country     NVARCHAR(20)  NOT NULL,
    payer_type  NVARCHAR(20)  NOT NULL
        CONSTRAINT CK_clean_payers_type CHECK (payer_type IN ('Private', 'Government'))
);

INSERT INTO clean.payers (payer_id, payer_name, country, payer_type)
SELECT TRY_CONVERT(INT, payer_id),
       LTRIM(RTRIM(payer_name)),
       LTRIM(RTRIM(country)),
       LTRIM(RTRIM(payer_type))
FROM stg.payers;
GO

/* ---- clean.providers (12 rows) ---- */
CREATE TABLE clean.providers (
    provider_id    INT           NOT NULL CONSTRAINT PK_clean_providers PRIMARY KEY,
    provider_name  NVARCHAR(100) NOT NULL,
    city           NVARCHAR(50)  NOT NULL,
    country        NVARCHAR(20)  NOT NULL,
    provider_type  NVARCHAR(20)  NOT NULL
);

INSERT INTO clean.providers (provider_id, provider_name, city, country, provider_type)
SELECT TRY_CONVERT(INT, provider_id),
       LTRIM(RTRIM(provider_name)),
       LTRIM(RTRIM(city)),
       LTRIM(RTRIM(country)),
       LTRIM(RTRIM(provider_type))
FROM stg.providers;
GO

/* ---- clean.map_gender: a lookup table instead of a long CASE ----
   Why a table? It is easy to review, easy to extend, and shows up in the
   portfolio as a documented business rule.
   raw_value uses a BINARY collation so 'f' and 'F' stay DIFFERENT rows
   (the database default is case-insensitive and would merge them). */
CREATE TABLE clean.map_gender (
    raw_value  NVARCHAR(20) COLLATE Latin1_General_BIN2 NOT NULL CONSTRAINT PK_map_gender PRIMARY KEY,
    std_value  NVARCHAR(10) NOT NULL
);

INSERT INTO clean.map_gender (raw_value, std_value) VALUES
    ('F',       'F'),
    ('f',       'F'),
    ('Female',  'F'),
    ('M',       'M'),
    ('m',       'M'),
    ('male',    'M'),
    ('MALE',    'M'),
    ('unknown', 'Unknown');   -- a missing value, not a gender
GO

/* ---- clean.patients (20,000 rows) ----
   If stg.patients has a gender that is not in map_gender, std_value is NULL
   and the NOT NULL constraint stops the load: new variants never slip in. */
CREATE TABLE clean.patients (
    patient_id  INT          NOT NULL CONSTRAINT PK_clean_patients PRIMARY KEY,
    gender      NVARCHAR(10) NOT NULL
        CONSTRAINT CK_clean_patients_gender CHECK (gender IN ('F', 'M', 'Unknown')),
    birth_date  DATE         NOT NULL
);

INSERT INTO clean.patients (patient_id, gender, birth_date)
SELECT TRY_CONVERT(INT, p.patient_id),
       m.std_value,
       TRY_CONVERT(DATE, p.birth_date, 23)
FROM stg.patients AS p
LEFT JOIN clean.map_gender AS m
       ON LTRIM(RTRIM(p.gender)) COLLATE Latin1_General_BIN2 = m.raw_value;
GO
