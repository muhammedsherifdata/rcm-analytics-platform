"""
Synthetic Healthcare RCM data generator (MENA region).

Produces realistic-but-fake claims data with a KNOWN ground truth, plus
deliberately injected data-quality problems so the cleaning pipeline and
validation checks have something real to catch.

Run:  python src/generate_data.py
Output: data/raw/*.csv  and  data/ground_truth/injected_issues.json
"""
import json
from pathlib import Path

import numpy as np
import pandas as pd

SEED = 42
N_PATIENTS = 20_000
N_CLAIMS = 60_000
START = pd.Timestamp("2024-01-01")
END = pd.Timestamp("2026-09-30")      # "as-of" date of the extract
TIMELY_FILING_DAYS = 90

rng = np.random.default_rng(SEED)
ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw"
TRUTH = ROOT / "data" / "ground_truth"
RAW.mkdir(parents=True, exist_ok=True)
TRUTH.mkdir(parents=True, exist_ok=True)

# ----------------------------------------------------------------- payers
payers = pd.DataFrame(
    [
        # id, name, country, type, denial_bias (logit), pay_lag_mean_days, allowed_ratio
        (1, "Bupa Arabia", "KSA", "Private", 0.10, 28, 0.82),
        (2, "Tawuniya", "KSA", "Private", 0.30, 35, 0.80),
        (3, "MedGulf", "KSA", "Private", 0.55, 42, 0.78),
        (4, "Saudi Social Insurance", "KSA", "Government", 0.20, 55, 0.70),
        (5, "Daman", "UAE", "Government", -0.10, 24, 0.85),
        (6, "Thiqa", "UAE", "Government", -0.20, 22, 0.88),
        (7, "Neuron", "UAE", "Private", 0.25, 33, 0.81),
        (8, "Oman Insurance", "UAE", "Private", 0.45, 40, 0.79),
        (9, "Health Insurance Organization", "Egypt", "Government", 0.60, 70, 0.62),
        (10, "Misr Insurance", "Egypt", "Private", 0.35, 48, 0.74),
        (11, "AXA Egypt", "Egypt", "Private", 0.15, 36, 0.80),
        (12, "MetLife Egypt", "Egypt", "Private", 0.25, 40, 0.77),
        (13, "Allianz Egypt", "Egypt", "Private", 0.50, 45, 0.76),
        (14, "Jordan Insurance", "Jordan", "Private", 0.30, 38, 0.80),
        (15, "Arab Orient Takaful", "Jordan", "Private", 0.65, 52, 0.75),
        (16, "Royal Medical Services", "Jordan", "Government", 0.05, 30, 0.84),
    ],
    columns=["payer_id", "payer_name", "country", "payer_type",
             "denial_bias", "pay_lag_mean_days", "allowed_ratio"],
)

# -------------------------------------------------------------- providers
providers = pd.DataFrame(
    [
        (1, "Riyadh Central Hospital", "Riyadh", "KSA", "General", 0.90),
        (2, "Jeddah Specialist Clinic", "Jeddah", "KSA", "Specialty", 0.80),
        (3, "Dammam Medical Center", "Dammam", "KSA", "General", 0.60),
        (4, "Dubai Care Hospital", "Dubai", "UAE", "General", 0.95),
        (5, "Abu Dhabi Heart Institute", "Abu Dhabi", "UAE", "Specialty", 0.85),
        (6, "Sharjah Family Clinic", "Sharjah", "UAE", "Clinic", 0.65),
        (7, "Cairo University Hospital", "Cairo", "Egypt", "General", 0.55),
        (8, "Alexandria Medical Center", "Alexandria", "Egypt", "General", 0.60),
        (9, "Giza Specialty Hospital", "Giza", "Egypt", "Specialty", 0.75),
        (10, "Nile Care Clinic", "Cairo", "Egypt", "Clinic", 0.50),
        (11, "Amman Medical City", "Amman", "Jordan", "General", 0.85),
        (12, "Irbid Community Hospital", "Irbid", "Jordan", "General", 0.60),
    ],
    columns=["provider_id", "provider_name", "city", "country",
             "provider_type", "coding_quality"],
)

# --------------------------------------------------------------- patients
patients = pd.DataFrame(
    {
        "patient_id": np.arange(1, N_PATIENTS + 1),
        "gender": rng.choice(["M", "F"], N_PATIENTS, p=[0.48, 0.52]),
        "birth_date": (pd.Timestamp("2026-01-01")
                       - pd.to_timedelta(rng.integers(0, 85 * 365, N_PATIENTS), unit="D")).normalize(),
    }
)

