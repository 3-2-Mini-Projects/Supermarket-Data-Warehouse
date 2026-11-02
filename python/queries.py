# 25 advanced business queries (MySQL 8.0). Revenue = net_amount (after discount, before tax).
END = "'2026-10-28'"   # last POS trading day in the data set
Q = []
def q(title, question, tech, sql, note=""): Q.append(dict(n=len(Q)+1, title=title, question=question, tech=tech, sql=sql.strip(), note=note))

q("Annual revenue by channel with year-over-year growth",
  "How fast is each sales channel growing year on year?", "CTE, LAG(), window per channel",
"""WITH yr AS (
  SELECT d.year_no, c.channel_name,
         SUM(f.net_amount) AS revenue, COUNT(DISTINCT f.source_order_no) AS orders
  FROM fact_sales f
  JOIN dim_date d    ON d.date_key    = f.date_key
  JOIN dim_channel c ON c.channel_key = f.channel_key
  GROUP BY d.year_no, c.channel_name)
SELECT channel_name, year_no, ROUND(revenue) AS revenue, orders,
       ROUND(100*(revenue - LAG(revenue) OVER w) / LAG(revenue) OVER w, 1) AS yoy_pct
FROM yr
WINDOW w AS (PARTITION BY channel_name ORDER BY year_no)
ORDER BY channel_name, year_no;""", "2026 is year-to-date (trading data ends 28 Oct 2026), so its YoY is understated.")

q("Monthly revenue with 3-month moving average and year-to-date total",
  "What is the underlying monthly trend once seasonality noise is smoothed out?", "CTE, moving-average window frame, running SUM per year",
"""WITH m AS (
  SELECT d.year_no, d.month_no, d.yearmonth, SUM(f.net_amount) AS rev
  FROM fact_sales f JOIN dim_date d ON d.date_key = f.date_key
  GROUP BY d.year_no, d.month_no, d.yearmonth)
SELECT yearmonth, ROUND(rev) AS revenue,
       ROUND(AVG(rev) OVER (ORDER BY yearmonth ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)) AS moving_avg_3m,
       ROUND(SUM(rev) OVER (PARTITION BY year_no ORDER BY month_no)) AS ytd_revenue
FROM m
ORDER BY yearmonth DESC
LIMIT 12;""", "Latest 12 months shown.")

q("Branch ranking per year with market share and rank movement",
  "Which branches are rising or falling in the league table?", "Two CTEs, RANK(), SUM() OVER share, LAG() on a ranking",
"""WITH b AS (
  SELECT d.year_no, br.branch_name, br.region, SUM(f.net_amount) AS rev
  FROM fact_sales f
  JOIN dim_date d    ON d.date_key   = f.date_key
  JOIN dim_branch br ON br.branch_key = f.branch_key
  GROUP BY d.year_no, br.branch_name, br.region),
r AS (
  SELECT *, RANK() OVER (PARTITION BY year_no ORDER BY rev DESC) AS rnk,
         100*rev / SUM(rev) OVER (PARTITION BY year_no) AS share_pct
  FROM b)
SELECT year_no, branch_name, region, ROUND(rev) AS revenue, rnk AS rank_now,
       CAST(LAG(rnk) OVER (PARTITION BY branch_name ORDER BY year_no) AS SIGNED) - CAST(rnk AS SIGNED) AS places_gained,
       ROUND(share_pct,1) AS share_pct
FROM r
ORDER BY year_no DESC, rnk
LIMIT 8;""", "Latest year (2026, YTD) shown; places_gained compares with the previous year.")

