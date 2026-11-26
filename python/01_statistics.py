"""
01_statistics.py
Statistical tests for the Olist late-delivery project.

Run from the repo root:
    mkdir -p python/output
    python python/01_statistics.py | tee python/output/01_statistics_output.txt

Input: data/orders_for_stats.csv, exported by sql/05_analysis/05_export_for_python.sql
(one row per delivered order with usable dates; not committed to Git).
"""

import numpy as np
import pandas as pd
from scipy import stats
import statsmodels.formula.api as smf
from statsmodels.stats.proportion import proportions_ztest, confint_proportions_2indep

DATA_PATH = "data/orders_for_stats.csv"
OUTPUT_DIR = "python/output"
RETURN_CUTOFF = "2018-03-01"  # first orders before this date had at least ~6 months to come back
LINE = "=" * 70


def fmt_p(p):
    """Show tiny p-values as '< 0.001' instead of 0.000."""
    return "< 0.001" if p < 0.001 else f"{p:.3f}"


def mean_with_ci(values):
    """Mean and its 95% confidence interval (t-distribution)."""
    n = len(values)
    mean = values.mean()
    margin = stats.t.ppf(0.975, n - 1) * values.std(ddof=1) / np.sqrt(n)
    return mean, mean - margin, mean + margin


def compare_rates(title, count_a, n_a, count_b, n_b, label_a, label_b):
    """Two-proportion z-test and 95% CI for the difference in rates (a minus b)."""
    rate_a, rate_b = count_a / n_a, count_b / n_b
    _, p = proportions_ztest([count_a, count_b], [n_a, n_b])
    low, high = confint_proportions_2indep(count_a, n_a, count_b, n_b)
    print(LINE)
    print(title)
    print(f"  {label_a}: {count_a:,} of {n_a:,} = {rate_a:.2%}")
    print(f"  {label_b}: {count_b:,} of {n_b:,} = {rate_b:.2%}")
    print(f"  Difference: {(rate_a - rate_b) * 100:+.2f} percentage points "
          f"(95% CI {low * 100:+.2f} to {high * 100:+.2f})")
    print(f"  Two-proportion z-test p-value: {fmt_p(p)}")
    return rate_a, rate_b


# ---------------------------------------------------------------------
# Load data
# ---------------------------------------------------------------------
df = pd.read_csv(DATA_PATH)
df.columns = df.columns.str.lower()  # Snowflake exports UPPERCASE column names
print(LINE)
print(f"Rows loaded: {len(df):,} (expected 96,282)")

reviewed = df[df["review_score"].notna()]
late_rev = reviewed[reviewed["is_late"] == 1]
ontime_rev = reviewed[reviewed["is_late"] == 0]

# ---------------------------------------------------------------------
# 1. Review scores: late vs on time
# ---------------------------------------------------------------------
print(LINE)
print("1. Do late orders get lower review scores?")
for label, scores in [("Late", late_rev["review_score"]),
                      ("On time or early", ontime_rev["review_score"])]:
    mean, low, high = mean_with_ci(scores)
    print(f"  {label}: mean {mean:.2f} stars (95% CI {low:.2f} to {high:.2f}), n = {len(scores):,}")

_, p_mw = stats.mannwhitneyu(late_rev["review_score"], ontime_rev["review_score"],
                             alternative="two-sided")
print(f"  Mann-Whitney U test p-value: {fmt_p(p_mw)}")
print("  (Mann-Whitney compares whole score distributions; it suits star ratings,")
print("   which are ranked categories rather than true measurements.)")

# ---------------------------------------------------------------------
# 2. Bad-review rate: late vs on time
# ---------------------------------------------------------------------
bad_late = int(late_rev["is_bad_review"].sum())
bad_ontime = int(ontime_rev["is_bad_review"].sum())
rate_late, rate_ontime = compare_rates(
    "2. Is the bad-review rate (1-2 stars) higher for late orders?",
    bad_late, len(late_rev), bad_ontime, len(ontime_rev),
    "Late", "On time or early")

# ---------------------------------------------------------------------
# 3. How many bad reviews do late deliveries cause?
# ---------------------------------------------------------------------
total_bad = bad_late + bad_ontime
excess_bad = len(late_rev) * (rate_late - rate_ontime)
print(LINE)
print("3. How many bad reviews do late deliveries cause?")
print(f"  Late orders are {len(late_rev) / len(reviewed):.1%} of reviewed orders,")
print(f"  but {bad_late / total_bad:.1%} of all bad reviews ({bad_late:,} of {total_bad:,}).")
print(f"  If late orders had the on-time bad-review rate, there would be about "
      f"{excess_bad:,.0f} fewer bad reviews")
print(f"  ({excess_bad / total_bad:.1%} of all bad reviews).")

# ---------------------------------------------------------------------
# 4. Return rate after a late vs on-time FIRST order
# ---------------------------------------------------------------------
first = df[(df["customer_order_number"] == 1) & (df["purchase_date"] < RETURN_CUTOFF)]
late_first = first[first["is_late"] == 1]
ontime_first = first[first["is_late"] == 0]
compare_rates(
    f"4. Do customers come back less after a late FIRST order? (first orders before {RETURN_CUTOFF})",
    int(late_first["customer_ordered_again"].sum()), len(late_first),
    int(ontime_first["customer_ordered_again"].sum()), len(ontime_first),
    "Late first order", "On-time first order")
print("  (Should match the SQL: 73 of 3,667 late and 1,520 of 51,772 on time.)")

# ---------------------------------------------------------------------
# 5. Logistic regression: what predicts a bad review?
# ---------------------------------------------------------------------
print(LINE)
print("5. What predicts a bad review? (logistic regression)")

model_df = reviewed.dropna(subset=["seller_missed_deadline", "customer_region"]).copy()
model_df["multi_seller"] = (model_df["seller_count"] > 1).astype(int)    # items from 2+ sellers
model_df["multi_item"] = (model_df["item_count"] > 1).astype(int)        # 2+ items in the order
model_df["order_value_100"] = model_df["order_value"] / 100              # per R$100
model_df["customer_region"] = pd.Categorical(
    model_df["customer_region"],
    categories=["Southeast", "South", "Center-West", "Northeast", "North"])  # Southeast = baseline

formula = ("is_bad_review ~ is_late + seller_missed_deadline + multi_seller + multi_item"
           " + order_value_100 + promised_days + customer_region")
result = smf.logit(formula, data=model_df).fit(disp=False)

ci = result.conf_int()
odds = pd.DataFrame({
    "odds_ratio": np.exp(result.params),
    "ci_low": np.exp(ci[0]),
    "ci_high": np.exp(ci[1]),
}).round(2)
odds["p_value"] = result.pvalues.map(fmt_p)
odds = odds.drop(index="Intercept", errors="ignore")

print(f"  Orders in model: {int(result.nobs):,}")
print(odds.to_string())
print(f"  Pseudo R-squared: {result.prsquared:.3f}")
print("  How to read: an odds ratio of 2.0 means twice the odds of a bad review,")
print("  holding the other factors fixed. Regions are compared with the Southeast.")

odds.to_csv(f"{OUTPUT_DIR}/logit_odds_ratios.csv")
print(LINE)
print(f"Saved odds ratios to {OUTPUT_DIR}/logit_odds_ratios.csv")