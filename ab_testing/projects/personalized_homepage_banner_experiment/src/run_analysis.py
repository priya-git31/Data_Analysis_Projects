
import pandas as pd
import numpy as np
from scipy import stats

users = pd.read_csv("users.csv", parse_dates=["signup_date"])
assignment = pd.read_csv("experiment_assignment.csv", parse_dates=["entry_date"])
events = pd.read_csv("page_events.csv", parse_dates=["event_timestamp"])
orders = pd.read_csv("orders.csv", parse_dates=["order_timestamp"])

population = users.merge(assignment[["user_id", "variant", "entry_date"]], on="user_id", how="inner")

click_flags = (
    events.query("event_type == 'banner_click'")
    .groupby("user_id", as_index=False)
    .size()
    .rename(columns={"size": "clicked_banner"})
)
click_flags["clicked_banner"] = 1

atc_flags = (
    events.query("event_type == 'add_to_cart'")
    .groupby("user_id", as_index=False)
    .size()
    .rename(columns={"size": "added_to_cart"})
)
atc_flags["added_to_cart"] = 1

purchase_flags = (
    orders.groupby("user_id", as_index=False)
    .agg(purchased=("order_id", "size"), revenue=("order_value", "sum"))
)
purchase_flags["purchased"] = 1

ab = (
    population
    .merge(click_flags[["user_id", "clicked_banner"]], on="user_id", how="left")
    .merge(atc_flags[["user_id", "added_to_cart"]], on="user_id", how="left")
    .merge(purchase_flags[["user_id", "purchased", "revenue"]], on="user_id", how="left")
)
for col in ["clicked_banner", "added_to_cart", "purchased", "revenue"]:
    ab[col] = ab[col].fillna(0)

summary = (
    ab.groupby("variant", as_index=False)
      .agg(users=("user_id", "nunique"),
           clicks=("clicked_banner", "sum"),
           add_to_carts=("added_to_cart", "sum"),
           purchasers=("purchased", "sum"),
           total_revenue=("revenue", "sum"))
)

summary["ctr"] = summary["clicks"] / summary["users"]
summary["add_to_cart_rate"] = summary["add_to_carts"] / summary["users"]
summary["conversion_rate"] = summary["purchasers"] / summary["users"]
summary["revenue_per_visitor"] = summary["total_revenue"] / summary["users"]

aov = orders.groupby("variant", as_index=False).agg(aov=("order_value", "mean"))
summary = summary.merge(aov, on="variant", how="left")

print(summary)

def two_prop_test(success_c, total_c, success_t, total_t):
    p_c = success_c / total_c
    p_t = success_t / total_t
    pooled = (success_c + success_t) / (total_c + total_t)
    se = np.sqrt(pooled * (1 - pooled) * ((1/total_c) + (1/total_t)))
    z = (p_t - p_c) / se
    p_value = 2 * (1 - stats.norm.cdf(abs(z)))
    return z, p_value, p_c, p_t, ((p_t - p_c) / p_c) * 100

control = summary.loc[summary["variant"] == "control"].iloc[0]
treatment = summary.loc[summary["variant"] == "treatment"].iloc[0]

for metric, success_col in [("CTR", "clicks"), ("ATC", "add_to_carts"), ("Conversion", "purchasers")]:
    z, p, p_c, p_t, lift = two_prop_test(control[success_col], control["users"], treatment[success_col], treatment["users"])
    print(f"{metric}: control={p_c:.4%}, treatment={p_t:.4%}, relative lift={lift:.2f}%, p-value={p:.6f}")

t_stat, aov_p = stats.ttest_ind(
    orders.loc[orders["variant"] == "control", "order_value"],
    orders.loc[orders["variant"] == "treatment", "order_value"],
    equal_var=False
)
print(f"AOV p-value: {aov_p:.6f}")