q("Top 3 products in every parent category (in-store margin)",
  "Which products drive each category, and are they profitable?", "ROW_NUMBER() PARTITION BY, SCD-2 roll-up by natural key",
"""SELECT parent_category, product_name, revenue, margin_pct, rn AS rank_in_category
FROM (
  SELECT p.parent_category, p.product_id, p.product_name,
         ROUND(SUM(f.net_amount)) AS revenue,
         ROUND(100*SUM(f.gross_profit)/SUM(f.net_amount),1) AS margin_pct,
         ROW_NUMBER() OVER (PARTITION BY p.parent_category ORDER BY SUM(f.net_amount) DESC) AS rn
  FROM fact_sales f JOIN dim_product p ON p.product_key = f.product_key
  WHERE f.channel_key = 1                      -- in-store only: online prices are unreliable (see DQ section)
  GROUP BY p.parent_category, p.product_id, p.product_name) t
WHERE rn <= 3
ORDER BY parent_category, rn;""", "Grouped by product_id (not product_key) so all price versions of a product are combined.")

q("Pareto / ABC classification of products",
  "Which few products generate most of the revenue?", "Cumulative SUM() window, CASE classification",
"""WITH pr AS (
  SELECT p.product_id, p.product_name, SUM(f.net_amount) AS rev
  FROM fact_sales f JOIN dim_product p ON p.product_key = f.product_key
  GROUP BY p.product_id, p.product_name),
cum AS (
  SELECT *, SUM(rev) OVER (ORDER BY rev DESC, product_id) AS cum_rev, SUM(rev) OVER () AS tot FROM pr)
SELECT product_name, ROUND(rev) AS revenue, ROUND(100*rev/tot,1) AS share_pct,
       ROUND(100*cum_rev/tot,1) AS cumulative_pct,
       CASE WHEN cum_rev/tot <= 0.70 THEN 'A' WHEN cum_rev/tot <= 0.90 THEN 'B' ELSE 'C' END AS abc_class
FROM cum
ORDER BY rev DESC
LIMIT 12;""", "Top 12 of 30 products shown.")

q("Category x quarter revenue matrix with grand-total row (2025)",
  "How is revenue split across categories and quarters in the latest full year?", "GROUP BY ... WITH ROLLUP, GROUPING(), conditional pivot",
"""SELECT IF(GROUPING(p.parent_category), '** ALL CATEGORIES **', p.parent_category) AS category,
       ROUND(SUM(CASE WHEN d.quarter_no = 1 THEN f.net_amount END)) AS q1,
       ROUND(SUM(CASE WHEN d.quarter_no = 2 THEN f.net_amount END)) AS q2,
       ROUND(SUM(CASE WHEN d.quarter_no = 3 THEN f.net_amount END)) AS q3,
       ROUND(SUM(CASE WHEN d.quarter_no = 4 THEN f.net_amount END)) AS q4,
       ROUND(SUM(f.net_amount)) AS year_total
FROM fact_sales f
JOIN dim_date d    ON d.date_key    = f.date_key
JOIN dim_product p ON p.product_key = f.product_key
WHERE d.year_no = 2025
GROUP BY p.parent_category WITH ROLLUP;""")

q("Revenue per day by day type: weekday, weekend, public holiday, Poya day",
  "Do customers shop more or less on holidays, Poya days and weekends?", "Calendar spine (LEFT JOIN from dim_date so zero-sales days count), Holiday-API attributes",
f"""WITH daily AS (
  SELECT d.date_key, d.day_type, d.holiday_class, COALESCE(SUM(f.net_amount),0) AS rev
  FROM dim_date d LEFT JOIN fact_sales f ON f.date_key = d.date_key
  WHERE d.full_date BETWEEN '2022-01-01' AND {END}
  GROUP BY d.date_key, d.day_type, d.holiday_class)
SELECT day_type, holiday_class, COUNT(*) AS days, ROUND(AVG(rev)) AS avg_daily_revenue,
       ROUND(100*AVG(rev) / (SELECT AVG(rev) FROM daily WHERE day_type = 'Weekday')) AS index_vs_weekday
FROM daily
GROUP BY day_type, holiday_class
ORDER BY avg_daily_revenue DESC;""", "Index 100 = an ordinary weekday.")

