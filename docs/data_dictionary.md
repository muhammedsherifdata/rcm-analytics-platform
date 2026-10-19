# Data dictionary (raw layer)

| File | Grain | Key columns |
|---|---|---|
| `payers.csv` | one row per insurer | payer_id, payer_name, country, payer_type |
| `providers.csv` | one row per hospital or clinic | provider_id, provider_name, city, country, provider_type |
| `patients.csv` | one row per patient | patient_id, gender, birth_date |
| `claims.csv` | one row per claim submission | claim_id, patient_id, provider_id, payer_id, payer_name_submitted, claim_type, cpt_code, primary_icd10, service_date, submission_date, claim_amount, prior_auth_required, prior_auth_obtained, eligibility_verified, claim_status |
| `remittances.csv` | one row per payment received | remittance_id, claim_id, payment_date, paid_amount, patient_responsibility, contractual_adjustment, payment_type (Initial or Appeal) |
| `denials.csv` | one row per denied claim | denial_id, claim_id, denial_date, denial_code, denial_reason, denied_amount, appealed, appeal_date, appeal_outcome, recovered_amount |

`claim_status` is Paid, Denied or Pending. The extract date is 2026-09-30, and claims whose payment would fall after that date are Pending.

## Injected data-quality problems
1. Payer names typed inconsistently (case, trailing spaces, underscores)
2. Duplicate claim rows
3. Missing diagnosis codes (ICD-10)
4. Service date after submission date
5. Negative or zero claim amounts
6. Mixed date formats (`YYYY-MM-DD` and `DD/MM/YYYY`)
7. Orphan remittances (claim_id not found in claims)
8. Inconsistent gender coding in patients
