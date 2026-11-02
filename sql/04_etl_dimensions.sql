-- ETL STEP 2: load dimensions (full rebuild with SCD-2 history reconstruction from the OLTP history tables)
USE supermarket_dw;
SET FOREIGN_KEY_CHECKS=0;
TRUNCATE fact_sales; TRUNCATE fact_procurement;
TRUNCATE dim_date; TRUNCATE dim_channel; TRUNCATE dim_branch; TRUNCATE dim_product; TRUNCATE dim_customer; TRUNCATE dim_promotion; TRUNCATE dim_supplier;
SET FOREIGN_KEY_CHECKS=1;

-- ---- dim_date (calendar 2022-2027) + Holiday-API enrichment
SET SESSION cte_max_recursion_depth = 5000;
INSERT INTO dim_date (date_key, full_date, day_of_month, day_name, day_of_week, is_weekend, iso_week, month_no, month_name, quarter_no, quarter_name, year_no, yearmonth)
WITH RECURSIVE cal AS (SELECT DATE('2022-01-01') d UNION ALL SELECT d + INTERVAL 1 DAY FROM cal WHERE d < '2027-12-31')
SELECT CAST(DATE_FORMAT(d,'%Y%m%d') AS UNSIGNED), d, DAY(d), DAYNAME(d), WEEKDAY(d)+1, IF(WEEKDAY(d)>=5,1,0), WEEK(d,3),
       MONTH(d), MONTHNAME(d), QUARTER(d), CONCAT('Q',QUARTER(d)), YEAR(d), DATE_FORMAT(d,'%Y-%m') FROM cal;

UPDATE dim_date d
JOIN (SELECT holiday_date,
             MAX(holiday_class='POYA') AS has_poya,
             GROUP_CONCAT(DISTINCT holiday_name ORDER BY holiday_name SEPARATOR ' | ') AS names
      FROM stg_holiday_api WHERE holiday_class IN ('POYA','PUBLIC') GROUP BY holiday_date) h ON h.holiday_date = d.full_date
SET d.is_holiday = 1, d.is_poya_day = h.has_poya, d.holiday_name = h.names,
    d.holiday_class = IF(h.has_poya=1,'Poya day','Public holiday');
UPDATE dim_date SET day_type = CASE WHEN is_holiday=1 THEN 'Holiday' WHEN is_weekend=1 THEN 'Weekend' ELSE 'Weekday' END;

-- ---- dim_channel
INSERT INTO dim_channel VALUES (1,'IN_STORE','In-store (POS)','MySQL OLTP'), (2,'ONLINE','Online order','CSV file');

-- ---- dim_branch (SCD-1) + unknown member
INSERT INTO dim_branch (branch_key, branch_id, branch_code, branch_name, city, region, opened_date, manager_name, is_active) VALUES (-1, NULL, 'N/A', 'Unknown branch', 'Unknown', 'Unknown', NULL, NULL, 0);
INSERT INTO dim_branch (branch_id, branch_code, branch_name, city, region, opened_date, manager_name, is_active)
SELECT branch_id, branch_code, branch_name, city, region, opened_date, manager_name, is_active FROM stg_branch;

-- ---- dim_supplier (SCD-1) + unknown member
INSERT INTO dim_supplier (supplier_key, supplier_id, supplier_code, supplier_name, contact_name, is_active) VALUES (-1, NULL, 'N/A', 'Unknown supplier', NULL, 0);
INSERT INTO dim_supplier (supplier_id, supplier_code, supplier_name, contact_name, is_active) SELECT supplier_id, supplier_code, supplier_name, contact_name, is_active FROM stg_supplier;

-- ---- dim_promotion (SCD-1) + special members
INSERT INTO dim_promotion VALUES (0, NULL, 'No promotion', NULL, NULL, NULL, 'N/A', NULL),
                                 (-1, NULL, 'Unknown promotion', NULL, NULL, NULL, 'N/A', NULL),
                                 (-2, NULL, 'Online ad-hoc discount', NULL, NULL, NULL, 'N/A', 'Online orders (CSV has no promo id)');
INSERT INTO dim_promotion SELECT promo_id, promo_id, promo_name, discount_percent, start_date, end_date, target_type, target_name FROM stg_promotion;