q("Holiday sales uplift versus the preceding 7-day baseline",
  "Which holidays produce the biggest sales spike (or dip) compared with normal trading?", "Window frame ROWS 7 PRECEDING AND 1 PRECEDING, ranking",
f"""WITH daily AS (
  SELECT d.full_date, d.holiday_name, d.is_holiday, COALESCE(SUM(f.net_amount),0) AS rev
  FROM dim_date d LEFT JOIN fact_sales f ON f.date_key = d.date_key
  WHERE d.full_date BETWEEN '2022-01-01' AND {END}
  GROUP BY d.full_date, d.holiday_name, d.is_holiday),
base AS (
  SELECT *, AVG(rev) OVER (ORDER BY full_date ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING) AS baseline FROM daily)
SELECT full_date, holiday_name, ROUND(rev) AS revenue, ROUND(baseline) AS baseline_7d,
       ROUND(100*(rev/baseline - 1),1) AS uplift_pct
FROM base
WHERE is_holiday = 1 AND baseline > 0 AND full_date >= '2025-01-01'
ORDER BY uplift_pct DESC
LIMIT 10;""", "Holidays since 2025 only; top 10 by uplift.")

q("RFM customer segmentation",
  "Who are our best, loyal and at-risk loyalty-card customers?", "NTILE() scoring, CASE segmentation, aggregation of a derived table",
f"""WITH cust AS (
  SELECT c.customer_id, MAX(d.full_date) AS last_buy,
         COUNT(DISTINCT f.source_order_no) AS frequency, SUM(f.net_amount) AS monetary
  FROM fact_sales f
  JOIN dim_customer c ON c.customer_key = f.customer_key AND c.customer_id IS NOT NULL
  JOIN dim_date d     ON d.date_key     = f.date_key
  WHERE d.full_date <= {END}
  GROUP BY c.customer_id),
scored AS (
  SELECT *, DATEDIFF({END}, last_buy) AS recency_days,
         NTILE(4) OVER (ORDER BY DATEDIFF({END}, last_buy) DESC) AS r,
         NTILE(4) OVER (ORDER BY frequency) AS f,
         NTILE(4) OVER (ORDER BY monetary)  AS m
  FROM cust),
seg AS (
  SELECT *, CASE WHEN r>=3 AND f>=3 AND m>=3 THEN '1-Champions'
                 WHEN r>=3 AND f>=2             THEN '2-Loyal / active'
                 WHEN r<=2 AND m>=3             THEN '3-Big spenders at risk'
                 ELSE                                '4-Hibernating' END AS segment
  FROM scored)
SELECT segment, COUNT(*) AS customers, ROUND(SUM(monetary)) AS revenue,
       ROUND(100*SUM(monetary)/SUM(SUM(monetary)) OVER (),1) AS revenue_share_pct,
       ROUND(AVG(frequency),1) AS avg_orders, ROUND(AVG(recency_days)) AS avg_days_since_last_buy
FROM seg GROUP BY segment ORDER BY segment;""", "Only identified loyalty-card customers (walk-ins excluded). Reference date = last trading day.")

q("Loyalty tier at time of purchase versus current tier (SCD Type 2 in action)",
  "How much revenue was earned from customers who have since been upgraded?", "Self-join of an SCD-2 dimension (historical vs current row)",
"""SELECT h.loyalty_tier AS tier_at_purchase, cur.loyalty_tier AS tier_today,
       COUNT(DISTINCT h.customer_id) AS customers,
       ROUND(SUM(f.net_amount)) AS revenue,
       ROUND(100*SUM(f.net_amount)/SUM(SUM(f.net_amount)) OVER (),1) AS pct_of_loyalty_revenue
FROM fact_sales f
JOIN dim_customer h   ON h.customer_key = f.customer_key AND h.customer_id IS NOT NULL
JOIN dim_customer cur ON cur.customer_id = h.customer_id AND cur.is_current = 1
GROUP BY h.loyalty_tier, cur.loyalty_tier
ORDER BY FIELD(h.loyalty_tier,'BRONZE','SILVER','GOLD','PLATINUM'), FIELD(cur.loyalty_tier,'BRONZE','SILVER','GOLD','PLATINUM');""",
  "Rows where the two tiers differ are customers who migrated; a Type-1 dimension could not show this.")

