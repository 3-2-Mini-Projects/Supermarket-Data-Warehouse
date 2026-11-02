-- ETL STEP 1: refresh staging from Source 1 (MySQL OLTP). Source 2 (CSV) and Source 3 (API) are loaded by Python.
USE supermarket_dw;
SET FOREIGN_KEY_CHECKS=0;
TRUNCATE stg_product; TRUNCATE stg_price_history; TRUNCATE stg_customer; TRUNCATE stg_tier_history; TRUNCATE stg_branch;
TRUNCATE stg_supplier; TRUNCATE stg_promotion; TRUNCATE stg_pos_sale; TRUNCATE stg_pos_sale_item; TRUNCATE stg_pos_return;
TRUNCATE stg_po; TRUNCATE stg_po_item;
SET FOREIGN_KEY_CHECKS=1;

INSERT INTO stg_product
SELECT p.product_id, p.barcode, p.name, p.brand, c.name, COALESCE(pc.name, c.name), p.unit_price, p.cost_price, p.tax_rate, p.is_active
FROM supermarket_oltp.products p
JOIN supermarket_oltp.categories c ON c.category_id = p.category_id
LEFT JOIN supermarket_oltp.categories pc ON pc.category_id = c.parent_id;

INSERT INTO stg_price_history SELECT history_id, product_id, old_price, new_price, changed_at FROM supermarket_oltp.product_price_history;
INSERT INTO stg_customer      SELECT customer_id, card_no, full_name, city, join_date, tier, is_active FROM supermarket_oltp.customers;
INSERT INTO stg_tier_history  SELECT history_id, customer_id, old_tier, new_tier, changed_at FROM supermarket_oltp.customer_tier_history;
INSERT INTO stg_branch
SELECT b.branch_id, b.branch_code, b.name, b.city, b.region, b.opened_date, b.is_active, e.full_name
FROM supermarket_oltp.branches b LEFT JOIN supermarket_oltp.employees e ON e.employee_id = b.manager_id;
INSERT INTO stg_supplier      SELECT supplier_id, supplier_code, name, contact_name, is_active FROM supermarket_oltp.suppliers;
INSERT INTO stg_promotion
SELECT p.promo_id, p.name, p.discount_percent, p.start_date, p.end_date,
       CASE WHEN p.product_id IS NOT NULL THEN 'PRODUCT' WHEN p.category_id IS NOT NULL THEN 'CATEGORY' ELSE 'STOREWIDE' END,
       COALESCE(pr.name, ca.name, 'All products')
FROM supermarket_oltp.promotions p
LEFT JOIN supermarket_oltp.products pr ON pr.product_id = p.product_id
LEFT JOIN supermarket_oltp.categories ca ON ca.category_id = p.category_id;
INSERT INTO stg_pos_sale      SELECT sale_id, branch_id, customer_id, promo_id, sale_date, status FROM supermarket_oltp.sales;
INSERT INTO stg_pos_sale_item SELECT sale_item_id, sale_id, product_id, quantity, unit_price, discount_amount, line_total FROM supermarket_oltp.sale_items;
INSERT INTO stg_pos_return    SELECT return_id, sale_item_id, quantity, refund_amount FROM supermarket_oltp.returns;
INSERT INTO stg_po            SELECT po_id, po_number, supplier_id, branch_id, order_date, expected_date, received_date, status FROM supermarket_oltp.purchase_orders;
INSERT INTO stg_po_item       SELECT po_item_id, po_id, product_id, quantity, received_quantity, damaged_quantity, shortage_quantity, discrepancy_reason, unit_cost FROM supermarket_oltp.purchase_order_items;

INSERT INTO etl_run_log(step_name, rows_loaded) SELECT 'staging: POS sale lines', COUNT(*) FROM stg_pos_sale_item;
