@echo off
set DB_USER=dw_user
set DB_PASS=user@1234
set CALENDARIFIC_KEY=c646eupXfqvKnFJ9A90hjVftZBYtNBhs
cd /d C:\Users\Kumudu\OneDrive\Desktop\DataWarehouseProject
python python\run_etl.py --skip-ddl >> etl_log.txt 2>&1