q("Quarterly cohort retention",
  "Of the customers who first bought in a given quarter, what share is still buying 1, 2 and 4 quarters later?", "Multiple CTEs, cohort indexing, conditional aggregation",
"""WITH tx AS (
  SELECT c.customer_id, d.year_no*4 + d.quarter_no - 1 AS qn
  FROM fact_sales f
  JOIN dim_customer c ON c.customer_key = f.customer_key AND c.customer_id IS NOT NULL
  JOIN dim_date d     ON d.date_key     = f.date_key
  GROUP BY c.customer_id, d.year_no*4 + d.quarter_no - 1),
first_q AS (SELECT customer_id, MIN(qn) AS fq FROM tx GROUP BY customer_id),
act AS (
  SELECT fq.fq, tx.qn - fq.fq AS q_offset, COUNT(DISTINCT tx.customer_id) AS n
  FROM tx JOIN first_q fq ON fq.customer_id = tx.customer_id
  GROUP BY fq.fq, tx.qn - fq.fq)
SELECT CONCAT(FLOOR(fq/4), '-Q', fq%4 + 1) AS cohort,
       MAX(CASE WHEN q_offset = 0 THEN n END) AS cohort_size,
       ROUND(100*MAX(CASE WHEN q_offset = 1 THEN n END) / MAX(CASE WHEN q_offset = 0 THEN n END),1) AS retained_q1_pct,
       ROUND(100*MAX(CASE WHEN q_offset = 2 THEN n END) / MAX(CASE WHEN q_offset = 0 THEN n END),1) AS retained_q2_pct,
       ROUND(100*MAX(CASE WHEN q_offset = 4 THEN n END) / MAX(CASE WHEN q_offset = 0 THEN n END),1) AS retained_q4_pct
FROM act GROUP BY fq ORDER BY fq LIMIT 12;""", "First 12 cohorts shown. The 2022-Q1 cohort contains all customers already active at the start of the data.")

q("Channel comparison: order value, basket size and discount intensity",
  "How do online orders differ from in-store baskets?", "Two-level aggregation (line -> order -> channel)",
"""WITH o AS (
  SELECT f.channel_key, f.source_order_no, COUNT(*) AS line_cnt, SUM(f.quantity) AS units,
         SUM(f.net_amount) AS rev, SUM(f.discount_amount) AS disc, SUM(f.gross_amount) AS gross
  FROM fact_sales f GROUP BY f.channel_key, f.source_order_no)
SELECT c.channel_name, COUNT(*) AS orders, ROUND(AVG(rev)) AS avg_order_value, ROUND(MAX(rev)) AS largest_order,
       ROUND(AVG(line_cnt),2) AS lines_per_order, ROUND(AVG(units),2) AS units_per_order,
       ROUND(100*SUM(disc)/SUM(gross),2) AS discount_pct_of_gross
FROM o JOIN dim_channel c ON c.channel_key = o.channel_key
GROUP BY c.channel_name;""", "Online CSV orders contain exactly one product line each, which limits basket analysis for that channel.")

q("Market-basket analysis: product pairs bought together (support, confidence, lift)",
  "Which products should be placed together or cross-promoted?", "Self-join on order, pair counting, lift = P(A&B) / (P(A) x P(B))",
"""WITH items AS (
  SELECT DISTINCT f.source_order_no AS ord, p.product_id AS pid, p.product_name AS nm
  FROM fact_sales f JOIN dim_product p ON p.product_key = f.product_key
  WHERE f.channel_key = 1),
n   AS (SELECT COUNT(DISTINCT ord) AS total FROM items),
pc  AS (SELECT pid, COUNT(*) AS cnt FROM items GROUP BY pid),
pairs AS (
  SELECT a.pid AS pa, b.pid AS pb, a.nm AS na, b.nm AS nb, COUNT(*) AS together
  FROM items a JOIN items b ON a.ord = b.ord AND a.pid < b.pid
  GROUP BY a.pid, b.pid, a.nm, b.nm)
SELECT na AS product_a, nb AS product_b, together AS orders_together,
       ROUND(100*together/total,2) AS support_pct,
       ROUND(100*together/ca.cnt,1) AS confidence_a_to_b_pct,
       ROUND((together/total) / ((ca.cnt/total)*(cb.cnt/total)),2) AS lift
FROM pairs JOIN pc ca ON ca.pid = pairs.pa JOIN pc cb ON cb.pid = pairs.pb CROSS JOIN n
WHERE together >= 30
ORDER BY lift DESC
LIMIT 10;""", "Lift > 1 means the pair is bought together more often than chance.")

