SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS `audit_log`;
CREATE TABLE `audit_log` (
  `audit_id` bigint NOT NULL AUTO_INCREMENT,
  `table_name` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `record_id` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `action` enum('INSERT','UPDATE','DELETE') COLLATE utf8mb4_unicode_ci NOT NULL,
  `old_value` json DEFAULT NULL,
  `new_value` json DEFAULT NULL,
  `changed_by` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `changed_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`audit_id`),
  KEY `idx_audit_table` (`table_name`,`changed_at`)
) ENGINE=InnoDB AUTO_INCREMENT=499 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `audit_log_archive`;
CREATE TABLE `audit_log_archive` (
  `audit_id` bigint NOT NULL AUTO_INCREMENT,
  `table_name` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `record_id` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `action` enum('INSERT','UPDATE','DELETE') COLLATE utf8mb4_unicode_ci NOT NULL,
  `old_value` json DEFAULT NULL,
  `new_value` json DEFAULT NULL,
  `changed_by` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `changed_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`audit_id`),
  KEY `idx_audit_table` (`table_name`,`changed_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `branches`;
CREATE TABLE `branches` (
  `branch_id` int NOT NULL AUTO_INCREMENT,
  `branch_code` varchar(10) COLLATE utf8mb4_unicode_ci NOT NULL,
  `name` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `city` varchar(60) COLLATE utf8mb4_unicode_ci NOT NULL,
  `region` varchar(60) COLLATE utf8mb4_unicode_ci NOT NULL,
  `address` varchar(200) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `phone` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `manager_id` int DEFAULT NULL,
  `opened_date` date NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  PRIMARY KEY (`branch_id`),
  UNIQUE KEY `branch_code` (`branch_code`),
  KEY `fk_branch_manager` (`manager_id`),
  CONSTRAINT `fk_branch_manager` FOREIGN KEY (`manager_id`) REFERENCES `employees` (`employee_id`)
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `categories`;
CREATE TABLE `categories` (
  `category_id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(80) COLLATE utf8mb4_unicode_ci NOT NULL,
  `parent_id` int DEFAULT NULL,
  `parent_key` int GENERATED ALWAYS AS (ifnull(`parent_id`,0)) STORED,
  PRIMARY KEY (`category_id`),
  UNIQUE KEY `uq_cat_name_parent` (`name`,`parent_key`),
  KEY `fk_cat_parent` (`parent_id`),
  CONSTRAINT `fk_cat_parent` FOREIGN KEY (`parent_id`) REFERENCES `categories` (`category_id`)
) ENGINE=InnoDB AUTO_INCREMENT=15 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `coupons`;
CREATE TABLE `coupons` (
  `coupon_id` int NOT NULL AUTO_INCREMENT,
  `code` varchar(30) COLLATE utf8mb4_unicode_ci NOT NULL,
  `promo_id` int NOT NULL,
  `customer_id` int DEFAULT NULL,
  `expiry_date` date NOT NULL,
  `is_used` tinyint(1) NOT NULL DEFAULT '0',
  `used_at` datetime DEFAULT NULL,
  `max_products` int NOT NULL DEFAULT '5',
  `purchase_limit` decimal(10,2) NOT NULL DEFAULT '3000.00',
  `sms_phone` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `sms_status` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT 'SENT',
  `sms_message` text COLLATE utf8mb4_unicode_ci,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`coupon_id`),
  UNIQUE KEY `code` (`code`),
  KEY `fk_coupon_promo` (`promo_id`),
  KEY `fk_coupon_cust` (`customer_id`),
  CONSTRAINT `fk_coupon_cust` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`),
  CONSTRAINT `fk_coupon_promo` FOREIGN KEY (`promo_id`) REFERENCES `promotions` (`promo_id`)
) ENGINE=InnoDB AUTO_INCREMENT=14 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `customer_tier_history`;
CREATE TABLE `customer_tier_history` (
  `history_id` int NOT NULL AUTO_INCREMENT,
  `customer_id` int NOT NULL,
  `old_tier` enum('BRONZE','SILVER','GOLD','PLATINUM') COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `new_tier` enum('BRONZE','SILVER','GOLD','PLATINUM') COLLATE utf8mb4_unicode_ci NOT NULL,
  `reason` varchar(200) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `changed_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`history_id`),
  KEY `fk_cth_cust` (`customer_id`),
  CONSTRAINT `fk_cth_cust` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`)
) ENGINE=InnoDB AUTO_INCREMENT=22 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `customers`;
CREATE TABLE `customers` (
  `customer_id` int NOT NULL AUTO_INCREMENT,
  `card_no` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL,
  `full_name` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `phone` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL,
  `email` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `city` varchar(60) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `join_date` date NOT NULL,
  `tier` enum('BRONZE','SILVER','GOLD','PLATINUM') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'BRONZE',
  `points_balance` int NOT NULL DEFAULT '0',
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  PRIMARY KEY (`customer_id`),
  UNIQUE KEY `card_no` (`card_no`),
  UNIQUE KEY `phone` (`phone`),
  CONSTRAINT `customers_chk_1` CHECK ((`points_balance` >= 0))
) ENGINE=InnoDB AUTO_INCREMENT=14 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `daily_sales_summary`;
CREATE TABLE `daily_sales_summary` (
  `summary_id` int NOT NULL AUTO_INCREMENT,
  `branch_id` int NOT NULL,
  `summary_date` date NOT NULL,
  `transactions_count` int NOT NULL DEFAULT '0',
  `total_sales` decimal(14,2) NOT NULL DEFAULT '0.00',
  `total_tax` decimal(14,2) NOT NULL DEFAULT '0.00',
  PRIMARY KEY (`summary_id`),
  UNIQUE KEY `uq_dss` (`branch_id`,`summary_date`),
  CONSTRAINT `fk_dss_branch` FOREIGN KEY (`branch_id`) REFERENCES `branches` (`branch_id`)
) ENGINE=InnoDB AUTO_INCREMENT=16 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `employees`;
CREATE TABLE `employees` (
  `employee_id` int NOT NULL AUTO_INCREMENT,
  `branch_id` int NOT NULL,
  `full_name` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `role` enum('CASHIER','MANAGER','STOCK_CLERK','CATALOG_MANAGER','MARKETING','HR','ADMIN') COLLATE utf8mb4_unicode_ci NOT NULL,
  `email` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `password_hash` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `phone` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `hire_date` date NOT NULL,
  `monthly_salary` decimal(10,2) NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`employee_id`),
  UNIQUE KEY `email` (`email`),
  KEY `fk_emp_branch` (`branch_id`),
  CONSTRAINT `fk_emp_branch` FOREIGN KEY (`branch_id`) REFERENCES `branches` (`branch_id`),
  CONSTRAINT `employees_chk_1` CHECK ((`monthly_salary` >= 0))
) ENGINE=InnoDB AUTO_INCREMENT=42 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `error_log`;
CREATE TABLE `error_log` (
  `error_id` bigint NOT NULL AUTO_INCREMENT,
  `procedure_name` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `error_code` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `error_message` varchar(500) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `employee_id` int DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`error_id`),
  KEY `fk_err_emp` (`employee_id`),
  CONSTRAINT `fk_err_emp` FOREIGN KEY (`employee_id`) REFERENCES `employees` (`employee_id`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `inventory`;
CREATE TABLE `inventory` (
  `inventory_id` int NOT NULL AUTO_INCREMENT,
  `branch_id` int NOT NULL,
  `product_id` int NOT NULL,
  `quantity_on_hand` int NOT NULL DEFAULT '0',
  `reserved_qty` int NOT NULL DEFAULT '0',
  `reorder_level` int NOT NULL DEFAULT '10',
  `last_updated` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`inventory_id`),
  UNIQUE KEY `uq_inv_branch_prod` (`branch_id`,`product_id`),
  UNIQUE KEY `uq_inventory_branch_product` (`branch_id`,`product_id`),
  KEY `fk_inv_prod` (`product_id`),
  CONSTRAINT `fk_inv_branch` FOREIGN KEY (`branch_id`) REFERENCES `branches` (`branch_id`),
  CONSTRAINT `fk_inv_prod` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`),
  CONSTRAINT `chk_inventory_nonnegative` CHECK (((`quantity_on_hand` >= 0) and (`reserved_qty` >= 0))),
  CONSTRAINT `inventory_chk_1` CHECK ((`quantity_on_hand` >= 0)),
  CONSTRAINT `inventory_chk_2` CHECK ((`reserved_qty` >= 0))
) ENGINE=InnoDB AUTO_INCREMENT=90 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `loyalty_transactions`;
CREATE TABLE `loyalty_transactions` (
  `loyalty_id` int NOT NULL AUTO_INCREMENT,
  `customer_id` int NOT NULL,
  `branch_id` int DEFAULT NULL,
  `sale_id` int DEFAULT NULL,
  `points` int NOT NULL,
  `type` enum('EARN','REDEEM','EXPIRE','ADJUST') COLLATE utf8mb4_unicode_ci NOT NULL,
  `note` varchar(200) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`loyalty_id`),
  KEY `fk_lt_sale` (`sale_id`),
  KEY `idx_lt_branch_type_created` (`branch_id`,`type`,`created_at`),
  KEY `idx_lt_type_created` (`type`,`created_at`),
  KEY `idx_lt_cust_created` (`customer_id`,`created_at`),
  CONSTRAINT `fk_lt_branch` FOREIGN KEY (`branch_id`) REFERENCES `branches` (`branch_id`) ON DELETE SET NULL,
  CONSTRAINT `fk_lt_cust` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`),
  CONSTRAINT `fk_lt_sale` FOREIGN KEY (`sale_id`) REFERENCES `sales` (`sale_id`),
  CONSTRAINT `chk_lt_sign` CHECK ((((`type` = _utf8mb4'EARN') and (`points` > 0)) or ((`type` in (_utf8mb4'REDEEM',_utf8mb4'EXPIRE')) and (`points` < 0)) or (`type` = _utf8mb4'ADJUST')))
) ENGINE=InnoDB AUTO_INCREMENT=89 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `payments`;
CREATE TABLE `payments` (
  `payment_id` int NOT NULL AUTO_INCREMENT,
  `sale_id` int NOT NULL,
  `method` enum('CASH','CARD','MOBILE','POINTS') COLLATE utf8mb4_unicode_ci NOT NULL,
  `amount` decimal(12,2) NOT NULL,
  `reference` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `paid_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`payment_id`),
  KEY `fk_pay_sale` (`sale_id`),
  CONSTRAINT `fk_pay_sale` FOREIGN KEY (`sale_id`) REFERENCES `sales` (`sale_id`),
  CONSTRAINT `payments_chk_1` CHECK ((`amount` > 0))
) ENGINE=InnoDB AUTO_INCREMENT=86 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `product_batches`;
CREATE TABLE `product_batches` (
  `batch_id` int NOT NULL AUTO_INCREMENT,
  `product_id` int NOT NULL,
  `branch_id` int NOT NULL,
  `batch_no` varchar(30) COLLATE utf8mb4_unicode_ci NOT NULL,
  `quantity` int NOT NULL,
  `received_date` date NOT NULL,
  `expiry_date` date DEFAULT NULL,
  PRIMARY KEY (`batch_id`),
  KEY `fk_batch_prod` (`product_id`),
  KEY `fk_batch_branch` (`branch_id`),
  KEY `idx_batch_expiry` (`expiry_date`),
  CONSTRAINT `fk_batch_branch` FOREIGN KEY (`branch_id`) REFERENCES `branches` (`branch_id`),
  CONSTRAINT `fk_batch_prod` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`),
  CONSTRAINT `product_batches_chk_1` CHECK ((`quantity` >= 0))
) ENGINE=InnoDB AUTO_INCREMENT=31 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `product_price_history`;
CREATE TABLE `product_price_history` (
  `history_id` int NOT NULL AUTO_INCREMENT,
  `product_id` int NOT NULL,
  `old_price` decimal(10,2) NOT NULL,
  `new_price` decimal(10,2) NOT NULL,
  `changed_by` int DEFAULT NULL,
  `changed_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`history_id`),
  KEY `fk_pph_prod` (`product_id`),
  KEY `fk_pph_emp` (`changed_by`),
  CONSTRAINT `fk_pph_emp` FOREIGN KEY (`changed_by`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `fk_pph_prod` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`),
  CONSTRAINT `chk_pph_prices` CHECK (((`old_price` > 0) and (`new_price` > 0)))
) ENGINE=InnoDB AUTO_INCREMENT=14 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `products`;
CREATE TABLE `products` (
  `product_id` int NOT NULL AUTO_INCREMENT,
  `barcode` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL,
  `name` varchar(150) COLLATE utf8mb4_unicode_ci NOT NULL,
  `category_id` int NOT NULL,
  `supplier_id` int NOT NULL,
  `brand` varchar(80) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `unit_price` decimal(10,2) NOT NULL,
  `cost_price` decimal(10,2) NOT NULL,
  `tax_rate` decimal(5,2) NOT NULL DEFAULT '0.00',
  `reorder_level` int NOT NULL DEFAULT '10',
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`product_id`),
  UNIQUE KEY `barcode` (`barcode`),
  KEY `fk_prod_cat` (`category_id`),
  KEY `fk_prod_supp` (`supplier_id`),
  FULLTEXT KEY `ft_prod_name` (`name`),
  CONSTRAINT `fk_prod_cat` FOREIGN KEY (`category_id`) REFERENCES `categories` (`category_id`),
  CONSTRAINT `fk_prod_supp` FOREIGN KEY (`supplier_id`) REFERENCES `suppliers` (`supplier_id`),
  CONSTRAINT `chk_price` CHECK (((`unit_price` > 0) and (`cost_price` >= 0) and (`cost_price` <= `unit_price`)))
) ENGINE=InnoDB AUTO_INCREMENT=29 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `promotions`;
CREATE TABLE `promotions` (
  `promo_id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `discount_percent` decimal(5,2) NOT NULL,
  `start_date` date NOT NULL,
  `end_date` date NOT NULL,
  `product_id` int DEFAULT NULL,
  `category_id` int DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  PRIMARY KEY (`promo_id`),
  KEY `fk_promo_prod` (`product_id`),
  KEY `fk_promo_cat` (`category_id`),
  CONSTRAINT `fk_promo_cat` FOREIGN KEY (`category_id`) REFERENCES `categories` (`category_id`),
  CONSTRAINT `fk_promo_prod` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`),
  CONSTRAINT `chk_dates` CHECK ((`end_date` >= `start_date`)),
  CONSTRAINT `chk_disc` CHECK (((`discount_percent` > 0) and (`discount_percent` <= 100))),
  CONSTRAINT `chk_promo_target` CHECK (((`product_id` is null) or (`category_id` is null)))
) ENGINE=InnoDB AUTO_INCREMENT=15 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `purchase_order_items`;
CREATE TABLE `purchase_order_items` (
  `po_item_id` int NOT NULL AUTO_INCREMENT,
  `po_id` int NOT NULL,
  `product_id` int NOT NULL,
  `quantity` int NOT NULL,
  `received_quantity` int DEFAULT NULL,
  `damaged_quantity` int DEFAULT '0',
  `shortage_quantity` int DEFAULT '0',
  `discrepancy_reason` enum('NONE','DAMAGED_IN_TRANSIT','PACKAGING_BROKEN','EXPIRED_ON_ARRIVAL','SUPPLIER_SHORTAGE','WRONG_PRODUCT','QUALITY_DEFECT') COLLATE utf8mb4_unicode_ci DEFAULT 'NONE',
  `discrepancy_notes` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `unit_cost` decimal(10,2) NOT NULL,
  PRIMARY KEY (`po_item_id`),
  UNIQUE KEY `uq_po_product` (`po_id`,`product_id`),
  KEY `fk_poi_prod` (`product_id`),
  CONSTRAINT `fk_poi_po` FOREIGN KEY (`po_id`) REFERENCES `purchase_orders` (`po_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_poi_prod` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`),
  CONSTRAINT `purchase_order_items_chk_1` CHECK ((`quantity` > 0)),
  CONSTRAINT `purchase_order_items_chk_2` CHECK ((`unit_cost` > 0))
) ENGINE=InnoDB AUTO_INCREMENT=19 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `purchase_orders`;
CREATE TABLE `purchase_orders` (
  `po_id` int NOT NULL AUTO_INCREMENT,
  `po_number` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `supplier_id` int NOT NULL,
  `branch_id` int NOT NULL,
  `created_by` int NOT NULL,
  `order_date` date NOT NULL,
  `expected_date` date DEFAULT NULL,
  `status` enum('DRAFT','SENT','RECEIVED','CANCELLED') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'DRAFT',
  `total_cost` decimal(12,2) NOT NULL DEFAULT '0.00',
  `received_date` date DEFAULT NULL,
  PRIMARY KEY (`po_id`),
  KEY `fk_po_supp` (`supplier_id`),
  KEY `fk_po_branch` (`branch_id`),
  KEY `fk_po_emp` (`created_by`),
  CONSTRAINT `fk_po_branch` FOREIGN KEY (`branch_id`) REFERENCES `branches` (`branch_id`),
  CONSTRAINT `fk_po_emp` FOREIGN KEY (`created_by`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `fk_po_supp` FOREIGN KEY (`supplier_id`) REFERENCES `suppliers` (`supplier_id`),
  CONSTRAINT `chk_po_dates` CHECK (((`expected_date` is null) or (`expected_date` >= `order_date`))),
  CONSTRAINT `chk_po_total` CHECK ((`total_cost` >= 0))
) ENGINE=InnoDB AUTO_INCREMENT=11 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `returns`;
CREATE TABLE `returns` (
  `return_id` int NOT NULL AUTO_INCREMENT,
  `sale_item_id` int NOT NULL,
  `quantity` int NOT NULL,
  `reason` varchar(200) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `refund_amount` decimal(10,2) NOT NULL,
  `processed_by` int NOT NULL,
  `return_date` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`return_id`),
  KEY `fk_ret_item` (`sale_item_id`),
  KEY `fk_ret_emp` (`processed_by`),
  CONSTRAINT `fk_ret_emp` FOREIGN KEY (`processed_by`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `fk_ret_item` FOREIGN KEY (`sale_item_id`) REFERENCES `sale_items` (`sale_item_id`),
  CONSTRAINT `chk_ret_refund` CHECK ((`refund_amount` >= 0)),
  CONSTRAINT `returns_chk_1` CHECK ((`quantity` > 0))
) ENGINE=InnoDB AUTO_INCREMENT=8 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `sale_items`;
CREATE TABLE `sale_items` (
  `sale_item_id` int NOT NULL AUTO_INCREMENT,
  `sale_id` int NOT NULL,
  `product_id` int NOT NULL,
  `quantity` int NOT NULL,
  `unit_price` decimal(10,2) NOT NULL,
  `discount_amount` decimal(10,2) NOT NULL DEFAULT '0.00',
  `line_total` decimal(12,2) NOT NULL,
  PRIMARY KEY (`sale_item_id`),
  KEY `fk_si_prod` (`product_id`),
  KEY `idx_si_sale` (`sale_id`),
  CONSTRAINT `fk_si_prod` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`),
  CONSTRAINT `fk_si_sale` FOREIGN KEY (`sale_id`) REFERENCES `sales` (`sale_id`) ON DELETE CASCADE,
  CONSTRAINT `chk_si_amounts` CHECK (((`unit_price` > 0) and (`discount_amount` >= 0) and (`line_total` >= 0))),
  CONSTRAINT `sale_items_chk_1` CHECK ((`quantity` > 0))
) ENGINE=InnoDB AUTO_INCREMENT=139 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `sales`;
CREATE TABLE `sales` (
  `sale_id` int NOT NULL AUTO_INCREMENT,
  `branch_id` int NOT NULL,
  `cashier_id` int NOT NULL,
  `customer_id` int DEFAULT NULL,
  `promo_id` int DEFAULT NULL,
  `coupon_id` int DEFAULT NULL,
  `sale_date` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `status` enum('OPEN','COMPLETED','CANCELLED') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'OPEN',
  `subtotal` decimal(12,2) NOT NULL DEFAULT '0.00',
  `discount_total` decimal(12,2) NOT NULL DEFAULT '0.00',
  `tax_total` decimal(12,2) NOT NULL DEFAULT '0.00',
  `total_amount` decimal(12,2) NOT NULL DEFAULT '0.00',
  `tendered_cash` decimal(12,2) DEFAULT NULL,
  `change_amount` decimal(12,2) DEFAULT NULL,
  PRIMARY KEY (`sale_id`),
  KEY `fk_sale_branch` (`branch_id`),
  KEY `fk_sale_cash` (`cashier_id`),
  KEY `fk_sale_cust` (`customer_id`),
  KEY `fk_sale_promo` (`promo_id`),
  KEY `fk_sale_coupon` (`coupon_id`),
  KEY `idx_sale_date` (`sale_date`),
  CONSTRAINT `fk_sale_branch` FOREIGN KEY (`branch_id`) REFERENCES `branches` (`branch_id`),
  CONSTRAINT `fk_sale_cash` FOREIGN KEY (`cashier_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `fk_sale_coupon` FOREIGN KEY (`coupon_id`) REFERENCES `coupons` (`coupon_id`),
  CONSTRAINT `fk_sale_cust` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`),
  CONSTRAINT `fk_sale_promo` FOREIGN KEY (`promo_id`) REFERENCES `promotions` (`promo_id`),
  CONSTRAINT `chk_sales_amounts` CHECK (((`subtotal` >= 0) and (`discount_total` >= 0) and (`tax_total` >= 0) and (`total_amount` >= 0)))
) ENGINE=InnoDB AUTO_INCREMENT=74 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `shifts`;
CREATE TABLE `shifts` (
  `shift_id` int NOT NULL AUTO_INCREMENT,
  `employee_id` int NOT NULL,
  `branch_id` int NOT NULL,
  `shift_date` date NOT NULL,
  `start_time` time NOT NULL,
  `end_time` time NOT NULL,
  `clock_in` datetime DEFAULT NULL,
  `clock_out` datetime DEFAULT NULL,
  `status` enum('SCHEDULED','PRESENT','ABSENT','COMPLETED') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'SCHEDULED',
  PRIMARY KEY (`shift_id`),
  KEY `fk_shift_branch` (`branch_id`),
  KEY `idx_shift_emp_date` (`employee_id`,`shift_date`),
  CONSTRAINT `fk_shift_branch` FOREIGN KEY (`branch_id`) REFERENCES `branches` (`branch_id`),
  CONSTRAINT `fk_shift_emp` FOREIGN KEY (`employee_id`) REFERENCES `employees` (`employee_id`)
) ENGINE=InnoDB AUTO_INCREMENT=33 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `slow_movers`;
CREATE TABLE `slow_movers` (
  `slow_id` int NOT NULL AUTO_INCREMENT,
  `product_id` int NOT NULL,
  `flagged_date` date NOT NULL,
  `days_since_last_sale` int NOT NULL,
  `note` varchar(200) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`slow_id`),
  KEY `fk_slow_prod` (`product_id`),
  CONSTRAINT `fk_slow_prod` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `stock_alerts`;
CREATE TABLE `stock_alerts` (
  `alert_id` int NOT NULL AUTO_INCREMENT,
  `branch_id` int NOT NULL,
  `product_id` int NOT NULL,
  `alert_type` enum('LOW_STOCK','OUT_OF_STOCK','EXPIRY') COLLATE utf8mb4_unicode_ci NOT NULL,
  `message` varchar(200) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `is_resolved` tinyint(1) NOT NULL DEFAULT '0',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`alert_id`),
  KEY `fk_alert_branch` (`branch_id`),
  KEY `fk_alert_prod` (`product_id`),
  CONSTRAINT `fk_alert_branch` FOREIGN KEY (`branch_id`) REFERENCES `branches` (`branch_id`),
  CONSTRAINT `fk_alert_prod` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`)
) ENGINE=InnoDB AUTO_INCREMENT=33 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `suppliers`;
CREATE TABLE `suppliers` (
  `supplier_id` int NOT NULL AUTO_INCREMENT,
  `supplier_code` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL,
  `name` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `contact_name` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `phone` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `email` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `address` varchar(200) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  PRIMARY KEY (`supplier_id`),
  UNIQUE KEY `supplier_code` (`supplier_code`)
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;
