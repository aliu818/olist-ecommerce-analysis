-- 05_export_for_python.sql
-- One row per delivered order with usable dates, for the Python statistics.
-- Download the result as CSV and save it as data/orders_for_stats.csv (not committed to Git).
-- Flags are 1/0 so Python can use them directly; NULL means "not known" (e.g. no review).

USE WAREHOUSE OLIST_WH;
USE DATABASE OLIST;
USE SCHEMA MARTS;

WITH seller_flag AS (
  SELECT order_id,
         BOOLOR_AGG(shipped_after_limit) AS seller_missed_deadline
  FROM FACT_ORDER_ITEMS
  GROUP BY order_id
)
SELECT
  f.order_id,
  f.purchase_date,
  TO_CHAR(f.purchase_date, 'YYYY-MM') AS purchase_month,
  f.customer_state,
  CASE
    WHEN f.customer_state IN ('AC','AP','AM','PA','RO','RR','TO')           THEN 'North'
    WHEN f.customer_state IN ('AL','BA','CE','MA','PB','PE','PI','RN','SE') THEN 'Northeast'
    WHEN f.customer_state IN ('DF','GO','MT','MS')                          THEN 'Center-West'
    WHEN f.customer_state IN ('ES','MG','RJ','SP')                          THEN 'Southeast'
    WHEN f.customer_state IN ('PR','RS','SC')                               THEN 'South'
  END                                                   AS customer_region,
  IFF(f.is_late, 1, 0)                                  AS is_late,
  f.days_late,
  f.delivery_days,
  f.promised_days,
  CASE WHEN s.seller_missed_deadline THEN 1
       WHEN NOT s.seller_missed_deadline THEN 0 END     AS seller_missed_deadline,
  f.item_count,
  f.seller_count,
  f.order_value,
  f.freight_value,
  f.main_payment_type,
  f.review_score,
  CASE WHEN f.is_bad_review THEN 1
       WHEN NOT f.is_bad_review THEN 0 END              AS is_bad_review,
  f.customer_order_number,
  IFF(f.customer_ordered_again, 1, 0)                   AS customer_ordered_again
FROM FACT_ORDERS f
LEFT JOIN seller_flag s ON f.order_id = s.order_id
WHERE f.is_delivery_analysable
  AND NOT f.has_date_issue
ORDER BY f.purchase_date;