q("Discount depth versus volume and margin",
  "Do deeper discounts actually lift units per line, and what do they cost in margin?", "Derived table, banding, margin ratios",
"""SELECT CONCAT(discount_depth, '%') AS discount_depth, COUNT(*) AS line_cnt,
       ROUND(AVG(quantity),2) AS avg_units_per_line, ROUND(SUM(net_amount)) AS revenue,
       ROUND(100*SUM(gross_profit)/SUM(net_amount),1) AS margin_pct
FROM (SELECT f.*, ROUND(100*discount_amount/gross_amount) AS discount_depth
      FROM fact_sales f WHERE f.channel_key = 1) x
GROUP BY discount_depth
ORDER BY discount_depth;""", "Dummy demand is not price-elastic, so units per line stay flat while margin falls; run on real data to test the question.")

q("Promotion effectiveness: profit earned per rupee of discount given",
  "Which promotions paid for themselves?", "Join to promotion dimension, RANK(), ratio measures",
"""SELECT pr.promo_name, pr.target_type, pr.discount_percent AS disc_pct,
       COUNT(DISTINCT f.source_order_no) AS orders, SUM(f.quantity) AS units,
       ROUND(SUM(f.discount_amount)) AS discount_cost, ROUND(SUM(f.gross_profit)) AS profit_after_discount,
       ROUND(SUM(f.gross_profit)/SUM(f.discount_amount),2) AS profit_per_rs_discount,
       RANK() OVER (ORDER BY SUM(f.gross_profit)/SUM(f.discount_amount) DESC) AS roi_rank
FROM fact_sales f JOIN dim_promotion pr ON pr.promotion_key = f.promotion_key
WHERE f.promotion_key > 0
GROUP BY pr.promo_name, pr.target_type, pr.discount_percent
ORDER BY roi_rank
LIMIT 10;""", "Top 10 of the 16 promotions. Only discounted lines carry a promotion key.")

q("Price-change impact on demand (SCD Type 2 versions)",
  "When a product's price rose, how did daily unit demand change?", "SCD-2 effective dates, LAG() across versions, simple elasticity",
f"""WITH v AS (
  SELECT p.product_key, p.product_id, p.product_name, p.version_no, p.list_price,
         GREATEST(p.effective_from, '2022-01-01') AS from_d, LEAST(p.effective_to, {END}) AS to_d,
         SUM(f.quantity) AS units
  FROM dim_product p JOIN fact_sales f ON f.product_key = p.product_key AND f.channel_key = 1
  WHERE p.product_id IN (SELECT product_id FROM dim_product GROUP BY product_id HAVING COUNT(*) > 1)
  GROUP BY p.product_key, p.product_id, p.product_name, p.version_no, p.list_price, p.effective_from, p.effective_to),
d AS (SELECT *, units / (DATEDIFF(to_d, from_d) + 1) AS units_per_day FROM v)
SELECT product_name, version_no, list_price, from_d AS price_from, ROUND(units_per_day*30,1) AS units_per_30d,
       ROUND(100*(list_price / LAG(list_price) OVER w - 1),1) AS price_change_pct,
       ROUND(100*(units_per_day / LAG(units_per_day) OVER w - 1),1) AS demand_change_pct
FROM d
WINDOW w AS (PARTITION BY product_id ORDER BY version_no)
ORDER BY product_name, version_no
LIMIT 14;""", "First 14 rows shown. version_no 1 has no predecessor (NULL change). Demand also grows with the business, so this is a template for elasticity analysis, not proof of it.")

