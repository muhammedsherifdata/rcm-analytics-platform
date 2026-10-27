/* =====================================================================
   04_validate_clean.sql
   Proves the cleaning worked. Every row must say PASS.
   Part A reconciles row counts (nothing lost without a reason).
   Part B re-runs the profiling checks on clean.* (problems must be gone).
   ===================================================================== */
USE RCM;
GO

SELECT check_name, actual, expected,
       CASE WHEN actual = expected THEN 'PASS' ELSE 'FAIL' END AS result
FROM (
    /* ---- Part A: reconciliation ---- */
    SELECT 'A1 stg.claims - clean.claims = duplicates removed' AS check_name,
           (SELECT COUNT(*) FROM stg.claims) - (SELECT COUNT(*) FROM clean.claims) AS actual, 720 AS expected
    UNION ALL SELECT 'A2 clean.claims rows',              (SELECT COUNT(*) FROM clean.claims),                    60000
    UNION ALL SELECT 'A3 stg.remittances = clean + quarantine',
           (SELECT COUNT(*) FROM clean.remittances) + (SELECT COUNT(*) FROM clean.quarantine_remittances),
           (SELECT COUNT(*) FROM stg.remittances)
    UNION ALL SELECT 'A4 clean.remittances rows',         (SELECT COUNT(*) FROM clean.remittances),              49529
    UNION ALL SELECT 'A5 quarantine_remittances rows',    (SELECT COUNT(*) FROM clean.quarantine_remittances),      40
    UNION ALL SELECT 'A6 clean.denials rows',             (SELECT COUNT(*) FROM clean.denials),                   7424
    UNION ALL SELECT 'A7 clean.patients rows',            (SELECT COUNT(*) FROM clean.patients),                 20000

    /* ---- Part B: problems are gone ---- */
    UNION ALL SELECT 'B1 duplicate claim_id',
           (SELECT COUNT(*) FROM (SELECT claim_id FROM clean.claims GROUP BY claim_id HAVING COUNT(*) > 1) x), 0
    UNION ALL SELECT 'B2 gender values not in (F, M, Unknown)',
           (SELECT COUNT(*) FROM clean.patients WHERE gender NOT IN ('F', 'M', 'Unknown')), 0
    UNION ALL SELECT 'B3 NULL dates in claims',
           (SELECT COUNT(*) FROM clean.claims WHERE service_date IS NULL OR submission_date IS NULL), 0
    UNION ALL SELECT 'B4 non-positive amounts in VALID claims',
           (SELECT COUNT(*) FROM clean.v_claims_valid WHERE claim_amount <= 0), 0
    UNION ALL SELECT 'B5 service after submission in VALID claims',
           (SELECT COUNT(*) FROM clean.v_claims_valid WHERE service_date > submission_date), 0
    UNION ALL SELECT 'B6 orphan remittances in clean.remittances',
           (SELECT COUNT(*) FROM clean.remittances r WHERE NOT EXISTS (SELECT 1 FROM clean.claims c WHERE c.claim_id = r.claim_id)), 0

    /* ---- Part C: what was flagged (documented, not hidden) ---- */
    UNION ALL SELECT 'C1 claims flagged QUARANTINE',      (SELECT COUNT(*) FROM clean.v_claims_quarantine),        414
    UNION ALL SELECT 'C2 claims with missing ICD-10',     (SELECT COUNT(*) FROM clean.claims WHERE icd10_missing = 1), 588
) t
ORDER BY check_name;
GO

/* Claim status mix after cleaning (for the README) */
SELECT claim_status, COUNT(*) AS claims FROM clean.claims GROUP BY claim_status;
