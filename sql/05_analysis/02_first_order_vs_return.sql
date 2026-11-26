-- 02_first_order_vs_return.sql
-- Question: does a customer's FIRST order experience predict whether they order again?
-- Population: each customer's first order, delivered with usable dates, no date issues,
-- purchased before 2018-03-01 so every customer had at least ~6 months to come back.

USE WAREHOUSE OLIST_WH;
USE DATABASE OLIST;
USE SCHEMA MARTS;

WITH first_orders AS (
  SELECT *
  FROM FACT_ORDERS
  WHERE customer_order_number = 1
    AND is_delivery_analysable
    AND NOT has_date_issue
    AND purchase_date < '2018-03-01'
)

-- By review score of the first order
SELECT
  'By review score'                                            AS breakdown,
  TO_VARCHAR(review_score) || ' stars'                         AS grp,
  COUNT(*)                                                     AS first_orders,
  COUNT_IF(customer_ordered_again)                             AS came_back,
  ROUND(100 * COUNT_IF(customer_ordered_again) / COUNT(*), 2)  AS pct_came_back
FROM first_orders
WHERE has_review
GROUP BY review_score

UNION ALL

-- By whether the first order was late
SELECT
  'By delivery',
  IFF(is_late, 'Late', 'On time or early'),
  COUNT(*),
  COUNT_IF(customer_ordered_again),
  ROUND(100 * COUNT_IF(customer_ordered_again) / COUNT(*), 2)
FROM first_orders
GROUP BY is_late

ORDER BY breakdown, grp;