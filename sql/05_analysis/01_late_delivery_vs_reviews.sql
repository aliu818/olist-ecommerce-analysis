-- 01_late_delivery_vs_reviews.sql
-- Question: do late deliveries get worse reviews, and are those customers less likely to order again?
-- Population: delivered orders with usable delivery dates (is_delivery_analysable),
-- excluding the 189 orders flagged with impossible dates.

USE WAREHOUSE OLIST_WH;
USE DATABASE OLIST;
USE SCHEMA MARTS;

SELECT
  CASE
    WHEN days_late <= 0  THEN 'On time or early'
    WHEN days_late <= 3  THEN '1-3 days late'
    WHEN days_late <= 7  THEN '4-7 days late'
    WHEN days_late <= 14 THEN '8-14 days late'
    ELSE '15+ days late'
  END                                                                  AS delivery_bucket,
  COUNT(*)                                                             AS orders,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                     AS pct_of_orders,
  ROUND(AVG(review_score), 2)                                          AS avg_review_score,
  ROUND(100 * COUNT_IF(is_bad_review) / NULLIF(COUNT_IF(has_review), 0), 1) AS pct_bad_reviews,
  ROUND(100 * COUNT_IF(customer_ordered_again) / COUNT(*), 1)          AS pct_ordered_again
FROM FACT_ORDERS
WHERE is_delivery_analysable
  AND NOT has_date_issue
GROUP BY delivery_bucket
ORDER BY MIN(days_late);