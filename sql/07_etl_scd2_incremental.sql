-- INCREMENTAL SCD REFRESH (run after 03_etl_staging.sql on every scheduled load)
--  * Type 2 : product list_price  -> close current row, open a new version
--  * Type 2 : customer loyalty_tier -> close current row, open a new version
--  * Type 1 : descriptive attributes overwritten in place on all versions
--  * New natural keys inserted as version 1
USE supermarket_dw;

-- ---------- PRODUCT -----------------------------------------------------
UPDATE dim_product d JOIN stg_product s ON s.product_id = d.product_id         -- Type 1 overwrite
SET d.product_name = s.product_name, d.brand = s.brand, d.category_name = s.category_name,
    d.parent_category = s.parent_category, d.cost_price = s.cost_price, d.tax_rate = s.tax_rate;

DROP TEMPORARY TABLE IF EXISTS tmp_price_chg;
CREATE TEMPORARY TABLE tmp_price_chg AS
SELECT s.product_id, d.version_no,
       COALESCE((SELECT DATE(MAX(h.changed_at)) FROM stg_price_history h WHERE h.product_id = s.product_id), CURDATE()) AS chg_date
FROM stg_product s JOIN dim_product d ON d.product_id = s.product_id AND d.is_current = 1
WHERE d.list_price <> s.unit_price;                                             -- change detected

UPDATE dim_product d JOIN tmp_price_chg t ON t.product_id = d.product_id AND d.is_current = 1
SET d.effective_to = DATE_SUB(t.chg_date, INTERVAL 1 DAY), d.is_current = 0;    -- close old version

INSERT INTO dim_product (product_id, barcode, product_name, brand, category_name, parent_category, list_price, cost_price, tax_rate, effective_from, effective_to, is_current, version_no)
SELECT s.product_id, s.barcode, s.product_name, s.brand, s.category_name, s.parent_category, s.unit_price, s.cost_price, s.tax_rate,
       t.chg_date, DATE('9999-12-31'), 1, t.version_no + 1                       -- open new version
FROM tmp_price_chg t JOIN stg_product s ON s.product_id = t.product_id;

INSERT INTO dim_product (product_id, barcode, product_name, brand, category_name, parent_category, list_price, cost_price, tax_rate, effective_from, effective_to, is_current, version_no)
SELECT s.product_id, s.barcode, s.product_name, s.brand, s.category_name, s.parent_category, s.unit_price, s.cost_price, s.tax_rate, DATE('1900-01-01'), DATE('9999-12-31'), 1, 1
FROM stg_product s WHERE NOT EXISTS (SELECT 1 FROM dim_product d WHERE d.product_id = s.product_id);   -- brand-new product

-- ---------- CUSTOMER ----------------------------------------------------
UPDATE dim_customer d JOIN stg_customer s ON s.customer_id = d.customer_id
SET d.full_name = s.full_name, d.city = s.city;                                  -- Type 1 overwrite

DROP TEMPORARY TABLE IF EXISTS tmp_tier_chg;
CREATE TEMPORARY TABLE tmp_tier_chg AS
SELECT s.customer_id, d.version_no,
       COALESCE((SELECT DATE(MAX(h.changed_at)) FROM stg_tier_history h WHERE h.customer_id = s.customer_id), CURDATE()) AS chg_date
FROM stg_customer s JOIN dim_customer d ON d.customer_id = s.customer_id AND d.is_current = 1
WHERE d.loyalty_tier <> s.tier;

UPDATE dim_customer d JOIN tmp_tier_chg t ON t.customer_id = d.customer_id AND d.is_current = 1
SET d.effective_to = DATE_SUB(t.chg_date, INTERVAL 1 DAY), d.is_current = 0;

INSERT INTO dim_customer (customer_id, card_no, full_name, city, join_date, loyalty_tier, effective_from, effective_to, is_current, version_no)
SELECT s.customer_id, s.card_no, s.full_name, s.city, s.join_date, s.tier, t.chg_date, DATE('9999-12-31'), 1, t.version_no + 1
FROM tmp_tier_chg t JOIN stg_customer s ON s.customer_id = t.customer_id;

INSERT INTO dim_customer (customer_id, card_no, full_name, city, join_date, loyalty_tier, effective_from, effective_to, is_current, version_no)
SELECT s.customer_id, s.card_no, s.full_name, s.city, s.join_date, s.tier, DATE('1900-01-01'), DATE('9999-12-31'), 1, 1
FROM stg_customer s WHERE NOT EXISTS (SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id);

INSERT INTO etl_run_log(step_name, rows_loaded, note) SELECT 'SCD2 incremental: product versions closed', COUNT(*), 'price change' FROM tmp_price_chg;
INSERT INTO etl_run_log(step_name, rows_loaded, note) SELECT 'SCD2 incremental: customer versions closed', COUNT(*), 'tier change' FROM tmp_tier_chg;
