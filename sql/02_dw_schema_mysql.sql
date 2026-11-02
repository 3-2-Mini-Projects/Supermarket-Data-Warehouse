-- =====================================================================
-- FreshMart Data Warehouse - PHYSICAL SCHEMA (MySQL 8.0, InnoDB)
-- Layers: stg_* (staging)  |  dim_* / fact_* (presentation star schema)  |  etl_* (control)
-- =====================================================================
DROP DATABASE IF EXISTS supermarket_dw;
CREATE DATABASE supermarket_dw CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE supermarket_dw;

-- ---------------------------------------------------------------------
-- 0. ETL control tables
-- ---------------------------------------------------------------------
CREATE TABLE etl_run_log (
  run_id        INT AUTO_INCREMENT PRIMARY KEY,
  step_name     VARCHAR(60) NOT NULL,
  rows_loaded   INT NULL,
  status        VARCHAR(10) NOT NULL DEFAULT 'OK',
  started_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  note          VARCHAR(200) NULL
) ENGINE=InnoDB;

CREATE TABLE etl_config (
  param VARCHAR(40) PRIMARY KEY, config_value VARCHAR(100) NOT NULL, description VARCHAR(200) NULL
) ENGINE=InnoDB;
INSERT INTO etl_config VALUES ('max_valid_order_date','2026-10-28','Online orders dated after this day are rejected (cannot be DELIVERED in the future)');

