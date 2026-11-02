"""Orchestrator:  python run_etl.py [--offline]  - runs the full ETL in dependency order."""
import os, subprocess, sys
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))
here = os.path.dirname(os.path.abspath(__file__)); sql = os.path.join(here, "..", "sql")
env = dict(os.environ, MYSQL_PWD=os.getenv("DB_PASS")); user = os.getenv("DB_USER", "dw_user")
def run_sql(f):
    print(">>", f); subprocess.run(f"mysql -u{user} --default-character-set=utf8mb4 < {os.path.join(sql, f)}", shell=True, check=True, env=env)
def run_py(f, *a):
    print(">>", f); subprocess.run([sys.executable, os.path.join(here, f), *a], check=True)
if "--skip-ddl" not in sys.argv: run_sql("02_dw_schema_mysql.sql")
run_sql("03_etl_staging.sql")                                  # Source 1 -> staging
run_py("load_online_orders.py")                                # Source 2 -> staging
run_py("extract_holidays.py", *(["--offline"] if "--offline" in sys.argv else []))   # Source 3 -> staging
run_sql("04_etl_dimensions.sql"); run_sql("05_etl_facts.sql")
print("ETL finished")