# ------------------------------------------------------------ code lists
CPT = {  # code: (description, base_amount, claim_type)
    "99213": ("Office visit, established", 120, "Outpatient"),
    "99214": ("Office visit, detailed", 190, "Outpatient"),
    "99203": ("Office visit, new patient", 160, "Outpatient"),
    "80053": ("Comprehensive metabolic panel", 60, "Outpatient"),
    "85025": ("Complete blood count", 45, "Outpatient"),
    "71046": ("Chest X-ray", 110, "Outpatient"),
    "93000": ("ECG", 80, "Outpatient"),
    "70553": ("MRI brain with contrast", 900, "Outpatient"),
    "74177": ("CT abdomen/pelvis", 750, "Outpatient"),
    "45378": ("Colonoscopy", 1100, "Outpatient"),
    "43239": ("Upper GI endoscopy", 950, "Outpatient"),
    "99285": ("Emergency visit, high severity", 650, "Emergency"),
    "99283": ("Emergency visit, moderate", 380, "Emergency"),
    "99223": ("Initial hospital care", 1800, "Inpatient"),
    "27447": ("Total knee replacement", 14000, "Inpatient"),
    "47562": ("Laparoscopic cholecystectomy", 6500, "Inpatient"),
    "59510": ("Cesarean delivery", 5200, "Inpatient"),
    "D1110": ("Dental cleaning", 70, "Dental"),
    "D2391": ("Dental filling", 140, "Dental"),
    "D7140": ("Tooth extraction", 180, "Dental"),
}
ICD10 = ["I10", "E11.9", "J06.9", "M54.5", "K21.9", "N39.0", "J45.909", "E78.5",
         "R10.9", "Z00.00", "O80", "S93.401A", "K80.20", "M17.11", "I25.10",
         "F41.9", "L30.9", "H10.9", "K35.80", "Z23"]
CLAIM_TYPE_P = {"Outpatient": 0.62, "Emergency": 0.13, "Inpatient": 0.14, "Dental": 0.11}

DENIAL_CODES = {
    "ELIG": ("CO-27", "Coverage not active / eligibility"),
    "AUTH": ("CO-197", "Prior authorization missing"),
    "CODING": ("CO-16", "Coding error / missing information"),
    "LATE": ("CO-29", "Timely filing limit exceeded"),
    "MEDNEC": ("CO-50", "Not medically necessary"),
    "DUP": ("CO-18", "Duplicate claim"),
}

# ----------------------------------------------------------------- claims
claim_id = np.arange(1, N_CLAIMS + 1)
provider_id = rng.choice(providers.provider_id, N_CLAIMS,
                         p=np.array([.11, .08, .06, .13, .07, .05, .12, .08, .07, .05, .10, .08]))
country_of_provider = providers.set_index("provider_id").loc[provider_id, "country"].to_numpy()

payer_id = np.zeros(N_CLAIMS, dtype=int)
for c in providers.country.unique():
    mask = country_of_provider == c
    pool = payers[payers.country == c]
    w = rng.dirichlet(np.ones(len(pool)) * 4)
    payer_id[mask] = rng.choice(pool.payer_id, mask.sum(), p=w)

patient_id = rng.integers(1, N_PATIENTS + 1, N_CLAIMS)

# service date: mild upward trend in volume
span = (END - START).days
service_offset = (span * rng.beta(1.25, 1.0, N_CLAIMS)).astype(int)
service_date = START + pd.to_timedelta(service_offset, unit="D")

cpt_codes = np.array(list(CPT))
claim_type = rng.choice(list(CLAIM_TYPE_P), N_CLAIMS, p=list(CLAIM_TYPE_P.values()))
cpt = np.empty(N_CLAIMS, dtype=object)
for t in CLAIM_TYPE_P:
    m = claim_type == t
    options = [c for c in cpt_codes if CPT[c][2] == t]
    cpt[m] = rng.choice(options, m.sum())
base = np.array([CPT[c][1] for c in cpt], dtype=float)
claim_amount = np.round(base * rng.lognormal(0, 0.25, N_CLAIMS), 2)

# submission lag (days after service)
lag = rng.gamma(2.2, 2.0, N_CLAIMS).round().astype(int) + 1
late_mask = rng.random(N_CLAIMS) < 0.035
lag[late_mask] = rng.integers(91, 150, late_mask.sum())
submission_date = service_date + pd.to_timedelta(lag, unit="D")

# root-cause flags (ground truth)
coding_q = providers.set_index("provider_id").loc[provider_id, "coding_quality"].to_numpy()
coding_error = rng.random(N_CLAIMS) < (0.02 + 0.10 * (1 - coding_q))
eligibility_verified = rng.random(N_CLAIMS) < (0.88 + 0.10 * coding_q)
auth_required = (claim_type == "Inpatient") | ((claim_amount > 700) & (claim_type == "Outpatient"))
auth_obtained = np.where(auth_required, rng.random(N_CLAIMS) < (0.70 + 0.25 * coding_q), True)
late_filing = lag > TIMELY_FILING_DAYS
clean_claim = (~coding_error) & eligibility_verified & auth_obtained & (~late_filing)