-- ---- dim_product (SCD-2 on list price). Versions rebuilt from product_price_history.
INSERT INTO dim_product (product_key, product_id, barcode, product_name, brand, category_name, parent_category, list_price, cost_price, tax_rate, effective_from, effective_to, is_current, version_no)
VALUES (-1, NULL, 'UNKNOWN', 'Unknown product', NULL, 'Unknown', 'Unknown', 0, 0, 0, '1900-01-01', '9999-12-31', 1, 1);
INSERT INTO dim_product (product_id, barcode, product_name, brand, category_name, parent_category, list_price, cost_price, tax_rate, effective_from, effective_to, is_current, version_no)
WITH ph AS (
  SELECT product_id, old_price, new_price, DATE(changed_at) AS chg,
         ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY changed_at) AS rn FROM stg_price_history),
ver AS (
  SELECT product_id, old_price AS price, DATE('1900-01-01') AS valid_from FROM ph WHERE rn = 1
  UNION ALL SELECT product_id, new_price, chg FROM ph
  UNION ALL SELECT p.product_id, p.unit_price, DATE('1900-01-01') FROM stg_product p WHERE NOT EXISTS (SELECT 1 FROM ph WHERE ph.product_id = p.product_id)),
v2 AS (
  SELECT product_id, price, valid_from,
         LEAD(valid_from) OVER (PARTITION BY product_id ORDER BY valid_from) AS nxt,
         ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY valid_from) AS vno FROM ver)
SELECT p.product_id, p.barcode, p.product_name, p.brand, p.category_name, p.parent_category, v.price, p.cost_price, p.tax_rate,
       v.valid_from, COALESCE(DATE_SUB(v.nxt, INTERVAL 1 DAY), DATE('9999-12-31')), IF(v.nxt IS NULL,1,0), v.vno
FROM v2 v JOIN stg_product p ON p.product_id = v.product_id;

-- ---- dim_customer (SCD-2 on loyalty tier). Versions rebuilt from customer_tier_history.
-- First version starts at 1900-01-01 (standard convention) so facts dated before join_date still resolve; join_date stays as an attribute.
INSERT INTO dim_customer (customer_key, customer_id, card_no, full_name, city, join_date, loyalty_tier, effective_from, effective_to, is_current, version_no)
VALUES (-1, NULL, 'ANONYMOUS', 'Anonymous / unmatched customer', NULL, NULL, 'NONE', '1900-01-01', '9999-12-31', 1, 1);
INSERT INTO dim_customer (customer_id, card_no, full_name, city, join_date, loyalty_tier, effective_from, effective_to, is_current, version_no)
WITH th AS (
  SELECT customer_id, old_tier, new_tier, DATE(changed_at) AS chg,
         ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY changed_at) AS rn FROM stg_tier_history),
ver AS (
  SELECT t.customer_id, COALESCE(t.old_tier,'BRONZE') AS tier, DATE('1900-01-01') AS valid_from FROM th t JOIN stg_customer c USING (customer_id) WHERE t.rn = 1
  UNION ALL SELECT customer_id, new_tier, chg FROM th
  UNION ALL SELECT c.customer_id, c.tier, DATE('1900-01-01') FROM stg_customer c WHERE NOT EXISTS (SELECT 1 FROM th WHERE th.customer_id = c.customer_id)),
v2 AS (
  SELECT customer_id, tier, valid_from,
         LEAD(valid_from) OVER (PARTITION BY customer_id ORDER BY valid_from) AS nxt,
         ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY valid_from) AS vno FROM ver)
SELECT c.customer_id, c.card_no, c.full_name, c.city, c.join_date, v.tier, v.valid_from,
       COALESCE(DATE_SUB(v.nxt, INTERVAL 1 DAY), DATE('9999-12-31')), IF(v.nxt IS NULL,1,0), v.vno
FROM v2 v JOIN stg_customer c ON c.customer_id = v.customer_id;

INSERT INTO etl_run_log(step_name, rows_loaded) SELECT 'dim_date', COUNT(*) FROM dim_date;
INSERT INTO etl_run_log(step_name, rows_loaded) SELECT 'dim_product (all versions)', COUNT(*) FROM dim_product;
INSERT INTO etl_run_log(step_name, rows_loaded) SELECT 'dim_customer (all versions)', COUNT(*) FROM dim_customer;
