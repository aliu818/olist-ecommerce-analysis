-- 01_dq_scorecard.sql
-- Data-quality scorecard for the RAW layer.
-- Each row is one check: how many rows fail it, out of how many were checked.
-- A failure is not always an error; docs/data_quality_log.md explains how each is handled.

USE WAREHOUSE OLIST_WH;
USE DATABASE OLIST;
USE SCHEMA RAW;

WITH
orders_typed AS (
  SELECT
    order_id,
    customer_id,
    order_status,
    TRY_TO_TIMESTAMP(order_purchase_timestamp)      AS purchased_at,
    TRY_TO_TIMESTAMP(order_approved_at)             AS approved_at,
    TRY_TO_TIMESTAMP(order_delivered_carrier_date)  AS carrier_at,
    TRY_TO_TIMESTAMP(order_delivered_customer_date) AS delivered_at
  FROM ORDERS
),
item_totals AS (
  SELECT order_id,
         SUM(TRY_TO_NUMBER(price, 12, 2) + TRY_TO_NUMBER(freight_value, 12, 2)) AS items_total
  FROM ORDER_ITEMS
  GROUP BY order_id
),
payment_totals AS (
  SELECT order_id,
         SUM(TRY_TO_NUMBER(payment_value, 12, 2)) AS paid_total
  FROM ORDER_PAYMENTS
  GROUP BY order_id
),
reviewed_orders AS (
  SELECT DISTINCT order_id FROM ORDER_REVIEWS
),
checks AS (

  -- UNIQUENESS: each ID should appear once
  SELECT 1 AS check_id, 'Uniqueness' AS category, 'ORDERS' AS table_name,
         'Duplicate order_id' AS check_description,
         COUNT(*) - COUNT(DISTINCT order_id) AS failing_rows, COUNT(*) AS rows_checked
  FROM ORDERS
  UNION ALL
  SELECT 2, 'Uniqueness', 'CUSTOMERS', 'Duplicate customer_id',
         COUNT(*) - COUNT(DISTINCT customer_id), COUNT(*) FROM CUSTOMERS
  UNION ALL
  SELECT 3, 'Uniqueness', 'PRODUCTS', 'Duplicate product_id',
         COUNT(*) - COUNT(DISTINCT product_id), COUNT(*) FROM PRODUCTS
  UNION ALL
  SELECT 4, 'Uniqueness', 'SELLERS', 'Duplicate seller_id',
         COUNT(*) - COUNT(DISTINCT seller_id), COUNT(*) FROM SELLERS
  UNION ALL
  SELECT 5, 'Uniqueness', 'ORDER_ITEMS', 'Duplicate (order_id, order_item_id)',
         COUNT(*) - COUNT(DISTINCT order_id, order_item_id), COUNT(*) FROM ORDER_ITEMS
  UNION ALL
  SELECT 6, 'Uniqueness', 'ORDER_REVIEWS', 'Duplicate review_id',
         COUNT(*) - COUNT(DISTINCT review_id), COUNT(*) FROM ORDER_REVIEWS
  UNION ALL
  SELECT 7, 'Uniqueness', 'ORDER_REVIEWS', 'Orders with more than one review',
         (SELECT COUNT(*) FROM (SELECT order_id FROM ORDER_REVIEWS
                                GROUP BY order_id HAVING COUNT(*) > 1)),
         (SELECT COUNT(*) FROM reviewed_orders)

  -- COMPLETENESS: key fields should not be empty
  UNION ALL
  SELECT 8, 'Completeness', 'ORDERS', 'Missing order_id or customer_id',
         COUNT_IF(order_id IS NULL OR customer_id IS NULL), COUNT(*) FROM ORDERS
  UNION ALL
  SELECT 9, 'Completeness', 'ORDER_ITEMS', 'Missing order_id, product_id or seller_id',
         COUNT_IF(order_id IS NULL OR product_id IS NULL OR seller_id IS NULL), COUNT(*)
  FROM ORDER_ITEMS
  UNION ALL
  SELECT 10, 'Completeness', 'ORDER_REVIEWS', 'Missing order_id or review_score',
         COUNT_IF(order_id IS NULL OR review_score IS NULL), COUNT(*) FROM ORDER_REVIEWS
  UNION ALL
  SELECT 11, 'Completeness', 'PRODUCTS', 'Missing product category',
         COUNT_IF(product_category_name IS NULL), COUNT(*) FROM PRODUCTS

  -- REFERENTIAL INTEGRITY: IDs should point to a record that exists
  UNION ALL
  SELECT 12, 'Referential integrity', 'ORDERS', 'customer_id not found in CUSTOMERS',
         COUNT_IF(c.customer_id IS NULL), COUNT(*)
  FROM ORDERS o LEFT JOIN CUSTOMERS c ON o.customer_id = c.customer_id
  UNION ALL
  SELECT 13, 'Referential integrity', 'ORDER_ITEMS', 'order_id not found in ORDERS',
         COUNT_IF(o.order_id IS NULL), COUNT(*)
  FROM ORDER_ITEMS i LEFT JOIN ORDERS o ON i.order_id = o.order_id
  UNION ALL
  SELECT 14, 'Referential integrity', 'ORDER_ITEMS', 'product_id not found in PRODUCTS',
         COUNT_IF(p.product_id IS NULL), COUNT(*)
  FROM ORDER_ITEMS i LEFT JOIN PRODUCTS p ON i.product_id = p.product_id
  UNION ALL
  SELECT 15, 'Referential integrity', 'ORDER_ITEMS', 'seller_id not found in SELLERS',
         COUNT_IF(s.seller_id IS NULL), COUNT(*)
  FROM ORDER_ITEMS i LEFT JOIN SELLERS s ON i.seller_id = s.seller_id
  UNION ALL
  SELECT 16, 'Referential integrity', 'ORDER_REVIEWS', 'order_id not found in ORDERS',
         COUNT_IF(o.order_id IS NULL), COUNT(*)
  FROM ORDER_REVIEWS r LEFT JOIN ORDERS o ON r.order_id = o.order_id
  UNION ALL
  SELECT 17, 'Referential integrity', 'ORDER_PAYMENTS', 'order_id not found in ORDERS',
         COUNT_IF(o.order_id IS NULL), COUNT(*)
  FROM ORDER_PAYMENTS pay LEFT JOIN ORDERS o ON pay.order_id = o.order_id
  UNION ALL
  SELECT 18, 'Referential integrity', 'PRODUCTS', 'Category has no English translation',
         COUNT_IF(p.product_category_name IS NOT NULL AND t.product_category_name IS NULL), COUNT(*)
  FROM PRODUCTS p
  LEFT JOIN PRODUCT_CATEGORY_TRANSLATION t ON p.product_category_name = t.product_category_name

  -- COVERAGE: every order should have items, a payment and a review
  UNION ALL
  SELECT 19, 'Coverage', 'ORDERS', 'Order has no items',
         COUNT_IF(i.order_id IS NULL), COUNT(*)
  FROM ORDERS o LEFT JOIN item_totals i ON o.order_id = i.order_id
  UNION ALL
  SELECT 20, 'Coverage', 'ORDERS', 'Order has no payment',
         COUNT_IF(p.order_id IS NULL), COUNT(*)
  FROM ORDERS o LEFT JOIN payment_totals p ON o.order_id = p.order_id
  UNION ALL
  SELECT 21, 'Coverage', 'ORDERS', 'Order has no review',
         COUNT_IF(r.order_id IS NULL), COUNT(*)
  FROM ORDERS o LEFT JOIN reviewed_orders r ON o.order_id = r.order_id

  -- DATE VALIDITY: dates should be readable and in a possible order
  UNION ALL
  SELECT 22, 'Date validity', 'ORDERS', 'Missing or unreadable purchase timestamp',
         COUNT_IF(purchased_at IS NULL), COUNT(*) FROM orders_typed
  UNION ALL
  SELECT 23, 'Date validity', 'ORDERS', 'Approved before purchased',
         COUNT_IF(approved_at < purchased_at), COUNT(*) FROM orders_typed
  UNION ALL
  SELECT 24, 'Date validity', 'ORDERS', 'Handed to carrier before purchased',
         COUNT_IF(carrier_at < purchased_at), COUNT(*) FROM orders_typed
  UNION ALL
  SELECT 25, 'Date validity', 'ORDERS', 'Delivered to customer before purchased',
         COUNT_IF(delivered_at < purchased_at), COUNT(*) FROM orders_typed
  UNION ALL
  SELECT 26, 'Date validity', 'ORDERS', 'Delivered to customer before handed to carrier',
         COUNT_IF(delivered_at < carrier_at), COUNT(*) FROM orders_typed
  UNION ALL
  SELECT 27, 'Date validity', 'ORDERS', 'Status delivered but no delivery date',
         COUNT_IF(order_status = 'delivered' AND delivered_at IS NULL), COUNT(*) FROM orders_typed
  UNION ALL
  SELECT 28, 'Date validity', 'ORDERS', 'Has delivery date but status not delivered',
         COUNT_IF(order_status <> 'delivered' AND delivered_at IS NOT NULL), COUNT(*) FROM orders_typed

  -- VALUE VALIDITY: numbers should be in a sensible range
  UNION ALL
  SELECT 29, 'Value validity', 'ORDER_REVIEWS', 'Review score not a number from 1 to 5',
         COUNT_IF(TRY_TO_NUMBER(review_score) IS NULL
                  OR TRY_TO_NUMBER(review_score) NOT BETWEEN 1 AND 5), COUNT(*)
  FROM ORDER_REVIEWS
  UNION ALL
  SELECT 30, 'Value validity', 'ORDER_ITEMS', 'Price missing, zero or negative',
         COUNT_IF(TRY_TO_NUMBER(price, 12, 2) IS NULL OR TRY_TO_NUMBER(price, 12, 2) <= 0), COUNT(*)
  FROM ORDER_ITEMS
  UNION ALL
  SELECT 31, 'Value validity', 'ORDER_PAYMENTS', 'Payment value is zero',
         COUNT_IF(TRY_TO_NUMBER(payment_value, 12, 2) = 0), COUNT(*) FROM ORDER_PAYMENTS
  UNION ALL
  SELECT 32, 'Value validity', 'ORDER_PAYMENTS', 'Payment type not_defined',
         COUNT_IF(payment_type = 'not_defined'), COUNT(*) FROM ORDER_PAYMENTS

  -- CONSISTENCY: amount paid should equal item prices + freight
  UNION ALL
  SELECT 33, 'Consistency', 'ORDER_PAYMENTS', 'Paid total differs from items + freight by > 0.01',
         COUNT_IF(ABS(p.paid_total - i.items_total) > 0.01), COUNT(*)
  FROM item_totals i JOIN payment_totals p ON i.order_id = p.order_id
)

SELECT
  check_id,
  category,
  table_name,
  check_description,
  failing_rows,
  rows_checked,
  ROUND(100 * failing_rows / NULLIF(rows_checked, 0), 2) AS pct_failing
FROM checks
ORDER BY check_id;