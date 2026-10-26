/* 03_profiling.sql  -- YOU write the rest. Goal: find every problem BEFORE cleaning.
   Log findings in your notes; later turn each check into a rerunnable query in sql/04_data_quality. */
USE RCM;
GO
-- 1) Duplicate claim_id (exact duplicates)
SELECT claim_id, COUNT(*) AS n FROM stg.claims GROUP BY claim_id HAVING COUNT(*) > 1;

-- 2) Payer name variants for the same payer_id
SELECT payer_id, payer_name_submitted, COUNT(*) AS n
FROM stg.claims GROUP BY payer_id, payer_name_submitted ORDER BY payer_id, n DESC;

-- TODO 3) NULL / empty primary_icd10 (count + % of claims)
-- TODO 4) service_date later than submission_date (hint: dates are text; mixed formats, see #6)
-- TODO 5) claim_amount <= 0 (hint: TRY_CONVERT(DECIMAL(12,2), claim_amount))
-- TODO 6) Date values that are not ISO yyyy-mm-dd (hint: TRY_CONVERT(date, x, 23) IS NULL)
-- TODO 7) Orphan remittances (claim_id not in stg.claims)
-- TODO 8) Distinct gender values and their counts

USE RCM;
GO

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    c.column_id AS column_order,
    c.name AS column_name,
    ty.name AS data_type,
    c.max_length,
    c.precision,
    c.scale,
    c.is_nullable,
    c.is_identity,
    dc.definition AS default_value
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
INNER JOIN sys.columns AS c
    ON t.object_id = c.object_id
INNER JOIN sys.types AS ty
    ON c.user_type_id = ty.user_type_id
LEFT JOIN sys.default_constraints AS dc
    ON c.default_object_id = dc.object_id
ORDER BY
    s.name,
    t.name,
    c.column_id;


    
SELECT
    COUNT_BIG(*) AS total_claims,
    SUM(CASE
        WHEN NULLIF(LTRIM(RTRIM(primary_icd10)), '') IS NULL
        THEN 1 ELSE 0
    END) AS missing_icd10_count,
    CAST(
        100.0 * SUM(CASE
            WHEN NULLIF(LTRIM(RTRIM(primary_icd10)), '') IS NULL
            THEN 1 ELSE 0
        END) / NULLIF(COUNT_BIG(*), 0)
        AS DECIMAL(6,2)
    ) AS missing_icd10_pct
FROM stg.claims;



SELECT
    COUNT_BIG(*) AS invalid_sequence_count
FROM stg.claims
WHERE TRY_CONVERT(date, service_date, 23) IS NOT NULL
  AND TRY_CONVERT(date, submission_date, 23) IS NOT NULL
  AND TRY_CONVERT(date, service_date, 23)
      > TRY_CONVERT(date, submission_date, 23);


      
SELECT
    COUNT_BIG(*) AS non_positive_amount_count
FROM stg.claims
WHERE TRY_CONVERT(DECIMAL(12,2), claim_amount) <= 0;



SELECT
    'service_date' AS column_name,
    COUNT_BIG(*) AS total_rows,
    SUM(CASE
        WHEN NULLIF(LTRIM(RTRIM(service_date)), '') IS NOT NULL
         AND TRY_CONVERT(date, service_date, 23) IS NULL
        THEN 1 ELSE 0
    END) AS non_iso_or_invalid_count,
    SUM(CASE
        WHEN NULLIF(LTRIM(RTRIM(service_date)), '') IS NULL
        THEN 1 ELSE 0
    END) AS missing_count
FROM stg.claims

UNION ALL

SELECT
    'submission_date',
    COUNT_BIG(*),
    SUM(CASE
        WHEN NULLIF(LTRIM(RTRIM(submission_date)), '') IS NOT NULL
         AND TRY_CONVERT(date, submission_date, 23) IS NULL
        THEN 1 ELSE 0
    END),
    SUM(CASE
        WHEN NULLIF(LTRIM(RTRIM(submission_date)), '') IS NULL
        THEN 1 ELSE 0
    END)
FROM stg.claims;


SELECT
    COUNT_BIG(*) AS orphan_remittance_count
FROM stg.remittances AS r
WHERE NOT EXISTS (
    SELECT 1
    FROM stg.claims AS c
    WHERE c.claim_id = r.claim_id
);


SELECT
    COALESCE(
        NULLIF(LTRIM(RTRIM(gender)), ''),
        '<MISSING>'
    ) AS gender_value,
    COUNT_BIG(*) AS patient_count
FROM stg.patients
GROUP BY
    COALESCE(
        NULLIF(LTRIM(RTRIM(gender)), ''),
        '<MISSING>'
    )
ORDER BY patient_count DESC;


  SELECT gender COLLATE Latin1_General_BIN2 AS g, COUNT(*) 
  FROM stg.patients GROUP BY gender COLLATE Latin1_General_BIN2;



  SELECT
    COUNT_BIG(*) AS total_rows,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(service_date)), '') IS NOT NULL
              AND TRY_CONVERT(date, service_date, 23) IS NULL
             THEN 1 ELSE 0 END) AS non_iso_count
FROM stg.claims;




SELECT COUNT_BIG(*) AS invalid_sequence_count
FROM stg.claims
WHERE COALESCE(TRY_CONVERT(date, service_date, 23),
               TRY_CONVERT(date, service_date, 103))
    > COALESCE(TRY_CONVERT(date, submission_date, 23),
               TRY_CONVERT(date, submission_date, 103));