# denial probability
payer_bias = payers.set_index("payer_id").loc[payer_id, "denial_bias"].to_numpy()
logit = (-3.3 + payer_bias
         + 2.1 * (~eligibility_verified)
         + 2.6 * (auth_required & ~auth_obtained)
         + 2.3 * coding_error
         + 4.0 * late_filing
         + 0.12 * np.log1p(claim_amount) / 2)
p_denied = 1 / (1 + np.exp(-logit))
denied_flag = rng.random(N_CLAIMS) < p_denied


def pick_reason(i):
    causes = []
    if late_filing[i]: causes.append("LATE")
    if not eligibility_verified[i]: causes.append("ELIG")
    if auth_required[i] and not auth_obtained[i]: causes.append("AUTH")
    if coding_error[i]: causes.append("CODING")
    if causes:
        return rng.choice(causes)
    return rng.choice(["MEDNEC", "DUP"], p=[0.7, 0.3])


# payment timing
pay_mean = payers.set_index("payer_id").loc[payer_id, "pay_lag_mean_days"].to_numpy()
pay_lag = rng.gamma(4.0, pay_mean / 4.0).round().astype(int) + 3
payment_date = submission_date + pd.to_timedelta(pay_lag, unit="D")
allowed_ratio = payers.set_index("payer_id").loc[payer_id, "allowed_ratio"].to_numpy()

claims = pd.DataFrame({
    "claim_id": claim_id, "patient_id": patient_id, "provider_id": provider_id,
    "payer_id": payer_id, "claim_type": claim_type, "cpt_code": cpt,
    "primary_icd10": rng.choice(ICD10, N_CLAIMS),
    "service_date": service_date, "submission_date": submission_date,
    "claim_amount": claim_amount,
    "prior_auth_required": auth_required, "prior_auth_obtained": auth_obtained,
    "eligibility_verified": eligibility_verified,
})

# remittances & denials -------------------------------------------------
rem_rows, den_rows = [], []
rem_id = den_id = 1
claim_status = []
for i in range(N_CLAIMS):
    cid = int(claim_id[i])
    if payment_date[i] > END:
        claim_status.append("Pending")
        continue
    if not denied_flag[i]:
        allowed = round(claim_amount[i] * allowed_ratio[i], 2)
        patient_resp = round(allowed * rng.choice([0, 0.1, 0.2], p=[.4, .35, .25]), 2)
        rem_rows.append((rem_id, cid, payment_date[i], allowed - patient_resp,
                         patient_resp, round(claim_amount[i] - allowed, 2), "Initial"))
        rem_id += 1
        claim_status.append("Paid")
    else:
        key = pick_reason(i)
        code, desc = DENIAL_CODES[key]
        appealed = rng.random() < 0.38
        outcome, recovered, appeal_date = None, 0.0, pd.NaT
        if appealed:
            appeal_date = payment_date[i] + pd.Timedelta(days=int(rng.integers(5, 30)))
            win_p = {"CODING": 0.62, "AUTH": 0.35, "ELIG": 0.25, "MEDNEC": 0.40,
                     "LATE": 0.05, "DUP": 0.10}[key]
            if appeal_date > END:
                outcome = "In Review"
            elif rng.random() < win_p:
                outcome = "Overturned"
                recovered = round(claim_amount[i] * allowed_ratio[i], 2)
                rem_rows.append((rem_id, cid, appeal_date + pd.Timedelta(days=int(rng.integers(10, 40))),
                                 recovered, 0.0, round(claim_amount[i] - recovered, 2), "Appeal"))
                rem_id += 1
            else:
                outcome = "Upheld"
        den_rows.append((den_id, cid, payment_date[i], code, desc, claim_amount[i],
                         appealed, appeal_date, outcome, recovered, key))
        den_id += 1
        claim_status.append("Denied")

claims["claim_status"] = claim_status
claims["clean_claim_flag"] = clean_claim

remittances = pd.DataFrame(rem_rows, columns=[
    "remittance_id", "claim_id", "payment_date", "paid_amount",
    "patient_responsibility", "contractual_adjustment", "payment_type"])
denials = pd.DataFrame(den_rows, columns=[
    "denial_id", "claim_id", "denial_date", "denial_code", "denial_reason",
    "denied_amount", "appealed", "appeal_date", "appeal_outcome",
    "recovered_amount", "_root_cause"])
# root cause is ground truth only: keep it out of the raw file
denials_truth = denials[["denial_id", "claim_id", "_root_cause"]].copy()
denials = denials.drop(columns="_root_cause")

