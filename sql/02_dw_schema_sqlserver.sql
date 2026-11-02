-- FreshMart DW - PHYSICAL SCHEMA for Microsoft SQL Server 2019/2022 (T-SQL)
-- NOTE: translated from the tested MySQL script; not executed in the authoring environment.
IF DB_ID('supermarket_dw') IS NULL CREATE DATABASE supermarket_dw;
GO
USE supermarket_dw;
GO
CREATE TABLE dbo.dim_date (
  date_key INT NOT NULL PRIMARY KEY, full_date DATE NOT NULL UNIQUE, day_of_month TINYINT NOT NULL,
  day_name NVARCHAR(10) NOT NULL, day_of_week TINYINT NOT NULL, is_weekend BIT NOT NULL, iso_week TINYINT NOT NULL,
  month_no TINYINT NOT NULL, month_name NVARCHAR(10) NOT NULL, quarter_no TINYINT NOT NULL, quarter_name CHAR(2) NOT NULL,
  year_no SMALLINT NOT NULL, yearmonth CHAR(7) NOT NULL, is_holiday BIT NOT NULL DEFAULT 0, is_poya_day BIT NOT NULL DEFAULT 0,
  holiday_name NVARCHAR(255) NULL, holiday_class NVARCHAR(20) NOT NULL DEFAULT 'Normal day', day_type NVARCHAR(20) NOT NULL DEFAULT 'Weekday');
CREATE TABLE dbo.dim_channel (channel_key TINYINT NOT NULL PRIMARY KEY, channel_code NVARCHAR(10) NOT NULL UNIQUE, channel_name NVARCHAR(30) NOT NULL, source_system NVARCHAR(30) NOT NULL);
CREATE TABLE dbo.dim_branch (
  branch_key INT IDENTITY(1,1) PRIMARY KEY, branch_id INT NULL, branch_code NVARCHAR(10) NOT NULL, branch_name NVARCHAR(100) NOT NULL,
  city NVARCHAR(60) NOT NULL, region NVARCHAR(60) NOT NULL, opened_date DATE NULL, manager_name NVARCHAR(100) NULL, is_active BIT NOT NULL DEFAULT 1);
CREATE UNIQUE INDEX uq_branch_nk ON dbo.dim_branch(branch_id) WHERE branch_id IS NOT NULL;
CREATE TABLE dbo.dim_product (
  product_key INT IDENTITY(1,1) PRIMARY KEY, product_id INT NULL, barcode NVARCHAR(20) NOT NULL, product_name NVARCHAR(150) NOT NULL,
  brand NVARCHAR(80) NULL, category_name NVARCHAR(80) NOT NULL, parent_category NVARCHAR(80) NOT NULL, list_price DECIMAL(10,2) NOT NULL,
  cost_price DECIMAL(10,2) NOT NULL, tax_rate DECIMAL(5,2) NOT NULL, effective_from DATE NOT NULL, effective_to DATE NOT NULL,
  is_current BIT NOT NULL, version_no SMALLINT NOT NULL DEFAULT 1);
CREATE INDEX ix_prod_nk ON dbo.dim_product(product_id, effective_from, effective_to);
CREATE INDEX ix_prod_bc ON dbo.dim_product(barcode, effective_from, effective_to);
CREATE TABLE dbo.dim_customer (
  customer_key INT IDENTITY(1,1) PRIMARY KEY, customer_id INT NULL, card_no NVARCHAR(20) NOT NULL, full_name NVARCHAR(100) NOT NULL,
  city NVARCHAR(60) NULL, join_date DATE NULL, loyalty_tier NVARCHAR(10) NOT NULL, effective_from DATE NOT NULL, effective_to DATE NOT NULL,
  is_current BIT NOT NULL, version_no SMALLINT NOT NULL DEFAULT 1);
CREATE INDEX ix_cust_nk ON dbo.dim_customer(customer_id, effective_from, effective_to);
CREATE INDEX ix_cust_card ON dbo.dim_customer(card_no, effective_from, effective_to);
CREATE TABLE dbo.dim_promotion (
  promotion_key INT NOT NULL PRIMARY KEY, promo_id INT NULL, promo_name NVARCHAR(100) NOT NULL, discount_percent DECIMAL(5,2) NULL,
  start_date DATE NULL, end_date DATE NULL, target_type NVARCHAR(10) NOT NULL, target_name NVARCHAR(150) NULL);
