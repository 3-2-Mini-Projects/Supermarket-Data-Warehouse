"""Source 3 - Holiday API -> stg_holiday_api.
LIVE mode  : Calendarific  https://calendarific.com/api/v2/holidays?api_key=KEY&country=LK&year=YYYY   (set CALENDARIFIC_KEY)
OFFLINE    : --offline reads data/holidays_lk_offline_sample.json (same JSON shape) - used when there is no internet / key."""
import os, sys, json, requests, pymysql
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))
YEARS = range(2022, 2028)
def fetch_live(key):
    out = []
    for y in YEARS:
        r = requests.get("https://calendarific.com/api/v2/holidays", params={"api_key": key, "country": "LK", "year": y}, timeout=30)
        r.raise_for_status()
        out += r.json()["response"]["holidays"]
    return out
def classify(name, types):
    n = name.lower()
    if "poya" in n: return "POYA"
    if any(k in n for k in ("public sector", "special bank", "government offices", "bad weather", "fuel conservation")): return "GOVERNMENT"
    if any(t in ("National holiday", "Local holiday", "Religious") for t in types): return "PUBLIC"
    return "OBSERVANCE"                      # Valentine's Day, equinox, etc. -> not treated as a holiday in the warehouse
def main():
    if "--offline" in sys.argv or not os.getenv("CALENDARIFIC_KEY"):
        hol = json.load(open(os.path.join(os.path.dirname(__file__), "..", "data", "holidays_lk_offline_sample.json")))["response"]["holidays"]
        print("Holiday source: OFFLINE sample file")
    else:
        hol = fetch_live(os.environ["CALENDARIFIC_KEY"]); print("Holiday source: LIVE Calendarific API")
    rows = [(h["date"]["iso"][:10], h["name"][:150], ", ".join(h.get("type", []))[:100], "LK", classify(h["name"], h.get("type", []))) for h in hol]
    cn = pymysql.connect(host=os.getenv("DB_HOST", "localhost"), user=os.getenv("DB_USER", "dw_user"), password=os.getenv("DB_PASS"), database="supermarket_dw")
    cur = cn.cursor(); cur.execute("TRUNCATE stg_holiday_api")
    cur.executemany("INSERT INTO stg_holiday_api(holiday_date,holiday_name,holiday_types,country_code,holiday_class) VALUES(%s,%s,%s,%s,%s)", rows)
    cur.execute("INSERT INTO etl_run_log(step_name,rows_loaded,note) VALUES('stg_holiday_api',%s,%s)", (len(rows), "offline sample" if "--offline" in sys.argv or not os.getenv("CALENDARIFIC_KEY") else "live API"))
    cn.commit(); print(len(rows), "holiday rows staged")
if __name__ == "__main__": main()
