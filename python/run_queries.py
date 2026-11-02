import os, json, decimal, datetime, pymysql, sys
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))
sys.path.insert(0, os.path.dirname(__file__)); from queries import Q
cn = pymysql.connect(host=os.getenv("DB_HOST", "localhost"), user=os.getenv("DB_USER", "dw_user"), password=os.getenv("DB_PASS"), database="supermarket_dw"); cur = cn.cursor()
out = []
for qq in Q:
    try:
        cur.execute(qq["sql"]); cols = [c[0] for c in cur.description]; rows = cur.fetchall()
        def f(v):
            if isinstance(v, decimal.Decimal): return float(v)
            if isinstance(v, (datetime.date, datetime.datetime)): return str(v)
            return v
        qq["cols"] = cols; qq["rows"] = [[f(v) for v in r] for r in rows]; print(f"Q{qq['n']:02d} OK  {len(rows):3d} rows  {qq['title'][:60]}")
    except Exception as e:
        qq["cols"] = []; qq["rows"] = []; qq["error"] = str(e); print(f"Q{qq['n']:02d} ERROR {e}")
    out.append(qq)
out_dir = os.path.join(os.path.dirname(__file__), "..", "out")
os.makedirs(out_dir, exist_ok=True)
json.dump(out, open(os.path.join(out_dir, "query_results.json"), "w"), indent=1, default=str)

import csv
csv_dir = os.path.join(out_dir, "query_csv")
os.makedirs(csv_dir, exist_ok=True)
for qq in out:
    with open(os.path.join(csv_dir, f"Q{qq['n']:02d}.csv"), "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.writer(fh)
        w.writerow(qq["cols"])
        w.writerows(qq["rows"])
print("CSV files saved to", os.path.abspath(csv_dir))
