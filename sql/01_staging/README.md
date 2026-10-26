# 01_staging

Loads the raw CSV files into SQL Server exactly as they arrive, then profiles them to measure every data-quality problem **before** any cleaning.

## Principle
Staging (`stg.*`) is a faithful copy of the source. All columns are `NVARCHAR`, nothing is rejected or fixed at load time, so every problem stays visible and countable. Fixes happen later in the `clean` layer.

## Files
| File | Purpose |
|---|---|
| `01_create_staging.sql` | Creates the `RCM` database, the `stg`, `clean` and `dw` schemas, and six all-text staging tables |
| `02_load_csv.sql` | `BULK INSERT` of the six CSVs and a row-count control against the expected counts |
| `03_profiling.sql` | Queries that find and count each injected data-quality problem |

## How to run
1. Copy the six CSVs from `data/raw/` to `C:\RCM_Data\raw\` (the folder must be readable by the SQL Server service account).
2. Run `01_create_staging.sql`.
3. Set `@path` in `02_load_csv.sql` if your folder differs, then run it. Every row of the control table must show `OK`.
4. Run `03_profiling.sql`.

Files use `\n` line endings, so the load uses `ROWTERMINATOR = '0x0a'`.

## Load control
| Table | Rows |
|---|---|
| payers | 16 |
| providers | 12 |
| patients | 20,000 |
| claims | 60,720 |
| remittances | 49,569 |
| denials | 7,424 |

## Profiling results
| Problem | Rows found |
|---|---|
| Duplicate claims | 720 |
| Missing ICD-10 code | 607 (1.00% of claims) |
| Service date after submission date | 303 |
| Claim amount zero or negative | 121 |
| Dates in `DD/MM/YYYY` (`service_date`) | 1,821 |
| Orphan remittances (claim not found) | 40 |
| Non-standard gender values | 800 |
| Payer name variants | 7,654 rows |

## Findings worth noting
- The 303 invalid date sequences only appear after both date formats are parsed (`TRY_CONVERT` styles 23 and 103). Checking ISO dates alone finds 291, because 12 rows sit among the `DD/MM/YYYY` dates.
- SQL Server's default collation is case-insensitive and ignores trailing spaces, so a plain `GROUP BY` hides variants such as `f` vs `F` or `MALE` vs `male`. Counting them correctly needs `COLLATE Latin1_General_BIN2`.
- `unknown` (143 patients) is a missing value, not a gender, and is handled in the clean layer.

## Next
`02_cleaning`: build `clean.*` from `stg.*`, remove duplicates, standardize values, parse dates, and move invalid rows to a quarantine table with a reject reason.
