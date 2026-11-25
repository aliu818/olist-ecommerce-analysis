# Data-quality log

Checks were run on the RAW layer in Snowflake before any cleaning.

- Scorecard query: `sql/02_data_quality/01_dq_scorecard.sql` (33 checks)
- Follow-up checks: `sql/02_data_quality/02_dq_followups.sql`

## Summary

All 9 tables loaded with the expected row counts. 20 of 33 checks found no problems: there are no duplicate order, customer, product or seller IDs, no missing keys and no orphan records. Every issue found affects less than 2% of rows. Each one is handled in the staging layer as described below.

## Issues and decisions

| # | Issue | Rows affected | Decision | Why |
|---|---|---|---|---|
| 1 | `customer_id` is new for every order; the real person is `customer_unique_id` | 99,441 IDs for 96,096 people | Use `customer_unique_id` as the customer key | Using `customer_id` would make every customer look like a one-time buyer |
| 2 | Orders with more than one review | 547 orders (0.55% of reviewed orders) | Keep the most recent review per order | The analysis needs one score per order |
| 3 | Same `review_id` linked to several orders | 789 review IDs (814 extra rows) | Keep; the key is `review_id` + `order_id` | One review covering several orders placed together is real behaviour |
| 4 | Orders with no review | 768 orders (0.77%) | Excluded from review analysis only | Can't measure satisfaction without a score |
| 5 | Orders with no items | 775 orders: 603 unavailable, 164 canceled, 8 other | Kept in orders; excluded from item and revenue analysis | These orders never shipped |
| 6 | Order with no payment record | 1 order | Kept and flagged | Too small to affect results |
| 7 | Handed to carrier before purchase | 166 orders | Flagged; carrier date not used for these orders | Impossible order of events, likely a recording error |
| 8 | Delivered to customer before handed to carrier | 23 orders | Flagged | Same as above |
| 9 | Status `delivered` but no delivery date | 8 orders | Excluded from delivery-time analysis | Delivery time can't be calculated |
| 10 | Has a delivery date but status isn't `delivered` | 6 orders | Excluded from delivery-time analysis | Status and dates contradict each other |
| 11 | Products with no category | 610 products (1.85%) | Category set to `unknown` | Keeps their sales in totals |
| 12 | Categories with no English translation | 13 products in 2 categories | Translated by hand: `pc_gamer`, `portable_kitchen_and_food_preparers` | Only 2 categories missing |
| 13 | Paid total differs from items + freight | 303 orders (0.31%): 264 paid more, 39 paid less; median gap R$5.90 | Revenue = item price + freight. Payments used only for payment-method analysis | Gaps look like instalment interest and vouchers |
| 14 | Zero-value payments / payment type `not_defined` | 9 / 3 payment rows | Kept; `not_defined` relabelled `unknown` | Too small to affect results |
| 15 | Misspelled source columns (`product_name_lenght`, `product_description_lenght`) | All products | Renamed in staging | RAW keeps the source exactly as delivered |

## Repeat customers (context for the analysis)

Only **2,997 of 96,096 customers (3.1%)** placed more than one order. This is why the project focuses on what makes the first order go wrong.