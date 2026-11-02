USE supermarket_dw;
-- V1 row-count reconciliation: source -> warehouse
SELECT 'POS completed lines (source)' AS check_name, COUNT(*) AS source_value,
       (SELECT COUNT(*) FROM fact_sales WHERE channel_key=1) AS dw_value
FROM supermarket_oltp.sale_items si JOIN supermarket_oltp.sales s USING(sale_id) WHERE s.status='COMPLETED'
UNION ALL SELECT 'Online CSV rows (loaded + rejected)', (SELECT COUNT(*) FROM stg_online_orders), (SELECT COUNT(*) FROM fact_sales WHERE channel_key=2) + (SELECT COUNT(*) FROM etl_reject_online_orders)
UNION ALL SELECT 'Received PO lines (source)', COUNT(*), (SELECT COUNT(*) FROM fact_procurement)
FROM supermarket_oltp.purchase_order_items i JOIN supermarket_oltp.purchase_orders p USING(po_id) WHERE p.status='RECEIVED';
-- V2 amount reconciliation
SELECT 'POS net revenue (source line_total vs DW net_amount)' AS check_name,
       (SELECT SUM(si.line_total) FROM supermarket_oltp.sale_items si JOIN supermarket_oltp.sales s USING(sale_id) WHERE s.status='COMPLETED') AS source_value,
       (SELECT SUM(net_amount) FROM fact_sales WHERE channel_key=1) AS dw_value
UNION ALL SELECT 'POS tax (source sales.tax_total vs DW tax_amount)',
       (SELECT SUM(tax_total) FROM supermarket_oltp.sales WHERE status='COMPLETED'), (SELECT SUM(tax_amount) FROM fact_sales WHERE channel_key=1)
UNION ALL SELECT 'Online net revenue (CSV recomputed vs DW)',
       (SELECT SUM(quantity*unit_price*(1-discount_rate)) FROM stg_online_orders WHERE dq_future_date=0), (SELECT SUM(net_amount) FROM fact_sales WHERE channel_key=2)
UNION ALL SELECT 'PO ordered amount (source vs DW)',
       (SELECT SUM(i.quantity*i.unit_cost) FROM supermarket_oltp.purchase_order_items i JOIN supermarket_oltp.purchase_orders p USING(po_id) WHERE p.status='RECEIVED'),
       (SELECT SUM(ordered_amount) FROM fact_procurement)
UNION ALL SELECT 'Refunds (source vs DW)', (SELECT SUM(refund_amount) FROM supermarket_oltp.returns), (SELECT SUM(refund_amount) FROM fact_sales);
-- V3 unknown-member counts (orphan handling)
SELECT 'fact_sales rows with product_key=-1' AS check_name, COUNT(*) AS n FROM fact_sales WHERE product_key=-1
UNION ALL SELECT 'fact_sales rows with customer_key=-1 (POS walk-ins + unmatched)', COUNT(*) FROM fact_sales WHERE customer_key=-1
UNION ALL SELECT '   of which ONLINE (unmatched card_no)', COUNT(*) FROM fact_sales WHERE customer_key=-1 AND channel_key=2
UNION ALL SELECT 'fact_sales rows with branch_key=-1', COUNT(*) FROM fact_sales WHERE branch_key=-1
UNION ALL SELECT 'fact_procurement rows with unknown keys', COUNT(*) FROM fact_procurement WHERE product_key=-1 OR supplier_key=-1 OR branch_key=-1;
-- V4 grain / duplicate check
SELECT 'duplicate (order_no,line_no) in fact_sales' AS check_name, COUNT(*) AS n FROM (SELECT source_order_no, source_line_no FROM fact_sales GROUP BY 1,2 HAVING COUNT(*)>1) x;
-- V5 SCD-2 integrity: exactly one current row per natural key, no overlaps
SELECT 'products with <>1 current row' AS check_name, COUNT(*) AS n FROM (SELECT product_id FROM dim_product WHERE product_id IS NOT NULL GROUP BY product_id HAVING SUM(is_current)<>1) x
UNION ALL SELECT 'customers with <>1 current row', COUNT(*) FROM (SELECT customer_id FROM dim_customer WHERE customer_id IS NOT NULL GROUP BY customer_id HAVING SUM(is_current)<>1) x
UNION ALL SELECT 'overlapping product versions', COUNT(*) FROM dim_product a JOIN dim_product b ON a.product_id=b.product_id AND a.product_key<b.product_key AND a.effective_from<=b.effective_to AND b.effective_from<=a.effective_to;
-- V6 holiday enrichment & DQ flags
SELECT 'dim_date holiday rows (is_holiday=1)' AS check_name, SUM(is_holiday) AS n FROM dim_date
UNION ALL SELECT 'dim_date Poya days', SUM(is_poya_day) FROM dim_date
UNION ALL SELECT 'CSV rows rejected (future-dated)', COUNT(*) FROM etl_reject_online_orders
UNION ALL SELECT 'CSV orders placed before the card join date', COUNT(*) FROM stg_online_orders o JOIN supermarket_oltp.customers c ON c.card_no=o.card_no WHERE o.order_date < c.join_date
UNION ALL SELECT 'CSV rows with price >2x or <0.5x list price (dq_price_outlier)', SUM(dq_price_outlier) FROM stg_online_orders;
