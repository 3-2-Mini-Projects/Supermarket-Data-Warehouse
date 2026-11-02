"""Source 2 - CSV online orders -> stg_online_orders (typed, validated, DQ-flagged)."""
import os, sys, pandas as pd, pymysql
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))
path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "data", "online_orders.csv")
df = pd.read_csv(path, dtype={"barcode": str, "card_no": str, "branch_code": str})
req = ["order_id","order_date","barcode","branch_code","quantity","unit_price","discount","card_no","delivery_status"]
assert list(df.columns) == req, f"unexpected columns {list(df.columns)}"
df["order_date"] = pd.to_datetime(df["order_date"]).dt.date
assert df.order_id.is_unique, "duplicate order_id"
assert df.isna().sum().sum() == 0, "NULLs in CSV"
assert (df.quantity > 0).all() and (df.unit_price > 0).all() and df.discount.between(0, 1).all()
cn = pymysql.connect(host=os.getenv("DB_HOST", "localhost"), user=os.getenv("DB_USER", "dw_user"), password=os.getenv("DB_PASS"), database="supermarket_dw")
cur = cn.cursor(); cur.execute("TRUNCATE stg_online_orders")
cur.executemany("INSERT INTO stg_online_orders(order_id,order_date,barcode,branch_code,quantity,unit_price,discount_rate,card_no,delivery_status) VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s)",
                df[req].values.tolist())
# data-quality flags (rows are kept, but flagged and reported)
cur.execute("UPDATE stg_online_orders SET dq_future_date = (order_date > (SELECT CAST(config_value AS DATE) FROM etl_config WHERE param='max_valid_order_date'))")
cur.execute("""UPDATE stg_online_orders o JOIN stg_product p ON p.barcode = o.barcode
               SET o.dq_price_outlier = (o.unit_price > 2*p.unit_price OR o.unit_price < 0.5*p.unit_price)""")
cur.execute("INSERT INTO etl_run_log(step_name,rows_loaded) SELECT 'stg_online_orders (CSV)', COUNT(*) FROM stg_online_orders")
cn.commit(); print(len(df), "CSV rows staged")