q("Return rate and refund cost by category",
  "Which categories generate the most returns?", "Aggregate ratios, RANK() on a ratio",
"""SELECT p.parent_category, p.category_name, SUM(f.quantity) AS units_sold, SUM(f.returned_qty) AS units_returned,
       ROUND(100*SUM(f.returned_qty)/SUM(f.quantity),2) AS return_rate_pct,
       ROUND(SUM(f.refund_amount)) AS refund_value,
       ROUND(100*SUM(f.refund_amount)/SUM(f.net_amount),2) AS refund_pct_of_revenue,
       RANK() OVER (ORDER BY SUM(f.returned_qty)/SUM(f.quantity) DESC) AS return_rank
FROM fact_sales f JOIN dim_product p ON p.product_key = f.product_key
WHERE f.channel_key = 1
GROUP BY p.parent_category, p.category_name
ORDER BY return_rank;""", "Returns are only recorded for in-store sales in the source system.")

q("Branches below the chain-average margin, by quarter",
  "Which branches consistently earn a lower margin than the chain?", "Window aggregate over partition, flag counting",
"""WITH q AS (
  SELECT d.year_no, d.quarter_no, b.branch_name, SUM(f.net_amount) AS rev, SUM(f.gross_profit) AS gp
  FROM fact_sales f
  JOIN dim_date d    ON d.date_key    = f.date_key
  JOIN dim_branch b  ON b.branch_key  = f.branch_key
  WHERE f.channel_key = 1
  GROUP BY d.year_no, d.quarter_no, b.branch_name),
m AS (
  SELECT *, 100*gp/rev AS margin,
         100*SUM(gp) OVER (PARTITION BY year_no, quarter_no) / SUM(rev) OVER (PARTITION BY year_no, quarter_no) AS chain_margin
  FROM q)
SELECT branch_name, COUNT(*) AS quarters_traded,
       SUM(margin < chain_margin) AS quarters_below_chain,
       ROUND(100*SUM(margin < chain_margin)/COUNT(*)) AS pct_quarters_below,
       ROUND(AVG(margin - chain_margin),2) AS avg_gap_pts
FROM m
GROUP BY branch_name
ORDER BY avg_gap_pts;""", "Negative avg_gap_pts = margin lower than the chain in the same quarter.")

q("Day-of-week revenue index by channel",
  "Which days of the week are strongest for each channel?", "CROSS JOIN calendar x channel (to keep zero days), index vs average",
f"""WITH daily AS (
  SELECT d.day_of_week, d.day_name, c.channel_name, d.full_date, COALESCE(SUM(f.net_amount),0) AS rev
  FROM dim_date d CROSS JOIN dim_channel c
  LEFT JOIN fact_sales f ON f.date_key = d.date_key AND f.channel_key = c.channel_key
  WHERE d.full_date BETWEEN '2022-01-01' AND {END}
  GROUP BY d.day_of_week, d.day_name, c.channel_name, d.full_date),
avg_dow AS (SELECT channel_name, day_of_week, day_name, AVG(rev) AS avg_rev FROM daily GROUP BY channel_name, day_of_week, day_name)
SELECT channel_name, day_name, ROUND(avg_rev) AS avg_daily_revenue,
       ROUND(100*avg_rev / AVG(avg_rev) OVER (PARTITION BY channel_name)) AS index_vs_weekly_avg
FROM avg_dow
ORDER BY channel_name, day_of_week;""", "100 = average day for that channel.")

q("Supplier scorecard",
  "Which suppliers deliver on time and with the fewest damaged or short shipments?", "Fact #2 aggregation, composite score, RANK()",
"""SELECT s.supplier_name, COUNT(DISTINCT f.po_number) AS purchase_orders, ROUND(SUM(f.ordered_amount)) AS spend,
       ROUND(100*SUM(f.on_time_flag)/COUNT(*),1) AS on_time_pct, ROUND(AVG(f.lead_time_days),1) AS avg_lead_days,
       ROUND(100*SUM(f.damaged_qty)/SUM(f.ordered_qty),2) AS damaged_pct,
       ROUND(100*SUM(f.shortage_qty)/SUM(f.ordered_qty),2) AS shortage_pct,
       RANK() OVER (ORDER BY 100*SUM(f.on_time_flag)/COUNT(*) - 2*(100*SUM(f.damaged_qty + f.shortage_qty)/SUM(f.ordered_qty)) DESC) AS score_rank
FROM fact_procurement f JOIN dim_supplier s ON s.supplier_key = f.supplier_key
GROUP BY s.supplier_name
ORDER BY score_rank;""", "Score = on-time % minus 2 x (damaged % + shortage %) - weights are illustrative.")

