# Data model (star schema)

Built in Snowflake: `RAW` → `STAGING` → `MARTS`. SQL in `sql/04_marts/01_star_schema.sql`.

```mermaid
erDiagram
    DIM_CUSTOMER ||--o{ FACT_ORDERS : places
    DIM_DATE ||--o{ FACT_ORDERS : "purchase date"
    FACT_ORDERS ||--o{ FACT_ORDER_ITEMS : contains
    DIM_PRODUCT ||--o{ FACT_ORDER_ITEMS : "sold as"
    DIM_SELLER ||--o{ FACT_ORDER_ITEMS : sells

    FACT_ORDERS {
        string order_id PK
        string customer_unique_id FK
        date purchase_date FK
        string order_status
        number order_value
        number delivery_days
        number days_late
        boolean is_late
        number review_score
        boolean is_bad_review
        boolean customer_ordered_again
        boolean is_delivery_analysable
    }

    FACT_ORDER_ITEMS {
        string order_id FK
        number order_item_id
        string product_id FK
        string seller_id FK
        number price
        number freight_value
        boolean shipped_after_limit
    }

    DIM_CUSTOMER {
        string customer_unique_id PK
        string customer_state
        timestamp first_order_at
        number total_orders
    }

    DIM_SELLER {
        string seller_id PK
        string seller_state
        string seller_city
    }

    DIM_PRODUCT {
        string product_id PK
        string category_name
        number product_weight_g
    }

    DIM_DATE {
        date date_day PK
        number year
        string year_month
        boolean is_weekend
    }
```

| Table | Grain (one row per) | Rows |
|---|---|---|
| FACT_ORDERS | order | 99,441 |
| FACT_ORDER_ITEMS | item sold | 112,650 |
| DIM_CUSTOMER | real customer (`customer_unique_id`) | 96,096 |
| DIM_SELLER | seller | 3,095 |
| DIM_PRODUCT | product | 32,951 |
| DIM_DATE | day, 2016-01-01 to 2018-12-31 | 1,096 |