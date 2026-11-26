-- 04_late_by_state_and_month.sql
-- Question: where (customer state) and when (purchase month) are deliveries late?
-- Population: delivered orders with usable dates, no date issues.

USE WAREHOUSE OLIST_WH;
USE DATABASE OLIST;
USE SCHEMA MARTS;

WITH base AS(
    SELECT *
    FROM FACT_ORDERS
    WHERE is_delivery_analysable
        AND NOT has_date_issue
),
by_state AS(
    SELECT 
    'A. By customer state'          AS view,
    customer_state                  AS grp,
    COUNT(*)                        AS orders,
    ROUND(100 * COUNT_IF(is_late) / COUNT(*), 1)AS pct_late,
    ROUND(AVG(delivery_days), 1)    AS avg_delivery_days,
    ROUND(AVG(promised_days), 1)    AS avg_promised_days,
    ROUND(AVG(review_score), 2)     AS avg_review_score
FROM base
GROUP BY customer_state
),
by_month AS (
    SELECT
    'B. By purchase month'          AS view,
    TO_CHAR(purchase_date, 'YYYY-MM')AS grp,
    COUNT(*)                        AS orders,
    ROUND(100 * COUNT_IF(is_late) / COUNT(*), 1) AS pct_late,
    ROUND(AVG(delivery_days), 1)    AS avg_delivery_days,
    ROUND(AVG(promised_days), 1)    AS avg_promised_days,
    ROUND(AVG(review_score), 2)     AS avg_review_score
FROM base
GROUP BY TO_CHAR(purchase_date, 'YYYY-MM')
HAVING COUNT(*) >= 100
)
SELECT *
FROM (SELECT * FROM by_state UNION ALL SELECT * FROM by_month)
ORDER BY view,
        IFF(view LIKE 'A%', -pct_late, 0),  --states: worst first
        grp;    -- months: in date order
        