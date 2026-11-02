-- ETL STEP 3: load the two fact tables (surrogate-key lookups, unknown-member handling, measure derivation)
USE supermarket_dw;
SET FOREIGN_KEY_CHECKS=0; TRUNCATE fact_sales; TRUNCATE fact_procurement; SET FOREIGN_KEY_CHECKS=1;

-- ---------- Quarantine: online orders that break a business rule (future-dated 'DELIVERED' orders)
TRUNCATE etl_reject_online_orders;
INSERT INTO etl_reject_online_orders (order_id, order_date, barcode, branch_code, quantity, unit_price, discount_rate, card_no, delivery_status, reject_reason)
SELECT order_id, order_date, barcode, branch_code, quantity, unit_price, discount_rate, card_no, delivery_status, 'order_date is after max_valid_order_date'
FROM stg_online_orders WHERE dq_future_date = 1;

-- ---------- FACT 1a: in-store sales (Source 1) -------------------------
INSERT INTO fact_sales (date_key, product_key, branch_key, customer_key, channel_key, promotion_key, source_order_no, source_line_no,
                        quantity, unit_price, gross_amount, discount_amount, net_amount, tax_amount, cost_amount, gross_profit, returned_qty, refund_amount)
SELECT CAST(DATE_FORMAT(s.sale_date,'%Y%m%d') AS UNSIGNED),
       COALESCE(p.product_key,-1), COALESCE(b.branch_key,-1), COALESCE(c.customer_key,-1), 1,
       CASE WHEN si.discount_amount > 0 AND dp.promotion_key IS NOT NULL THEN dp.promotion_key ELSE 0 END,
       CONCAT('POS-', s.sale_id), si.sale_item_id,
       si.quantity, si.unit_price, ROUND(si.quantity*si.unit_price,2), si.discount_amount, si.line_total,
       ROUND(si.line_total * COALESCE(p.tax_rate,0)/100, 2),
       ROUND(si.quantity * COALESCE(p.cost_price,0), 2),
       ROUND(si.line_total - si.quantity * COALESCE(p.cost_price,0), 2),
       COALESCE(r.ret_qty,0), COALESCE(r.ret_amt,0)
FROM stg_pos_sale_item si
JOIN stg_pos_sale s ON s.sale_id = si.sale_id AND s.status = 'COMPLETED'          -- business rule: only COMPLETED sales
LEFT JOIN dim_product  p ON p.product_id = si.product_id AND DATE(s.sale_date) BETWEEN p.effective_from AND p.effective_to
LEFT JOIN dim_branch   b ON b.branch_id  = s.branch_id
LEFT JOIN dim_customer c ON c.customer_id = s.customer_id AND DATE(s.sale_date) BETWEEN c.effective_from AND c.effective_to
LEFT JOIN dim_promotion dp ON dp.promo_id = s.promo_id
LEFT JOIN (SELECT sale_item_id, SUM(quantity) ret_qty, SUM(refund_amount) ret_amt FROM stg_pos_return GROUP BY sale_item_id) r ON r.sale_item_id = si.sale_item_id;

-- ---------- FACT 1b: online orders (Source 2 - CSV) ---------------------
INSERT INTO fact_sales (date_key, product_key, branch_key, customer_key, channel_key, promotion_key, source_order_no, source_line_no,
                        quantity, unit_price, gross_amount, discount_amount, net_amount, tax_amount, cost_amount, gross_profit, returned_qty, refund_amount)
SELECT CAST(DATE_FORMAT(o.order_date,'%Y%m%d') AS UNSIGNED),
       COALESCE(p.product_key,-1), COALESCE(b.branch_key,-1), COALESCE(c.customer_key,-1), 2,
       CASE WHEN o.discount_rate > 0 THEN -2 ELSE 0 END,
       CONCAT('ONL-', o.order_id), 1,
       o.quantity, o.unit_price, ROUND(o.quantity*o.unit_price,2),
       ROUND(o.quantity*o.unit_price*o.discount_rate,2),                                    -- CSV holds a RATE, warehouse stores an AMOUNT
       ROUND(o.quantity*o.unit_price*(1-o.discount_rate),2),
       ROUND(o.quantity*o.unit_price*(1-o.discount_rate) * COALESCE(p.tax_rate,0)/100, 2),
       ROUND(o.quantity * COALESCE(p.cost_price,0), 2),
       ROUND(o.quantity*o.unit_price*(1-o.discount_rate) - o.quantity*COALESCE(p.cost_price,0), 2), 0, 0
FROM stg_online_orders o
LEFT JOIN dim_product  p ON p.barcode = o.barcode AND o.order_date BETWEEN p.effective_from AND p.effective_to
LEFT JOIN dim_branch   b ON b.branch_code = o.branch_code
LEFT JOIN dim_customer c ON c.card_no = o.card_no AND o.order_date BETWEEN c.effective_from AND c.effective_to
WHERE o.delivery_status = 'DELIVERED' AND o.dq_future_date = 0;                                                      -- business rule: revenue recognised on delivery

-- ---------- FACT 2: procurement (Source 1) ------------------------------
INSERT INTO fact_procurement (order_date_key, received_date_key, product_key, supplier_key, branch_key, po_number, po_line_no, discrepancy_reason,
                              ordered_qty, received_qty, damaged_qty, shortage_qty, unit_cost, ordered_amount, received_amount, lost_amount,
                              lead_time_days, delay_days, on_time_flag)
SELECT CAST(DATE_FORMAT(po.order_date,'%Y%m%d') AS UNSIGNED), CAST(DATE_FORMAT(po.received_date,'%Y%m%d') AS UNSIGNED),
       COALESCE(p.product_key,-1), COALESCE(s.supplier_key,-1), COALESCE(b.branch_key,-1),
       po.po_number, pi.po_item_id, COALESCE(pi.discrepancy_reason,'NONE'),
       pi.quantity, COALESCE(pi.received_quantity,0), COALESCE(pi.damaged_quantity,0), COALESCE(pi.shortage_quantity,0), pi.unit_cost,
       ROUND(pi.quantity*pi.unit_cost,2), ROUND(COALESCE(pi.received_quantity,0)*pi.unit_cost,2),
       ROUND((COALESCE(pi.damaged_quantity,0)+COALESCE(pi.shortage_quantity,0))*pi.unit_cost,2),
       DATEDIFF(po.received_date, po.order_date), DATEDIFF(po.received_date, po.expected_date),
       IF(po.received_date <= po.expected_date,1,0)
FROM stg_po_item pi
JOIN stg_po po ON po.po_id = pi.po_id AND po.status = 'RECEIVED'                           -- business rule: only RECEIVED POs
LEFT JOIN dim_product  p ON p.product_id = pi.product_id AND po.order_date BETWEEN p.effective_from AND p.effective_to
LEFT JOIN dim_supplier s ON s.supplier_id = po.supplier_id
LEFT JOIN dim_branch   b ON b.branch_id = po.branch_id;

INSERT INTO etl_run_log(step_name, rows_loaded) SELECT 'fact_sales (POS + online)', COUNT(*) FROM fact_sales;
INSERT INTO etl_run_log(step_name, rows_loaded) SELECT 'fact_procurement', COUNT(*) FROM fact_procurement;
INSERT INTO etl_run_log(step_name, rows_loaded, status, note) SELECT 'rejected online orders', COUNT(*), 'REJECT', 'future-dated' FROM etl_reject_online_orders;