q("Procurement loss root-cause by supplier",
  "Where is money lost in goods receiving, and which supplier causes it?", "Conditional-aggregation pivot, % of total with window over an aggregate",
"""SELECT f.discrepancy_reason,
       ROUND(SUM(CASE WHEN s.supplier_code='SUP01' THEN f.lost_amount END)) AS sup01_ceylon_harvest,
       ROUND(SUM(CASE WHEN s.supplier_code='SUP02' THEN f.lost_amount END)) AS sup02_lanka_dairy,
       ROUND(SUM(CASE WHEN s.supplier_code='SUP03' THEN f.lost_amount END)) AS sup03_island_bev,
       ROUND(SUM(CASE WHEN s.supplier_code='SUP04' THEN f.lost_amount END)) AS sup04_green_valley,
       ROUND(SUM(CASE WHEN s.supplier_code='SUP05' THEN f.lost_amount END)) AS sup05_homecare,
       ROUND(SUM(f.lost_amount)) AS total_loss,
       ROUND(100*SUM(f.lost_amount)/SUM(SUM(f.lost_amount)) OVER (),1) AS pct_of_all_losses
FROM fact_procurement f JOIN dim_supplier s ON s.supplier_key = f.supplier_key
WHERE f.discrepancy_reason <> 'NONE'
GROUP BY f.discrepancy_reason
ORDER BY total_loss DESC;""")

q("Drill-across: units bought versus units sold by category (2025)",
  "Are we over- or under-buying relative to what customers purchase?", "Drill-across of the two fact tables on conformed dimensions (date, product)",
"""WITH s AS (
  SELECT d.year_no, p.parent_category, SUM(f.quantity) AS units_sold, SUM(f.cost_amount) AS cogs
  FROM fact_sales f
  JOIN dim_date d    ON d.date_key    = f.date_key
  JOIN dim_product p ON p.product_key = f.product_key
  GROUP BY d.year_no, p.parent_category),
b AS (
  SELECT d.year_no, p.parent_category, SUM(f.received_qty) AS units_received, SUM(f.received_amount) AS purchase_cost
  FROM fact_procurement f
  JOIN dim_date d    ON d.date_key    = f.received_date_key
  JOIN dim_product p ON p.product_key = f.product_key
  GROUP BY d.year_no, p.parent_category)
SELECT s.parent_category, b.units_received, s.units_sold,
       ROUND(100*s.units_sold/b.units_received,1) AS sell_through_pct,
       ROUND(b.purchase_cost) AS purchase_cost, ROUND(s.cogs) AS cost_of_goods_sold,
       ROUND(b.purchase_cost/s.cogs,2) AS buy_to_cogs_ratio
FROM s JOIN b ON b.year_no = s.year_no AND b.parent_category = s.parent_category
WHERE s.year_no = 2025
ORDER BY sell_through_pct;""", "Each fact is aggregated separately to the shared grain, then joined - never join the two facts directly.")

