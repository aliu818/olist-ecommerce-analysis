-- 00_setup.sql
-- Creates the warehouse, database and schemas for the Olist project.

-- Small warehouse that switches itself off after 60 seconds idle (saves trial credits)
CREATE WAREHOUSE IF NOT EXISTS OLIST_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;

CREATE DATABASE IF NOT EXISTS OLIST;

CREATE SCHEMA IF NOT EXISTS OLIST.RAW;      -- CSVs loaded as-is
CREATE SCHEMA IF NOT EXISTS OLIST.STAGING;  -- cleaned, renamed, typed
CREATE SCHEMA IF NOT EXISTS OLIST.MARTS;    -- star schema for analysis