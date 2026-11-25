-- 01_star_schema.sql
-- Star schema for analysis: 2 fact tables and 4 dimension tables, built from STAGING.

USE WAREHOUSE OLIST_WH;
USE DATABASE OLIST;
USE SCHEMA MARTS;

------------------------------------------------------------
-- FACT_ORDERS: one row per order
------------------------------------------------------------
CREATE OR REPLACE TABLE FACT_ORDERS AS
WITH
items AS (
  SELECT order_id,
         COUNT(*)                  AS item_count,
         COUNT(DISTINCT seller_id) AS seller_count,
         SUM(price)                AS items_value,
         SUM(freight_value)        AS freight_value
  FROM STAGING.STG_ORDER_ITEMS
  GROUP BY order_id
),
payments AS (
  SELECT order_id,
         SUM(payment_value)                  AS payment_value,
         MAX_BY(payment_type, payment_value) AS main_payment_type,
         MAX(payment_installments)           AS max_installments
  FROM STAGING.STG_ORDER_PAYMENTS
  GROUP BY order_id
),
orders AS (
  SELECT o.*, c.customer_unique_id, c.customer_state
  FROM STAGING.STG_ORDERS o
  JOIN STAGING.STG_CUSTOMERS c ON o.customer_id = c.customer_id
),
-- Orders that count towards "coming back": not canceled or unavailable
valid_orders AS (
  SELECT order_id, customer_unique_id, purchased_at
  FROM orders
  WHERE order_status NOT IN ('canceled', 'unavailable')
),
-- The customer's next valid order on a LATER day
next_orders AS (
  SELECT a.order_id, MIN(b.purchased_at) AS next_order_at
  FROM valid_orders a
  JOIN valid_orders b
    ON a.customer_unique_id = b.customer_unique_id
   AND b.purchased_at::DATE > a.purchased_at::DATE
  GROUP BY a.order_id
)
SELECT
  o.order_id,
  o.customer_unique_id,
  o.customer_id,
  o.customer_state,
  o.order_status,
  o.purchased_at::DATE AS purchase_date,
  o.purchased_at,
  o.approved_at,
  o.shipped_at,
  o.delivered_at,
  o.estimated_delivery_at,

  -- Money (revenue = items + freight, see log #13)
  i.item_count,
  i.seller_count,
  i.items_value,
  i.freight_value,
  i.items_value + i.freight_value AS order_value,
  p.payment_value,
  p.main_payment_type,
  p.max_installments,

  -- Delivery (only filled for orders usable for delivery analysis)
  IFF(o.is_delivery_analysable, DATEDIFF('day', o.purchased_at::DATE, o.delivered_at::DATE), NULL)          AS delivery_days,
  IFF(o.is_delivery_analysable, DATEDIFF('day', o.purchased_at::DATE, o.estimated_delivery_at::DATE), NULL) AS promised_days,
  IFF(o.is_delivery_analysable, DATEDIFF('day', o.estimated_delivery_at::DATE, o.delivered_at::DATE), NULL) AS days_late,  -- negative = early
  IFF(o.is_delivery_analysable, o.delivered_at::DATE > o.estimated_delivery_at::DATE, NULL)                 AS is_late,

  -- Review
  r.review_score,
  r.review_score IS NOT NULL                             AS has_review,
  IFF(r.review_score IS NULL, NULL, r.review_score <= 2) AS is_bad_review,

  -- Customer journey
  ROW_NUMBER() OVER (PARTITION BY o.customer_unique_id ORDER BY o.purchased_at, o.order_id) AS customer_order_number,
  n.next_order_at,
  n.next_order_at IS NOT NULL                                  AS customer_ordered_again,
  DATEDIFF('day', o.purchased_at::DATE, n.next_order_at::DATE) AS days_to_next_order,

  -- Data-quality flags
  o.has_date_issue,
  o.is_delivery_analysable
FROM orders o
LEFT JOIN items i      ON o.order_id = i.order_id
LEFT JOIN payments p   ON o.order_id = p.order_id
LEFT JOIN STAGING.STG_ORDER_REVIEWS r ON o.order_id = r.order_id
LEFT JOIN next_orders n ON o.order_id = n.order_id;

------------------------------------------------------------
-- FACT_ORDER_ITEMS: one row per item sold
------------------------------------------------------------
CREATE OR REPLACE TABLE FACT_ORDER_ITEMS AS
SELECT
  i.order_id,
  i.order_item_id,
  i.product_id,
  i.seller_id,
  f.customer_unique_id,
  f.purchase_date,
  i.price,
  i.freight_value,
  i.shipping_limit_at,
  f.shipped_at,
  -- Did the seller hand the item to the carrier after the deadline?
  IFF(f.shipped_at IS NULL OR f.has_date_issue, NULL, f.shipped_at > i.shipping_limit_at) AS shipped_after_limit
FROM STAGING.STG_ORDER_ITEMS i
JOIN FACT_ORDERS f ON i.order_id = f.order_id;

------------------------------------------------------------
-- DIM_CUSTOMER: one row per real person
------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_CUSTOMER AS
SELECT
  c.customer_unique_id,
  MAX_BY(c.customer_city,  o.purchased_at) AS customer_city,   -- from most recent order
  MAX_BY(c.customer_state, o.purchased_at) AS customer_state,
  MIN(o.purchased_at)                      AS first_order_at,
  MAX(o.purchased_at)                      AS last_order_at,
  COUNT(DISTINCT o.order_id)               AS total_orders     -- all statuses
FROM STAGING.STG_CUSTOMERS c
JOIN STAGING.STG_ORDERS o ON c.customer_id = o.customer_id
GROUP BY c.customer_unique_id;

------------------------------------------------------------
-- DIM_SELLER and DIM_PRODUCT
------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_SELLER AS
SELECT seller_id, seller_zip_prefix, seller_city, seller_state
FROM STAGING.STG_SELLERS;

CREATE OR REPLACE TABLE DIM_PRODUCT AS
SELECT * FROM STAGING.STG_PRODUCTS;

------------------------------------------------------------
-- DIM_DATE: one row per day, 2016-01-01 to 2018-12-31
------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_DATE AS
WITH days AS (
  SELECT DATEADD('day', ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, '2016-01-01'::DATE) AS date_day
  FROM TABLE(GENERATOR(ROWCOUNT => 1096))
)
SELECT
  date_day,
  YEAR(date_day)               AS year,
  QUARTER(date_day)            AS quarter,
  MONTH(date_day)              AS month,
  MONTHNAME(date_day)          AS month_name,
  TO_CHAR(date_day, 'YYYY-MM') AS year_month,
  DAYOFWEEKISO(date_day)       AS day_of_week,   -- 1 = Monday
  DAYNAME(date_day)            AS day_name,
  DAYOFWEEKISO(date_day) IN (6, 7) AS is_weekend
FROM days;

------------------------------------------------------------
-- Checks
------------------------------------------------------------
SELECT 'FACT_ORDERS' AS check_name, COUNT(*) AS value FROM FACT_ORDERS
UNION ALL SELECT 'FACT_ORDER_ITEMS', COUNT(*) FROM FACT_ORDER_ITEMS
UNION ALL SELECT 'DIM_CUSTOMER', COUNT(*) FROM DIM_CUSTOMER
UNION ALL SELECT 'DIM_SELLER', COUNT(*) FROM DIM_SELLER
UNION ALL SELECT 'DIM_PRODUCT', COUNT(*) FROM DIM_PRODUCT
UNION ALL SELECT 'DIM_DATE', COUNT(*) FROM DIM_DATE
UNION ALL SELECT 'orders: delivery analysable', COUNT_IF(is_delivery_analysable) FROM FACT_ORDERS
UNION ALL SELECT 'orders: delivered late', COUNT_IF(is_late) FROM FACT_ORDERS
UNION ALL SELECT 'orders: customer ordered again later', COUNT_IF(customer_ordered_again) FROM FACT_ORDERS;