CREATE TABLE dbo.dim_supplier (
  supplier_key INT IDENTITY(1,1) PRIMARY KEY, supplier_id INT NULL, supplier_code NVARCHAR(20) NOT NULL, supplier_name NVARCHAR(100) NOT NULL,
  contact_name NVARCHAR(100) NULL, is_active BIT NOT NULL DEFAULT 1);
-- Unknown members use negative keys: wrap the INSERT in  SET IDENTITY_INSERT dbo.dim_xxx ON; ... OFF;
CREATE TABLE dbo.fact_sales (
  sales_fact_id BIGINT IDENTITY(1,1) PRIMARY KEY, date_key INT NOT NULL, product_key INT NOT NULL, branch_key INT NOT NULL,
  customer_key INT NOT NULL, channel_key TINYINT NOT NULL, promotion_key INT NOT NULL, source_order_no NVARCHAR(20) NOT NULL,
  source_line_no INT NOT NULL, quantity INT NOT NULL, unit_price DECIMAL(10,2) NOT NULL, gross_amount DECIMAL(14,2) NOT NULL,
  discount_amount DECIMAL(12,2) NOT NULL, net_amount DECIMAL(14,2) NOT NULL, tax_amount DECIMAL(12,2) NOT NULL,
  cost_amount DECIMAL(14,2) NOT NULL, gross_profit DECIMAL(14,2) NOT NULL, returned_qty INT NOT NULL DEFAULT 0,
  refund_amount DECIMAL(12,2) NOT NULL DEFAULT 0, load_ts DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT uq_sales_nk UNIQUE (source_order_no, source_line_no),
  CONSTRAINT fk_fs_date FOREIGN KEY (date_key) REFERENCES dbo.dim_date(date_key),
  CONSTRAINT fk_fs_prod FOREIGN KEY (product_key) REFERENCES dbo.dim_product(product_key),
  CONSTRAINT fk_fs_br   FOREIGN KEY (branch_key) REFERENCES dbo.dim_branch(branch_key),
  CONSTRAINT fk_fs_cust FOREIGN KEY (customer_key) REFERENCES dbo.dim_customer(customer_key),
  CONSTRAINT fk_fs_chan FOREIGN KEY (channel_key) REFERENCES dbo.dim_channel(channel_key),
  CONSTRAINT fk_fs_promo FOREIGN KEY (promotion_key) REFERENCES dbo.dim_promotion(promotion_key));
CREATE INDEX ix_fs_date ON dbo.fact_sales(date_key); CREATE INDEX ix_fs_prod ON dbo.fact_sales(product_key);
CREATE INDEX ix_fs_branch ON dbo.fact_sales(branch_key); CREATE INDEX ix_fs_cust ON dbo.fact_sales(customer_key);
-- Optional on SQL Server: CREATE CLUSTERED COLUMNSTORE INDEX cci_fact_sales ON dbo.fact_sales;  (drop the PK/unique constraints first)
CREATE TABLE dbo.fact_procurement (
  proc_fact_id BIGINT IDENTITY(1,1) PRIMARY KEY, order_date_key INT NOT NULL, received_date_key INT NOT NULL, product_key INT NOT NULL,
  supplier_key INT NOT NULL, branch_key INT NOT NULL, po_number NVARCHAR(50) NOT NULL, po_line_no INT NOT NULL,
  discrepancy_reason NVARCHAR(30) NOT NULL, ordered_qty INT NOT NULL, received_qty INT NOT NULL, damaged_qty INT NOT NULL,
  shortage_qty INT NOT NULL, unit_cost DECIMAL(10,2) NOT NULL, ordered_amount DECIMAL(14,2) NOT NULL, received_amount DECIMAL(14,2) NOT NULL,
  lost_amount DECIMAL(14,2) NOT NULL, lead_time_days SMALLINT NOT NULL, delay_days SMALLINT NOT NULL, on_time_flag BIT NOT NULL,
  load_ts DATETIME2 NOT NULL DEFAULT SYSDATETIME(), CONSTRAINT uq_proc_nk UNIQUE (po_number, po_line_no),
  CONSTRAINT fk_fp_od FOREIGN KEY (order_date_key) REFERENCES dbo.dim_date(date_key),
  CONSTRAINT fk_fp_rd FOREIGN KEY (received_date_key) REFERENCES dbo.dim_date(date_key),
  CONSTRAINT fk_fp_prod FOREIGN KEY (product_key) REFERENCES dbo.dim_product(product_key),
  CONSTRAINT fk_fp_sup FOREIGN KEY (supplier_key) REFERENCES dbo.dim_supplier(supplier_key),
  CONSTRAINT fk_fp_br FOREIGN KEY (branch_key) REFERENCES dbo.dim_branch(branch_key));
GO
