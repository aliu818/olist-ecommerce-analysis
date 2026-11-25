-- 01_stage_and_format.sql
-- Describes the Olist CSV files and creates a stage (holding area) to upload them to.

USE DATABASE OLIST;
USE SCHEMA RAW;

CREATE OR REPLACE FILE FORMAT OLIST_CSV
  TYPE = 'CSV'
  SKIP_HEADER = 1                      -- first row is column names
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'   -- review comments contain commas and line breaks inside quotes
  EMPTY_FIELD_AS_NULL = TRUE
  ENCODING = 'UTF8';

CREATE OR REPLACE STAGE OLIST_STAGE
  FILE_FORMAT = OLIST_CSV;