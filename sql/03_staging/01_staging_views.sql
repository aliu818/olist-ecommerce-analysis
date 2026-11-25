-- 01_staging_views.sql
-- Staging layer: one view per source table.
-- Converts text to proper types, renames columns and applies the rules in docs/data_quality_log.md.
-- Geolocation is not staged: the analysis uses customer and seller state instead.

USE WAREHOUSE OLIST_WH;
USE DATABASE OLIST;
USE SCHEMA STAGING;

-- Customers: one row per customer_id (a new one per order).
-- customer_unique_id is the real person (log #1).
CREATE OR REPLACE VIEW STG_CUSTOMERS AS
SELECT
  customer_id,
  customer_unique_id,
  LPAD(customer_zip_code_prefix, 5, '0') AS customer_zip_prefix,
  customer_city,
  UPPER(customer_state)                  AS customer_state
FROM RAW.CUSTOMERS;

-- Orders: typed dates plus data-quality flags (log #7-10).
CREATE OR REPLACE VIEW STG_ORDERS AS
WITH typed AS (
  SELECT
    order_id,
    customer_id,
    order_status,
    TRY_TO_TIMESTAMP_NTZ(order_purchase_timestamp)      AS purchased_at,
    TRY_TO_TIMESTAMP_NTZ(order_approved_at)             AS approved_at,
    TRY_TO_TIMESTAMP_NTZ(order_delivered_carrier_date)  AS shipped_at,
    TRY_TO_TIMESTAMP_NTZ(order_delivered_customer_date) AS delivered_at,
    TRY_TO_TIMESTAMP_NTZ(order_estimated_delivery_date) AS estimated_delivery_at
  FROM RAW.ORDERS
)
SELECT
  *,
  -- Dates in an impossible order (log #7, #8)
  COALESCE(shipped_at < purchased_at OR delivered_at < shipped_at, FALSE) AS has_date_issue,
  -- Usable for late-delivery analysis (log #9, #10)
  (order_status = 'delivered'
   AND delivered_at IS NOT NULL
   AND estimated_delivery_at IS NOT NULL)                                AS is_delivery_analysable
FROM typed;

-- Order items: one row per item in an order.
CREATE OR REPLACE VIEW STG_ORDER_ITEMS AS
SELECT
  order_id,
  TO_NUMBER(order_item_id)                  AS order_item_id,
  product_id,
  seller_id,
  TRY_TO_TIMESTAMP_NTZ(shipping_limit_date) AS shipping_limit_at,
  TO_NUMBER(price, 12, 2)                   AS price,
  TO_NUMBER(freight_value, 12, 2)           AS freight_value
FROM RAW.ORDER_ITEMS;

-- Payments: not_defined relabelled unknown (log #14).
CREATE OR REPLACE VIEW STG_ORDER_PAYMENTS AS
SELECT
  order_id,
  TO_NUMBER(payment_sequential)   AS payment_sequential,
  CASE WHEN payment_type = 'not_defined' THEN 'unknown' ELSE payment_type END AS payment_type,
  TO_NUMBER(payment_installments) AS payment_installments,
  TO_NUMBER(payment_value, 12, 2) AS payment_value
FROM RAW.ORDER_PAYMENTS;

-- Reviews: one review per order, keeping the most recent (log #2, #3).
CREATE OR REPLACE VIEW STG_ORDER_REVIEWS AS
SELECT
  review_id,
  order_id,
  TO_NUMBER(review_score)                       AS review_score,
  review_comment_title,
  review_comment_message,
  TRY_TO_TIMESTAMP_NTZ(review_creation_date)    AS review_created_at,
  TRY_TO_TIMESTAMP_NTZ(review_answer_timestamp) AS review_answered_at
FROM RAW.ORDER_REVIEWS
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY order_id
  ORDER BY TRY_TO_TIMESTAMP_NTZ(review_answer_timestamp) DESC NULLS LAST,
           TRY_TO_TIMESTAMP_NTZ(review_creation_date)    DESC NULLS LAST,
           review_id
) = 1;

-- Products: English category names, unknown for missing (log #11, #12),
-- misspelled columns renamed (log #15).
CREATE OR REPLACE VIEW STG_PRODUCTS AS
WITH translations AS (
  SELECT product_category_name, product_category_name_english
  FROM RAW.PRODUCT_CATEGORY_TRANSLATION
  UNION ALL SELECT 'pc_gamer', 'pc_gamer'
  UNION ALL SELECT 'portateis_cozinha_e_preparadores_de_alimentos', 'portable_kitchen_and_food_preparers'
)
SELECT
  p.product_id,
  COALESCE(p.product_category_name, 'unknown')         AS category_name_pt,
  COALESCE(t.product_category_name_english, 'unknown') AS category_name,
  TRY_TO_NUMBER(p.product_name_lenght)                 AS product_name_length,
  TRY_TO_NUMBER(p.product_description_lenght)          AS product_description_length,
  TRY_TO_NUMBER(p.product_photos_qty)                  AS product_photos_qty,
  TRY_TO_NUMBER(p.product_weight_g)                    AS product_weight_g,
  TRY_TO_NUMBER(p.product_length_cm)                   AS product_length_cm,
  TRY_TO_NUMBER(p.product_height_cm)                   AS product_height_cm,
  TRY_TO_NUMBER(p.product_width_cm)                    AS product_width_cm
FROM RAW.PRODUCTS p
LEFT JOIN translations t ON p.product_category_name = t.product_category_name;

-- Sellers
CREATE OR REPLACE VIEW STG_SELLERS AS
SELECT
  seller_id,
  LPAD(seller_zip_code_prefix, 5, '0') AS seller_zip_prefix,
  seller_city,
  UPPER(seller_state)                  AS seller_state
FROM RAW.SELLERS;

-- Check: row counts and flag counts
SELECT 'STG_CUSTOMERS' AS check_name, COUNT(*) AS value FROM STG_CUSTOMERS
UNION ALL SELECT 'STG_ORDERS', COUNT(*) FROM STG_ORDERS
UNION ALL SELECT 'STG_ORDER_ITEMS', COUNT(*) FROM STG_ORDER_ITEMS
UNION ALL SELECT 'STG_ORDER_PAYMENTS', COUNT(*) FROM STG_ORDER_PAYMENTS
UNION ALL SELECT 'STG_ORDER_REVIEWS', COUNT(*) FROM STG_ORDER_REVIEWS
UNION ALL SELECT 'STG_PRODUCTS', COUNT(*) FROM STG_PRODUCTS
UNION ALL SELECT 'STG_SELLERS', COUNT(*) FROM STG_SELLERS
UNION ALL SELECT 'orders: delivery analysable', COUNT_IF(is_delivery_analysable) FROM STG_ORDERS
UNION ALL SELECT 'orders: has_date_issue', COUNT_IF(has_date_issue) FROM STG_ORDERS
UNION ALL SELECT 'products: category unknown', COUNT_IF(category_name = 'unknown') FROM STG_PRODUCTS;