CREATE TABLE etl_reject_online_orders (          -- quarantine for rows that fail business rules
  order_id INT PRIMARY KEY, order_date DATE, barcode VARCHAR(20), branch_code VARCHAR(10), quantity INT,
  unit_price DECIMAL(10,2), discount_rate DECIMAL(5,2), card_no VARCHAR(20), delivery_status VARCHAR(20),
  reject_reason VARCHAR(100) NOT NULL, rejected_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 1. STAGING (landing copies of the 3 sources; truncated every run)
-- ---------------------------------------------------------------------
-- Source 2: CSV (online orders) - loaded as-is, typed columns + DQ flags
CREATE TABLE stg_online_orders (
  order_id        INT PRIMARY KEY,
  order_date      DATE NOT NULL,
  barcode         VARCHAR(20) NOT NULL,
  branch_code     VARCHAR(10) NOT NULL,
  quantity        INT NOT NULL,
  unit_price      DECIMAL(10,2) NOT NULL,
  discount_rate   DECIMAL(5,2) NOT NULL,
  card_no         VARCHAR(20) NOT NULL,
  delivery_status VARCHAR(20) NOT NULL,
  dq_future_date  TINYINT NOT NULL DEFAULT 0,
  dq_price_outlier TINYINT NOT NULL DEFAULT 0
) ENGINE=InnoDB;

-- Source 3: Holiday API (Calendarific JSON, flattened)
CREATE TABLE stg_holiday_api (
  holiday_date  DATE NOT NULL,
  holiday_name  VARCHAR(150) NOT NULL,
  holiday_types VARCHAR(100) NULL,
  country_code  CHAR(2) NOT NULL DEFAULT 'LK',
  holiday_class VARCHAR(20) NULL,          -- derived: POYA / PUBLIC / OBSERVANCE
  KEY ix_hdate (holiday_date)
) ENGINE=InnoDB;

-- Source 1: MySQL OLTP (only the columns the warehouse needs)
CREATE TABLE stg_product        (product_id INT PRIMARY KEY, barcode VARCHAR(20), product_name VARCHAR(150), brand VARCHAR(80), category_name VARCHAR(80), parent_category VARCHAR(80), unit_price DECIMAL(10,2), cost_price DECIMAL(10,2), tax_rate DECIMAL(5,2), is_active TINYINT);
CREATE TABLE stg_price_history  (history_id INT PRIMARY KEY, product_id INT, old_price DECIMAL(10,2), new_price DECIMAL(10,2), changed_at DATETIME);
CREATE TABLE stg_customer       (customer_id INT PRIMARY KEY, card_no VARCHAR(20), full_name VARCHAR(100), city VARCHAR(60), join_date DATE, tier VARCHAR(10), is_active TINYINT);
CREATE TABLE stg_tier_history   (history_id INT PRIMARY KEY, customer_id INT, old_tier VARCHAR(10), new_tier VARCHAR(10), changed_at DATETIME);
CREATE TABLE stg_branch         (branch_id INT PRIMARY KEY, branch_code VARCHAR(10), branch_name VARCHAR(100), city VARCHAR(60), region VARCHAR(60), opened_date DATE, is_active TINYINT, manager_name VARCHAR(100));
CREATE TABLE stg_supplier       (supplier_id INT PRIMARY KEY, supplier_code VARCHAR(20), supplier_name VARCHAR(100), contact_name VARCHAR(100), is_active TINYINT);
CREATE TABLE stg_promotion      (promo_id INT PRIMARY KEY, promo_name VARCHAR(100), discount_percent DECIMAL(5,2), start_date DATE, end_date DATE, target_type VARCHAR(10), target_name VARCHAR(150));
CREATE TABLE stg_pos_sale       (sale_id INT PRIMARY KEY, branch_id INT, customer_id INT NULL, promo_id INT NULL, sale_date DATETIME, status VARCHAR(12));
CREATE TABLE stg_pos_sale_item  (sale_item_id INT PRIMARY KEY, sale_id INT, product_id INT, quantity INT, unit_price DECIMAL(10,2), discount_amount DECIMAL(10,2), line_total DECIMAL(12,2), KEY ix_sale (sale_id));
CREATE TABLE stg_pos_return     (return_id INT PRIMARY KEY, sale_item_id INT, quantity INT, refund_amount DECIMAL(10,2), KEY ix_si (sale_item_id));
CREATE TABLE stg_po             (po_id INT PRIMARY KEY, po_number VARCHAR(50), supplier_id INT, branch_id INT, order_date DATE, expected_date DATE, received_date DATE, status VARCHAR(12));
CREATE TABLE stg_po_item        (po_item_id INT PRIMARY KEY, po_id INT, product_id INT, quantity INT, received_quantity INT, damaged_quantity INT, shortage_quantity INT, discrepancy_reason VARCHAR(30), unit_cost DECIMAL(10,2), KEY ix_po (po_id));

-- ---------------------------------------------------------------------
-- 2. DIMENSIONS
-- ---------------------------------------------------------------------
CREATE TABLE dim_date (
  date_key       INT PRIMARY KEY,                -- yyyymmdd (smart key, standard for date dim)
  full_date      DATE NOT NULL UNIQUE,
  day_of_month   TINYINT NOT NULL,
  day_name       VARCHAR(10) NOT NULL,
  day_of_week    TINYINT NOT NULL,               -- 1=Mon ... 7=Sun
  is_weekend     TINYINT NOT NULL,
  iso_week       TINYINT NOT NULL,
  month_no       TINYINT NOT NULL,
  month_name     VARCHAR(10) NOT NULL,
  quarter_no     TINYINT NOT NULL,
  quarter_name   CHAR(2) NOT NULL,
  year_no        SMALLINT NOT NULL,
  yearmonth      CHAR(7) NOT NULL,               -- 2025-04
  is_holiday     TINYINT NOT NULL DEFAULT 0,     -- from Holiday API
  is_poya_day    TINYINT NOT NULL DEFAULT 0,     -- from Holiday API
  holiday_name   VARCHAR(255) NULL,
  holiday_class  VARCHAR(20) NOT NULL DEFAULT 'Normal day',
  day_type       VARCHAR(20) NOT NULL DEFAULT 'Weekday',   -- Holiday / Weekend / Weekday
  KEY ix_ym (year_no, month_no)
) ENGINE=InnoDB;

CREATE TABLE dim_channel (
  channel_key   TINYINT PRIMARY KEY,
  channel_code  VARCHAR(10) NOT NULL UNIQUE,
  channel_name  VARCHAR(30) NOT NULL,
  source_system VARCHAR(30) NOT NULL
) ENGINE=InnoDB;

CREATE TABLE dim_branch (                         -- SCD Type 1
  branch_key    INT AUTO_INCREMENT PRIMARY KEY,
  branch_id     INT NULL,                          -- natural key (OLTP)
  branch_code   VARCHAR(10) NOT NULL,
  branch_name   VARCHAR(100) NOT NULL,
  city          VARCHAR(60) NOT NULL,
  region        VARCHAR(60) NOT NULL,
  opened_date   DATE NULL,
  manager_name  VARCHAR(100) NULL,
  is_active     TINYINT NOT NULL DEFAULT 1,
  UNIQUE KEY uq_branch_nk (branch_id)
) ENGINE=InnoDB;

CREATE TABLE dim_product (                        -- SCD Type 2 on list_price (+Type 1 on descriptive attrs)
  product_key     INT AUTO_INCREMENT PRIMARY KEY,
  product_id      INT NULL,                        -- natural key (OLTP)
  barcode         VARCHAR(20) NOT NULL,
  product_name    VARCHAR(150) NOT NULL,
  brand           VARCHAR(80) NULL,
  category_name   VARCHAR(80) NOT NULL,
  parent_category VARCHAR(80) NOT NULL,
  list_price      DECIMAL(10,2) NOT NULL,          -- tracked (Type 2)
  cost_price      DECIMAL(10,2) NOT NULL,
  tax_rate        DECIMAL(5,2) NOT NULL,
  effective_from  DATE NOT NULL,
  effective_to    DATE NOT NULL,
  is_current      TINYINT NOT NULL,
  version_no      SMALLINT NOT NULL DEFAULT 1,
  KEY ix_prod_nk (product_id, effective_from, effective_to),
  KEY ix_prod_bc (barcode, effective_from, effective_to)
) ENGINE=InnoDB;

CREATE TABLE dim_customer (                       -- SCD Type 2 on loyalty tier (+Type 1 on name/city)
  customer_key    INT AUTO_INCREMENT PRIMARY KEY,
  customer_id     INT NULL,                        -- natural key (OLTP)
  card_no         VARCHAR(20) NOT NULL,
  full_name       VARCHAR(100) NOT NULL,
  city            VARCHAR(60) NULL,
  join_date       DATE NULL,
  loyalty_tier    VARCHAR(10) NOT NULL,            -- tracked (Type 2)
  effective_from  DATE NOT NULL,
  effective_to    DATE NOT NULL,
  is_current      TINYINT NOT NULL,
  version_no      SMALLINT NOT NULL DEFAULT 1,
  KEY ix_cust_nk (customer_id, effective_from, effective_to),
  KEY ix_cust_card (card_no, effective_from, effective_to)
) ENGINE=InnoDB;

CREATE TABLE dim_promotion (                      -- SCD Type 1
  promotion_key    INT PRIMARY KEY,                -- 0 = No promotion, -2 = online ad-hoc discount
  promo_id         INT NULL,
  promo_name       VARCHAR(100) NOT NULL,
  discount_percent DECIMAL(5,2) NULL,
  start_date       DATE NULL,
  end_date         DATE NULL,
  target_type      VARCHAR(10) NOT NULL,           -- PRODUCT / CATEGORY / STOREWIDE / N/A
  target_name      VARCHAR(150) NULL
) ENGINE=InnoDB;

CREATE TABLE dim_supplier (                       -- SCD Type 1
  supplier_key   INT AUTO_INCREMENT PRIMARY KEY,
  supplier_id    INT NULL,
  supplier_code  VARCHAR(20) NOT NULL,
  supplier_name  VARCHAR(100) NOT NULL,
  contact_name   VARCHAR(100) NULL,
  is_active      TINYINT NOT NULL DEFAULT 1,
  UNIQUE KEY uq_sup_nk (supplier_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 3. FACT TABLES
-- ---------------------------------------------------------------------
-- FACT 1: sales (grain = one product line of one order, both channels)
CREATE TABLE fact_sales (
  sales_fact_id    BIGINT AUTO_INCREMENT PRIMARY KEY,
  date_key         INT NOT NULL,
  product_key      INT NOT NULL,
  branch_key       INT NOT NULL,
  customer_key     INT NOT NULL,
  channel_key      TINYINT NOT NULL,
  promotion_key    INT NOT NULL,
  source_order_no  VARCHAR(20) NOT NULL,           -- degenerate dimension (POS-123 / ONL-900479)
  source_line_no   INT NOT NULL,
  quantity         INT NOT NULL,
  unit_price       DECIMAL(10,2) NOT NULL,         -- price actually charged
  gross_amount     DECIMAL(14,2) NOT NULL,         -- qty * unit_price
  discount_amount  DECIMAL(12,2) NOT NULL,
  net_amount       DECIMAL(14,2) NOT NULL,         -- gross - discount (tax-exclusive revenue)
  tax_amount       DECIMAL(12,2) NOT NULL,
  cost_amount      DECIMAL(14,2) NOT NULL,         -- qty * cost_price
  gross_profit     DECIMAL(14,2) NOT NULL,         -- net - cost
  returned_qty     INT NOT NULL DEFAULT 0,
  refund_amount    DECIMAL(12,2) NOT NULL DEFAULT 0,
  load_ts          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_sales_nk (source_order_no, source_line_no),
  KEY ix_fs_date (date_key), KEY ix_fs_prod (product_key), KEY ix_fs_branch (branch_key),
  KEY ix_fs_cust (customer_key), KEY ix_fs_chan (channel_key), KEY ix_fs_promo (promotion_key),
  CONSTRAINT fk_fs_date  FOREIGN KEY (date_key)      REFERENCES dim_date(date_key),
  CONSTRAINT fk_fs_prod  FOREIGN KEY (product_key)   REFERENCES dim_product(product_key),
  CONSTRAINT fk_fs_br    FOREIGN KEY (branch_key)    REFERENCES dim_branch(branch_key),
  CONSTRAINT fk_fs_cust  FOREIGN KEY (customer_key)  REFERENCES dim_customer(customer_key),
  CONSTRAINT fk_fs_chan  FOREIGN KEY (channel_key)   REFERENCES dim_channel(channel_key),
  CONSTRAINT fk_fs_promo FOREIGN KEY (promotion_key) REFERENCES dim_promotion(promotion_key)
) ENGINE=InnoDB;

-- FACT 2: procurement (grain = one product line of one received purchase order)
CREATE TABLE fact_procurement (
  proc_fact_id      BIGINT AUTO_INCREMENT PRIMARY KEY,
  order_date_key    INT NOT NULL,                  -- role-playing date #1
  received_date_key INT NOT NULL,                  -- role-playing date #2
  product_key       INT NOT NULL,
  supplier_key      INT NOT NULL,
  branch_key        INT NOT NULL,
  po_number         VARCHAR(50) NOT NULL,          -- degenerate dimension
  po_line_no        INT NOT NULL,
  discrepancy_reason VARCHAR(30) NOT NULL,         -- low-cardinality degenerate attribute
  ordered_qty       INT NOT NULL,
  received_qty      INT NOT NULL,
  damaged_qty       INT NOT NULL,
  shortage_qty      INT NOT NULL,
  unit_cost         DECIMAL(10,2) NOT NULL,
  ordered_amount    DECIMAL(14,2) NOT NULL,
  received_amount   DECIMAL(14,2) NOT NULL,
  lost_amount       DECIMAL(14,2) NOT NULL,        -- (damaged+shortage) * unit_cost
  lead_time_days    SMALLINT NOT NULL,             -- received - ordered
  delay_days        SMALLINT NOT NULL,             -- received - expected (negative = early)
  on_time_flag      TINYINT NOT NULL,
  load_ts           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_proc_nk (po_number, po_line_no),
  KEY ix_fp_od (order_date_key), KEY ix_fp_rd (received_date_key), KEY ix_fp_prod (product_key),
  KEY ix_fp_sup (supplier_key), KEY ix_fp_br (branch_key),
  CONSTRAINT fk_fp_od   FOREIGN KEY (order_date_key)    REFERENCES dim_date(date_key),
  CONSTRAINT fk_fp_rd   FOREIGN KEY (received_date_key) REFERENCES dim_date(date_key),
  CONSTRAINT fk_fp_prod FOREIGN KEY (product_key)       REFERENCES dim_product(product_key),
  CONSTRAINT fk_fp_sup  FOREIGN KEY (supplier_key)      REFERENCES dim_supplier(supplier_key),
  CONSTRAINT fk_fp_br   FOREIGN KEY (branch_key)        REFERENCES dim_branch(branch_key)
) ENGINE=InnoDB;