# ------------------------------------------------- inject dirty data
issues = {}
claims_dirty = claims.copy()
claims_dirty["service_date"] = claims_dirty["service_date"].dt.strftime("%Y-%m-%d")
claims_dirty["submission_date"] = claims_dirty["submission_date"].dt.strftime("%Y-%m-%d")

# 1) payer name as submitted (free text, messy) -------------------------
name_map = payers.set_index("payer_id").payer_name.to_dict()
submitted = claims_dirty.payer_id.map(name_map)
r = rng.random(len(submitted))
submitted = np.where(r < 0.06, submitted.str.upper(), submitted)
submitted = np.where((r >= 0.06) & (r < 0.10), submitted.astype(str) + " ", submitted)
submitted = np.where((r >= 0.10) & (r < 0.13), pd.Series(submitted).str.replace(" ", "_"), submitted)
claims_dirty.insert(4, "payer_name_submitted", submitted)
issues["payer_name_variants_rows"] = int((r < 0.13).sum())

# 2) duplicate claim rows ----------------------------------------------
dup_idx = rng.choice(len(claims_dirty), int(0.012 * len(claims_dirty)), replace=False)
claims_dirty = pd.concat([claims_dirty, claims_dirty.iloc[dup_idx]], ignore_index=True)
issues["exact_duplicate_claim_rows"] = len(dup_idx)

# 3) missing diagnosis codes -------------------------------------------
n = len(claims_dirty)
idx = rng.choice(n, int(0.01 * n), replace=False)
claims_dirty.loc[idx, "primary_icd10"] = None
issues["null_icd10_rows"] = len(idx)

# 4) service date AFTER submission date (swapped) ----------------------
idx = rng.choice(n, int(0.005 * n), replace=False)
tmp = claims_dirty.loc[idx, "service_date"].copy()
claims_dirty.loc[idx, "service_date"] = claims_dirty.loc[idx, "submission_date"]
claims_dirty.loc[idx, "submission_date"] = tmp
issues["service_after_submission_rows"] = len(idx)

# 5) negative / zero claim amounts -------------------------------------
idx = rng.choice(n, int(0.002 * n), replace=False)
claims_dirty.loc[idx[: len(idx) // 2], "claim_amount"] *= -1
claims_dirty.loc[idx[len(idx) // 2:], "claim_amount"] = 0
issues["negative_or_zero_amount_rows"] = len(idx)

# 6) mixed date formats (dd/mm/yyyy) -----------------------------------
idx = rng.choice(n, int(0.03 * n), replace=False)
claims_dirty.loc[idx, "service_date"] = pd.to_datetime(
    claims_dirty.loc[idx, "service_date"], errors="coerce").dt.strftime("%d/%m/%Y")
issues["mixed_date_format_rows"] = len(idx)

# 7) orphan remittances (claim_id that does not exist) -----------------
orph = remittances.sample(40, random_state=SEED).copy()
orph["remittance_id"] = np.arange(remittances.remittance_id.max() + 1,
                                  remittances.remittance_id.max() + 1 + len(orph))
orph["claim_id"] = rng.integers(900_000, 999_999, len(orph))
remittances = pd.concat([remittances, orph], ignore_index=True)
issues["orphan_remittance_rows"] = len(orph)

# 8) inconsistent gender coding in patients ----------------------------
g = patients.gender.copy()
idx = rng.choice(len(g), int(0.04 * len(g)), replace=False)
g.iloc[idx] = rng.choice(["male", "Female", "m", "f", "MALE", "unknown"], len(idx))
patients["gender"] = g
issues["inconsistent_gender_rows"] = len(idx)

# ------------------------------------------------------------- write out
payers.drop(columns=["denial_bias", "pay_lag_mean_days", "allowed_ratio"]).to_csv(RAW / "payers.csv", index=False)
providers.drop(columns=["coding_quality"]).to_csv(RAW / "providers.csv", index=False)
patients.to_csv(RAW / "patients.csv", index=False)
claims_dirty.drop(columns=["clean_claim_flag"]).to_csv(RAW / "claims.csv", index=False)
remittances.to_csv(RAW / "remittances.csv", index=False)
denials.to_csv(RAW / "denials.csv", index=False)

# ground truth (answer key) — kept separate on purpose
claims[["claim_id", "clean_claim_flag"]].to_csv(TRUTH / "clean_claim_truth.csv", index=False)
denials_truth.to_csv(TRUTH / "denial_root_cause_truth.csv", index=False)
issues["note"] = "Counts of deliberately injected defects, for validating DQ checks."
(TRUTH / "injected_issues.json").write_text(json.dumps(issues, indent=2))

print("claims (raw, incl. dups):", len(claims_dirty))
print("remittances:", len(remittances), "| denials:", len(denials))
print(json.dumps(issues, indent=2))
