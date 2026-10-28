# 03_warehouse

Star schema (`dw`) built from the validated `clean` layer. This is the only layer Power BI reads.

## Model
```
                 dim_date (role-playing: service, submission, payment, denial)
                     |
dim_payer ----- fact_claims ----- dim_provider
                     |
        dim_patient     dim_denial_reason
```
**Grain:** one row in `fact_claims` = one valid claim (59,586 rows). The 414 quarantined claims never enter the warehouse.

## Run order
| Order | File | Builds |
|---|---|---|
| 1 | `01_dim_date.sql` | Resets `dw`, creates `dim_date` (2024-01-01 to 2027-12-31, 1,461 rows) |
| 2 | `02_dimensions.sql` | `dim_payer`, `dim_provider`, `dim_patient`, `dim_denial_reason` |
| 3 | `03_fact_claims.sql` | `fact_claims` with foreign keys to every dimension |
| 4 | `04_validate_dw.sql` | Row counts, reconciliation with `clean`, KPI sanity. All rows must show `PASS` |

## Design decisions
- **Natural keys.** Dimensions never change in this dataset, so source ids (`payer_id`...) are used as keys instead of surrogate keys. Surrogate keys and SCD Type 2 would be needed if payer or provider attributes changed over time.
- **Roll up before joining.** Remittances and denials are aggregated to claim level before they join the fact, so no claim can be counted twice.
- **Role-playing date dimension.** `fact_claims` has four date keys (service, submission, payment, denial), all referencing `dim_date`. In Power BI one relationship is active and the others use `USERELATIONSHIP`.
- **Flags as BIT.** `is_denied`, `is_clean_claim` and `is_appealed` are 0/1 so DAX can sum them.
- **Clean claim.** Eligibility verified, authorization obtained when required, filed within 90 days, ICD-10 present, and not denied for a coding error.
- **Preventable denials.** `dim_denial_reason.is_preventable` marks eligibility, authorization, coding and timely filing (4,297 of 7,379 denials, 58.2%).
- **Weekend.** `is_weekend` marks Friday and Saturday, the weekend in Egypt, KSA and UAE.

## Headline numbers
| KPI | Value |
|---|---|
| Valid claims | 59,586 |
| Denial rate (Paid + Denied) | 13.23% |
| Clean claim rate | 86.06% |
| Appeal success rate (Overturned / decided) | 29.31% |
| Average days to pay | 43.34 |
| Billed amount | 79,637,642.10 |
| Paid amount | 45,002,624.64 |
| Denied amount | 12,963,944.93 |
| Recovered amount | 1,061,293.38 |

## Known limitations
- **Dates after the extract date.** The extract date is 2026-09-30, but 614 pending claims have a submission date after it, and 26 appeal payments are dated after it. The generator allows submission lag to run past the extract. These rows are kept and documented; they do not affect the denial rate because pending claims are excluded from it.
- **Clean claim rate is measured, not true.** Some coding errors are invisible in the claims table (a claim can have a wrong code and still be paid), so the observable clean claim rate is higher than the real one used to generate the data.
- **Age is measured at the extract date**, so `dim_patient` is static.
