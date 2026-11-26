-- 03_seller_vs_carrier_delays.sql
-- Question: are late deliveries caused by sellers shipping late or by carriers taking too long?
-- seller_days  = purchase -> handed to carrier
-- carrier_days = handed to carrier -> delivered to customer
-- Population: delivered orders with usable dates and a ship date, no date issues.

USE WAREHOUSE OLIST_WH;
USE DATABASE OLIST;
USE SCHEMA MARTS;

WITH seller_flag AS (
  SELECT order_id,
         BOOLOR_AGG(shipped_after_limit) AS seller_shipped_late   -- TRUE if any item missed its deadline
  FROM FACT_ORDER_ITEMS
  GROUP BY order_id
),
orders AS (
  SELECT f.*,
         s.seller_shipped_late,
         DATEDIFF('day', f.purchased_at::DATE, f.shipped_at::DATE)  AS seller_days,
         DATEDIFF('day', f.shipped_at::DATE, f.delivered_at::DATE)  AS carrier_days
  FROM FACT_ORDERS f
  JOIN seller_flag s ON f.order_id = s.order_id
  WHERE f.is_delivery_analysable
    AND NOT f.has_date_issue
    AND f.shipped_at IS NOT NULL
    AND s.seller_shipped_late IS NOT NULL
)

-- A. Does a seller missing their deadline make late delivery more likely?
SELECT
  'A. By seller shipping'                                        AS view,
  IFF(seller_shipped_late, 'Seller missed deadline', 'Seller on time') AS grp,
  COUNT(*)                                                       AS orders,
  ROUND(100 * COUNT_IF(is_late) / COUNT(*), 1)                   AS pct_delivered_late,
  ROUND(100 * COUNT_IF(seller_shipped_late) / COUNT(*), 1)       AS pct_seller_missed_deadline,
  ROUND(AVG(seller_days), 1)                                     AS avg_seller_days,
  ROUND(AVG(carrier_days), 1)                                    AS avg_carrier_days,
  ROUND(AVG(promised_days), 1)                                   AS avg_promised_days
FROM orders
GROUP BY seller_shipped_late

UNION ALL

-- B. For late vs on-time orders, where did the time go?
SELECT
  'B. By delivery outcome',
  IFF(is_late, 'Delivered late', 'On time or early'),
  COUNT(*),
  ROUND(100 * COUNT_IF(is_late) / COUNT(*), 1),
  ROUND(100 * COUNT_IF(seller_shipped_late) / COUNT(*), 1),
  ROUND(AVG(seller_days), 1),
  ROUND(AVG(carrier_days), 1),
  ROUND(AVG(promised_days), 1)
FROM orders
GROUP BY is_late

ORDER BY view, grp;