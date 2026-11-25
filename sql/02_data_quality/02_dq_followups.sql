-- 02_dq_followups.sql
-- Follow-up questions raised by the scorecard, so the data-quality log is based on facts.

USE WAREHOUSE OLIST_WH;
USE DATABASE OLIST;
USE SCHEMA RAW;

WITH
item_totals AS (
  SELECT order_id,
         SUM(TRY_TO_NUMBER(price, 12, 2) + TRY_TO_NUMBER(freight_value, 12, 2)) AS items_total
  FROM ORDER_ITEMS
  GROUP BY order_id
),
payment_diffs AS (
  SELECT i.order_id,
         SUM(TRY_TO_NUMBER(p.payment_value, 12, 2)) - MAX(i.items_total) AS diff
  FROM item_totals i
  JOIN ORDER_PAYMENTS p ON i.order_id = p.order_id
  GROUP BY i.order_id
  HAVING ABS(diff) > 0.01
)

-- A. What status are the orders with no items?
SELECT 'A. Orders with no items' AS question, o.order_status AS detail, COUNT(*) AS value
FROM ORDERS o
LEFT JOIN item_totals i ON o.order_id = i.order_id
WHERE i.order_id IS NULL
GROUP BY o.order_status

-- B. Which categories have no English translation?
UNION ALL
SELECT 'B. Untranslated categories', p.product_category_name, COUNT(*)
FROM PRODUCTS p
LEFT JOIN PRODUCT_CATEGORY_TRANSLATION t ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NOT NULL AND t.product_category_name IS NULL
GROUP BY p.product_category_name

-- C. customer_id vs customer_unique_id
UNION ALL
SELECT 'C. Customers', 'distinct customer_id (one per order)', COUNT(DISTINCT customer_id) FROM CUSTOMERS
UNION ALL
SELECT 'C. Customers', 'distinct customer_unique_id (real people)', COUNT(DISTINCT customer_unique_id) FROM CUSTOMERS
UNION ALL
SELECT 'C. Customers', 'people with 2+ orders', COUNT(*)
FROM (SELECT c.customer_unique_id
      FROM CUSTOMERS c JOIN ORDERS o ON c.customer_id = o.customer_id
      GROUP BY c.customer_unique_id
      HAVING COUNT(DISTINCT o.order_id) > 1)

-- D. Payment mismatches: direction and size
UNION ALL
SELECT 'D. Payment mismatch',
       CASE WHEN diff > 0 THEN 'paid MORE than items + freight' ELSE 'paid LESS than items + freight' END,
       COUNT(*)
FROM payment_diffs
GROUP BY 2
UNION ALL
SELECT 'D. Payment mismatch', 'median absolute difference (BRL)', MEDIAN(ABS(diff)) FROM payment_diffs

-- E. Is a duplicated review_id one review linked to several orders?
UNION ALL
SELECT 'E. Duplicate review_ids', 'review_ids linked to 2+ different orders', COUNT(*)
FROM (SELECT review_id FROM ORDER_REVIEWS
      GROUP BY review_id HAVING COUNT(DISTINCT order_id) > 1)

ORDER BY 1, 3 DESC;