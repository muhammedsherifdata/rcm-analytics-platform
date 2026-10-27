# 02_cleaning

Builds the `clean` schema from `stg`. Staging is never modified: every clean table can be rebuilt from it at any time.

## Run order
Always run in this order (the scripts drop and rebuild their tables):

| Order | File | Builds |
|---|---|---|
| 1 | `01_clean_dimensions.sql` | `clean.payers`, `clean.providers`, `clean.map_gender`, `clean.patients` |
| 2 | `02_clean_claims.sql` | `clean.claims`, views `clean.v_claims_valid` and `clean.v_claims_quarantine` |
| 3 | `03_clean_remittances_denials.sql` | `clean.remittances`, `clean.quarantine_remittances`, `clean.denials` |
| 4 | `04_validate_clean.sql` | Reconciliation and re-check of every problem. All rows must show `PASS` |

Requires SQL Server 2017 or later (`CONCAT_WS`).

## Problems and how each is handled
| Problem (raw) | Rows | Treatment |
|---|---|---|
| Duplicate claims | 720 | One row kept per `claim_id` (`ROW_NUMBER`). In 70 pairs the copies differ, so the copy with the fewest problems is kept |
| Payer names typed inconsistently | 7,654 | Not fixed by text. The official name comes from `clean.payers` through `payer_id`; the typed name is kept only as `payer_name_submitted` for audit |
| Mixed date formats (`DD/MM/YYYY`) | 1,821 | `COALESCE(TRY_CONVERT(date, x, 23), TRY_CONVERT(date, x, 103))` |
| Missing ICD-10 | 588 after dedup | Set to `UNKNOWN` and `icd10_missing = 1`. The claim is financially valid, so it stays in the analysis |
| Claim amount zero or negative | 116 after dedup | Flagged `QUARANTINE` (`dq_reason = non_positive_amount`) |
| Service date after submission date | 299 after dedup | Flagged `QUARANTINE` (`service_after_submission`) |
| Orphan remittances | 40 | Moved to `clean.quarantine_remittances` with a reject reason |
| Inconsistent gender | 800 | `clean.map_gender` lookup (`F`, `M`, `Unknown`) |
| Amounts and flags stored as text | all | `DECIMAL(12,2)` and `BIT`; also removes float noise such as `483.79999999999995` |

One claim has both a bad amount and a reversed date, so 414 claims are flagged in total.

## Design decisions
- **Flag instead of delete.** Remittances and denials reference claims. Deleting a claim would orphan its payments, so flagged claims stay in `clean.claims` and reports read `clean.v_claims_valid`.
- **Fail loudly.** Clean columns are `NOT NULL` and use `CHECK` and foreign keys. A value that cannot be converted stops the load instead of becoming a silent wrong value.
- **Case-sensitive mapping.** `map_gender.raw_value` uses `Latin1_General_BIN2`, because the default collation is case-insensitive and would merge `f` and `F`.
- **Dedup by quality, not by chance.** Picking an arbitrary copy could keep the one with the injected error.

## Expected results
| Table | Rows |
|---|---|
| `clean.payers` | 16 |
| `clean.providers` | 12 |
| `clean.patients` | 20,000 |
| `clean.claims` | 60,000 (59,586 valid, 414 quarantine) |
| `clean.remittances` | 49,529 |
| `clean.quarantine_remittances` | 40 |
| `clean.denials` | 7,424 |
