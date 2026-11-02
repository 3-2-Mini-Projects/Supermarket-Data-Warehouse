"""
make_query_excel.py
Reads ../out/query_results.json (written by run_queries.py) and writes
../out/query_results.xlsx : one sheet per query (Q01..Q25), each holding an
Excel table named tbl_Q01..tbl_Q25. Power BI can then load all 25 at once
(Get data > Excel workbook > tick the tbl_ tables).

Needs openpyxl:   pip install openpyxl
Usage (python folder, after run_queries.py):   python make_query_excel.py
"""
import json, os
from openpyxl import Workbook
from openpyxl.worksheet.table import Table, TableStyleInfo

here = os.path.dirname(os.path.abspath(__file__))
out_dir = os.path.join(here, "..", "out")
with open(os.path.join(out_dir, "query_results.json"), encoding="utf-8") as fh:
    data = json.load(fh)

wb = Workbook()
wb.remove(wb.active)

for q in data:
    name = f"Q{int(q['n']):02d}"
    ws = wb.create_sheet(name)
    cols = q.get("cols") or []
    if not cols:                       # failed query: keep a visible placeholder
        cols = ["error"]
        rows = [[q.get("error", "no data")]]
    else:
        rows = q.get("rows", [])

    # Excel table headers must be unique, non-empty text
    seen, headers = {}, []
    for c in cols:
        c = str(c) if str(c).strip() else "column"
        seen[c] = seen.get(c, 0) + 1
        headers.append(c if seen[c] == 1 else f"{c}_{seen[c]}")

    ws.append(headers)
    for r in rows:
        ws.append(r)

    last_col = ws.cell(row=1, column=len(headers)).column_letter
    last_row = max(len(rows), 1) + 1
    tab = Table(displayName=f"tbl_{name}", ref=f"A1:{last_col}{last_row}")
    tab.tableStyleInfo = TableStyleInfo(name="TableStyleMedium2", showRowStripes=True)
    ws.add_table(tab)
    for i, h in enumerate(headers, start=1):
        ws.column_dimensions[ws.cell(row=1, column=i).column_letter].width = max(12, min(40, len(h) + 4))

dst = os.path.join(out_dir, "query_results.xlsx")
wb.save(dst)
print("Saved", os.path.abspath(dst), "-", len(data), "sheets")