q("Cost inflation versus selling-price change (2025 vs 2024) - margin squeeze detector",
  "Where did supplier cost rise faster than our shelf price?", "Drill-across, pivot of two years, CASE flag",
"""WITH c AS (
  SELECT p.product_id, p.product_name,
         AVG(CASE WHEN d.year_no = 2024 THEN f.unit_cost END) AS c24,
         AVG(CASE WHEN d.year_no = 2025 THEN f.unit_cost END) AS c25
  FROM fact_procurement f
  JOIN dim_product p ON p.product_key = f.product_key
  JOIN dim_date d    ON d.date_key    = f.order_date_key
  WHERE d.year_no IN (2024, 2025) GROUP BY p.product_id, p.product_name),
s AS (
  SELECT p.product_id,
         SUM(CASE WHEN d.year_no = 2024 THEN f.gross_amount END) / SUM(CASE WHEN d.year_no = 2024 THEN f.quantity END) AS s24,
         SUM(CASE WHEN d.year_no = 2025 THEN f.gross_amount END) / SUM(CASE WHEN d.year_no = 2025 THEN f.quantity END) AS s25
  FROM fact_sales f
  JOIN dim_product p ON p.product_key = f.product_key
  JOIN dim_date d    ON d.date_key    = f.date_key
  WHERE f.channel_key = 1 AND d.year_no IN (2024, 2025) GROUP BY p.product_id)
SELECT c.product_name, ROUND(c24,2) AS cost_2024, ROUND(c25,2) AS cost_2025, ROUND(100*(c25/c24-1),1) AS cost_change_pct,
       ROUND(s24,2) AS price_2024, ROUND(s25,2) AS price_2025, ROUND(100*(s25/s24-1),1) AS price_change_pct,
       ROUND(100*(s25/s24-1) - 100*(c25/c24-1),1) AS price_minus_cost_pts,
       CASE WHEN s25/s24 < c25/c24 THEN 'MARGIN SQUEEZE' ELSE 'ok' END AS flag
FROM c JOIN s ON s.product_id = c.product_id
ORDER BY price_minus_cost_pts
LIMIT 10;""", "10 worst products shown (most negative price-minus-cost gap).")

q("Customer lifetime value, share of revenue and purchase rhythm",
  "Who are the top 10 customers and how often do they come back?", "LAG() on order dates, nested aggregation, share-of-total window",
f"""WITH o AS (
  SELECT c.customer_id, c.card_no, f.source_order_no, MIN(d.full_date) AS order_date, SUM(f.net_amount) AS rev
  FROM fact_sales f
  JOIN dim_customer c ON c.customer_key = f.customer_key AND c.customer_id IS NOT NULL
  JOIN dim_date d     ON d.date_key     = f.date_key
  GROUP BY c.customer_id, c.card_no, f.source_order_no),
g AS (
  SELECT *, DATEDIFF(order_date, LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date)) AS gap_days FROM o)
SELECT card_no, COUNT(*) AS orders, ROUND(SUM(rev)) AS lifetime_value,
       ROUND(100*SUM(rev)/SUM(SUM(rev)) OVER (),2) AS share_of_loyalty_revenue_pct,
       MIN(order_date) AS first_order, MAX(order_date) AS last_order, ROUND(AVG(gap_days)) AS avg_days_between_orders
FROM g
GROUP BY customer_id, card_no
ORDER BY lifetime_value DESC
LIMIT 10;""")

q("Unusual trading days: z-score anomaly detection",
  "Which days were statistically unusual, and were they holidays?", "AVG/STDDEV_SAMP window per year, z-score filter",
f"""WITH daily AS (
  SELECT d.full_date, d.year_no, d.day_name, d.holiday_name, COALESCE(SUM(f.net_amount),0) AS rev
  FROM dim_date d LEFT JOIN fact_sales f ON f.date_key = d.date_key
  WHERE d.full_date BETWEEN '2022-01-01' AND {END}
  GROUP BY d.full_date, d.year_no, d.day_name, d.holiday_name),
z AS (
  SELECT *, (rev - AVG(rev) OVER (PARTITION BY year_no)) / STDDEV_SAMP(rev) OVER (PARTITION BY year_no) AS zscore FROM daily)
SELECT full_date, day_name, COALESCE(holiday_name,'-') AS holiday, ROUND(rev) AS revenue, ROUND(zscore,2) AS z_score,
       CASE WHEN zscore > 0 THEN 'spike' ELSE 'dip' END AS direction
FROM z
WHERE ABS(zscore) >= 2.5
ORDER BY ABS(zscore) DESC
LIMIT 12;""", "|z| >= 2.5 within each calendar year.")
