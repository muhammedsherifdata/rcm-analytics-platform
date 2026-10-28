/* =====================================================================
   01_dim_date.sql
   Builds the dw schema objects that everything else depends on and the
   date dimension (2024-01-01 .. 2027-12-31 = 1,461 rows).

   WHY A DATE TABLE?
   Power BI time intelligence (YTD, same period last year...) needs a
   complete calendar with no gaps. We also use it as a ROLE-PLAYING
   dimension: the fact table has several dates (service, submission,
   payment, denial) and each one points to this same table.

   WHY THE RANGE GOES TO 2027?
   Some claims have submission dates after the 2026-09-30 extract date
   (see README, "known limitations"). The fact table has a foreign key to
   this table, so the calendar must cover every date in the data.
   ===================================================================== */
USE RCM;
GO

/* Reset in dependency order: the fact first, dimensions after */
DROP TABLE IF EXISTS dw.fact_claims;
DROP TABLE IF EXISTS dw.dim_date;
DROP TABLE IF EXISTS dw.dim_payer;
DROP TABLE IF EXISTS dw.dim_provider;
DROP TABLE IF EXISTS dw.dim_patient;
DROP TABLE IF EXISTS dw.dim_denial_reason;
GO

CREATE TABLE dw.dim_date (
    date_key         INT          NOT NULL CONSTRAINT PK_dim_date PRIMARY KEY,   -- 20260930
    full_date        DATE         NOT NULL,
    [year]           SMALLINT     NOT NULL,
    [quarter]        TINYINT      NOT NULL,
    month_number     TINYINT      NOT NULL,
    month_name       VARCHAR(10)  NOT NULL,
    year_month       CHAR(7)      NOT NULL,                                       -- '2026-09' (sorts correctly)
    day_of_month     TINYINT      NOT NULL,
    day_name         VARCHAR(10)  NOT NULL,
    is_weekend       BIT          NOT NULL                                        -- Friday/Saturday (Egypt, KSA, UAE)
);

/* A recursive CTE generates one row per day. MAXRECURSION 0 lifts the
   default limit of 100 recursion levels. */
WITH d AS (
    SELECT CAST('2024-01-01' AS DATE) AS dt
    UNION ALL
    SELECT DATEADD(DAY, 1, dt) FROM d WHERE dt < '2027-12-31'
)
INSERT INTO dw.dim_date
SELECT
    CONVERT(INT, CONVERT(CHAR(8), dt, 112)),                  -- style 112 = yyyymmdd
    dt,
    YEAR(dt),
    DATEPART(QUARTER, dt),
    MONTH(dt),
    CHOOSE(MONTH(dt), 'January','February','March','April','May','June',
                      'July','August','September','October','November','December'),
    CONVERT(CHAR(7), dt, 120),                                 -- style 120 -> '2026-09'
    DAY(dt),
    /* 1900-01-01 was a Monday, so (days since then) % 7 = 0 means Monday.
       This does not depend on the server's DATEFIRST or language setting. */
    CHOOSE((DATEDIFF(DAY, '19000101', dt) % 7) + 1,
           'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'),
    CASE WHEN (DATEDIFF(DAY, '19000101', dt) % 7) IN (4, 5) THEN 1 ELSE 0 END   -- Fri, Sat
FROM d
OPTION (MAXRECURSION 0);
GO
