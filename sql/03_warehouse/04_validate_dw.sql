/* =====================================================================
   04_validate_dw.sql   -- every row must say PASS
   A: row counts   B: totals reconcile with the clean layer   C: KPI sanity
   ===================================================================== */
USE RCM;
GO

SELECT check_name, actual, expected,
       CASE WHEN actual = expected THEN 'PASS' ELSE 'FAIL' END AS result
FROM (
    /* ---- A: row counts ---- */
              SELECT 'A1 dim_date rows'            AS check_name, CAST(COUNT(*) AS DECIMAL(18,2)) AS actual, CAST(1461 AS DECIMAL(18,2)) AS expected FROM dw.dim_date
    UNION ALL SELECT 'A2 dim_payer rows',          COUNT(*), 16    FROM dw.dim_payer
    UNION ALL SELECT 'A3 dim_provider rows',       COUNT(*), 12    FROM dw.dim_provider
    UNION ALL SELECT 'A4 dim_patient rows',        COUNT(*), 20000 FROM dw.dim_patient
    UNION ALL SELECT 'A5 dim_denial_reason rows',  COUNT(*), 6     FROM dw.dim_denial_reason
    UNION ALL SELECT 'A6 fact_claims rows',        COUNT(*), 59586 FROM dw.fact_claims

    /* ---- B: reconciliation with clean.* ---- */
    UNION ALL SELECT 'B1 fact rows = valid claims',
           (SELECT COUNT(*) FROM dw.fact_claims), (SELECT COUNT(*) FROM clean.v_claims_valid)
    UNION ALL SELECT 'B2 SUM(claim_amount) fact = clean',
           (SELECT SUM(claim_amount) FROM dw.fact_claims), (SELECT SUM(claim_amount) FROM clean.v_claims_valid)
    UNION ALL SELECT 'B3 SUM(paid_amount) fact = remittances of valid claims',
           (SELECT SUM(paid_amount) FROM dw.fact_claims),
           (SELECT SUM(r.paid_amount) FROM clean.remittances r JOIN clean.v_claims_valid c ON c.claim_id = r.claim_id)
    UNION ALL SELECT 'B4 SUM(denied_amount) fact = denials of valid claims',
           (SELECT SUM(denied_amount) FROM dw.fact_claims),
           (SELECT SUM(d.denied_amount) FROM clean.denials d JOIN clean.v_claims_valid c ON c.claim_id = d.claim_id)
    UNION ALL SELECT 'B5 duplicate claim_id in fact',
           (SELECT COUNT(*) FROM (SELECT claim_id FROM dw.fact_claims GROUP BY claim_id HAVING COUNT(*) > 1) x), 0

    /* ---- C: KPI sanity (numbers expected from the project's own calculation) ---- */
    UNION ALL SELECT 'C1 denied claims',            SUM(CAST(is_denied AS INT)), 7379 FROM dw.fact_claims
    UNION ALL SELECT 'C2 clean claims',             SUM(CAST(is_clean_claim AS INT)), 51280 FROM dw.fact_claims
    UNION ALL SELECT 'C3 SUM(claim_amount)',        SUM(claim_amount), 79637642.10 FROM dw.fact_claims
    UNION ALL SELECT 'C4 SUM(paid_amount)',         SUM(paid_amount),  45002624.64 FROM dw.fact_claims
    UNION ALL SELECT 'C5 SUM(denied_amount)',       SUM(denied_amount), 12963944.93 FROM dw.fact_claims
    UNION ALL SELECT 'C6 SUM(recovered_amount)',    SUM(recovered_amount), 1061293.38 FROM dw.fact_claims
    UNION ALL SELECT 'C7 claims with a payment',    COUNT(days_to_pay), 49184 FROM dw.fact_claims
    UNION ALL SELECT 'C8 avg days_to_pay (2 dp)',   CAST(AVG(CAST(days_to_pay AS DECIMAL(9,2))) AS DECIMAL(9,2)), 43.34 FROM dw.fact_claims
    UNION ALL SELECT 'C9 overturned appeals',       COUNT(*), 786 FROM dw.fact_claims WHERE appeal_outcome = 'Overturned'
    UNION ALL SELECT 'C10 upheld appeals',          COUNT(*), 1896 FROM dw.fact_claims WHERE appeal_outcome = 'Upheld'
) t
ORDER BY LEN(check_name), check_name;
GO

/* The three headline KPIs, ready for the README */
SELECT
    CAST(100.0 * SUM(CASE WHEN is_denied = 1 THEN 1 ELSE 0 END)
         / NULLIF(SUM(CASE WHEN claim_status IN ('Paid','Denied') THEN 1 ELSE 0 END), 0) AS DECIMAL(5,2)) AS denial_rate_pct,          -- 13.23
    CAST(100.0 * SUM(CAST(is_clean_claim AS INT)) / COUNT(*) AS DECIMAL(5,2))                           AS clean_claim_rate_pct,      -- 86.06
    CAST(100.0 * SUM(CASE WHEN appeal_outcome = 'Overturned' THEN 1 ELSE 0 END)
         / NULLIF(SUM(CASE WHEN appeal_outcome IN ('Overturned','Upheld') THEN 1 ELSE 0 END), 0) AS DECIMAL(5,2)) AS appeal_win_rate_pct  -- 29.31
FROM dw.fact_claims;
GO
