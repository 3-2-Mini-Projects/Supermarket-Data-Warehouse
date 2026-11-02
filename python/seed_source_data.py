"""Seed the OLTP source (supermarket_oltp) with DUMMY data that follows the uploaded schema.
Deterministic (random.seed(42)). Keys are aligned with the online-orders CSV (barcodes, BR01-BR06, card numbers C000100-C000259)."""
import random, math, datetime as dt, pymysql, csv, os
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))
random.seed(42)
cn = pymysql.connect(host=os.getenv("DB_HOST", "localhost"), user=os.getenv("DB_USER", "dw_user"), password=os.getenv("DB_PASS"), database="supermarket_oltp", autocommit=False)
cur = cn.cursor()
D = dt.date; TODAY = D(2026,10,28)
data_dir = os.path.join(os.path.dirname(__file__), "..", "data")
def ins(sql, rows):
    cur.executemany(sql, rows)

# the dump carries AUTO_INCREMENT counters from the original DB; restart them so IDs begin at 1
cur.execute("SELECT table_name FROM information_schema.tables WHERE table_schema='supermarket_oltp'")
for (t,) in cur.fetchall(): cur.execute(f"ALTER TABLE `{t}` AUTO_INCREMENT=1")
# ---- suppliers
sup = [('SUP01','Ceylon Harvest Foods','Nimal Perera','0112345601','sales@ceylonharvest.example','Colombo 10'),
       ('SUP02','Lanka Dairy Co','Kamala Silva','0112345602','orders@lankadairy.example','Kurunegala'),
       ('SUP03','Island Beverages','Ruwan Fernando','0112345603','trade@islandbev.example','Ja-Ela'),
       ('SUP04','Green Valley Produce','Saman Kumara','0812345604','farm@greenvalley.example','Nuwara Eliya'),
       ('SUP05','HomeCare Distributors','Dilani Jayasinghe','0112345605','supply@homecare.example','Colombo 12')]
ins("INSERT INTO suppliers(supplier_code,name,contact_name,phone,email,address) VALUES(%s,%s,%s,%s,%s,%s)", sup)

# ---- categories (6 parents + 8 leaves)
ins("INSERT INTO categories(name,parent_id) VALUES(%s,%s)", [('Groceries',None),('Dairy & Eggs',None),('Beverages',None),('Fresh Produce',None),('Household',None),('Personal Care',None),
    ('Rice & Grains',1),('Spices & Oils',1),('Milk & Yogurt',2),('Soft Drinks & Water',3),('Tea & Coffee',3),('Fruits & Vegetables',4),('Cleaning',5),('Hair, Skin & Oral',6)])

# ---- employees / branches
cities = [('BR01','FreshMart Colombo Fort','Colombo','Western','2015-03-01'),('BR02','FreshMart Kotte','Sri Jayawardenepura Kotte','Western','2016-06-15'),
          ('BR03','FreshMart Nugegoda','Nugegoda','Western','2017-09-01'),('BR04','FreshMart Kandy','Kandy','Central','2018-11-20'),
          ('BR05','FreshMart Galle','Galle','Southern','2019-05-10'),('BR06','FreshMart Negombo','Negombo','Western','2020-02-01'),
          ('BR07','FreshMart Jaffna','Jaffna','Northern','2023-03-15'),('BR08','FreshMart Kurunegala','Kurunegala','North Western','2024-06-01')]
for i,(c,n,city,reg,od) in enumerate(cities,1):
    cur.execute("INSERT INTO branches(branch_code,name,city,region,address,phone,opened_date) VALUES(%s,%s,%s,%s,%s,%s,%s)",(c,n,city,reg,f'{city} Main Road','011-2'+str(100000+i*111),od))
fn = ['Nimal','Kamal','Sunil','Anura','Chaminda','Dilshan','Ruwan','Pradeep','Lakmal','Saman','Nadeesha','Kumari','Dilani','Sanduni','Thilini','Ishara','Madhavi','Priyanka','Shanika','Hasini','Tharindu','Kasun','Janaka','Asela','Isuru','Nuwan','Ayesha','Fathima','Mohamed','Rizwan','Arun','Kavitha','Suresh','Priya','Vijay','Nirmala','Gayan','Sachini','Malsha','Roshan']
ln = ['Perera','Silva','Fernando','Jayasinghe','Wickramasinghe','Bandara','Rajapaksha','Gunawardena','Herath','Dissanayake','Senanayake','Kumar','Rahman','Nadarajah','Weerasinghe','Amarasinghe','Karunaratne','Samarasinghe']
def nm(): return f"{random.choice(fn)} {random.choice(ln)}"
emp_id=0; mgr={}; cashiers={}
for b in range(1,9):
    for role,cnt in (('MANAGER',1),('CASHIER',3),('STOCK_CLERK',1)):
        for _ in range(cnt):
            emp_id+=1; sal={'MANAGER':145000,'CASHIER':65000,'STOCK_CLERK':60000}[role]+random.randint(0,9)*1000
            cur.execute("INSERT INTO employees(branch_id,full_name,role,email,phone,hire_date,monthly_salary) VALUES(%s,%s,%s,%s,%s,%s,%s)",
                        (b,nm(),role,f'emp{emp_id}@freshmart.example','077'+str(1000000+emp_id),D(2015,1,1)+dt.timedelta(days=random.randint(0,3000)),sal))
            if role=='MANAGER': mgr[b]=emp_id
            if role=='CASHIER': cashiers.setdefault(b,[]).append(emp_id)
cur.execute("INSERT INTO employees(branch_id,full_name,role,email,phone,hire_date,monthly_salary) VALUES(1,'Catalog Admin','CATALOG_MANAGER','catalog@freshmart.example','0771000000','2015-03-01',175000)")
CATALOG=cur.lastrowid
for b,m in mgr.items(): cur.execute("UPDATE branches SET manager_id=%s WHERE branch_id=%s",(m,b))

# ---- products (barcodes taken from the online-orders CSV)
barcodes = sorted({r['barcode'] for r in csv.DictReader(open(os.path.join(data_dir, "online_orders.csv")))})
assert len(barcodes)==30
P = [("Samba Rice 5kg",7,1,"Golden Paddy",0,1450),("Red Raw Rice 5kg",7,1,"Golden Paddy",0,1250),("Basmati Rice 1kg",7,1,"Royal Grain",0,690),
 ("Red Dhal 1kg",7,1,"Golden Paddy",0,340),("Wheat Flour 1kg",7,1,"Prima Mills",8,270),("Curry Powder 250g",8,1,"Spice Isle",8,480),
 ("Chilli Powder 250g",8,1,"Spice Isle",8,520),("Coconut Oil 1L",8,1,"Palm Gold",8,1050),("Fresh Milk 1L",9,2,"Lanka Dairy",0,450),
 ("Yoghurt 80g x6",9,2,"Lanka Dairy",8,520),("Eggs (10 pack)",9,2,"Farm Fresh",0,620),("Butter 200g",9,2,"Lanka Dairy",8,890),
 ("Cheese Slices 200g",9,2,"Creamy Co",8,1150),("Ginger Beer 1.5L",10,3,"Island Fizz",15,380),("Orange Cordial 750ml",10,3,"Island Fizz",15,620),
 ("Mineral Water 1.5L",10,3,"Pure Spring",0,130),("Black Tea 400g",11,3,"Hill Country",8,780),("Green Tea 25 bags",11,3,"Hill Country",8,640),
 ("Instant Coffee 100g",11,3,"Brew Co",8,1250),("Bananas 1kg",12,4,"Local Farm",0,320),("Mango 1kg",12,4,"Local Farm",0,650),
 ("Tomatoes 1kg",12,4,"Local Farm",0,420),("Carrots 1kg",12,4,"Local Farm",0,380),("Dish Wash Liquid 500ml",13,5,"CleanWave",15,390),
 ("Laundry Detergent 1kg",13,5,"CleanWave",15,780),("Floor Cleaner 1L",13,5,"CleanWave",15,560),("Shampoo 200ml",14,5,"SilkCare",15,890),
 ("Soap Bar 100g x3",14,5,"SilkCare",15,360),("Toothpaste 120g",14,5,"BrightSmile",15,450),("Hand Wash 250ml",14,5,"SilkCare",15,420)]
# price history: products 1,2,8,9,12,17,19,24,25,27 get one or two increases
hist_plan = {1:[(D(2023,3,10),1.10),(D(2025,1,20),1.08)],2:[(D(2023,3,10),1.12)],8:[(D(2022,9,5),1.15),(D(2024,5,1),1.10)],9:[(D(2024,2,1),1.09)],
             12:[(D(2023,8,15),1.07)],17:[(D(2022,11,1),1.12),(D(2025,6,1),1.06)],19:[(D(2024,10,1),1.10)],24:[(D(2023,1,15),1.08)],
             25:[(D(2024,4,1),1.09)],27:[(D(2025,3,1),1.07)]}
price_at = {}   # pid -> list of (from_date, price)
for pid,(name,cat,s,brand,tax,final) in enumerate(P,1):
    steps = hist_plan.get(pid,[])
    mult = 1.0
    for _,g in steps: mult*=g
    price0 = round(final/mult/5)*5
    cost = round(price0*random.uniform(0.70,0.78),2)
    cur.execute("INSERT INTO products(barcode,name,category_id,supplier_id,brand,unit_price,cost_price,tax_rate,reorder_level,created_at) VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,'2021-12-01 09:00:00')",
                (barcodes[pid-1],name,cat,s,brand,price0,cost,tax,random.choice([20,30,40,50])))
    lst=[(D(1900,1,1),price0)]; p=price0
    for d,g in steps:
        newp=round(p*g/5)*5 if pid not in (9,) else round(p*g/5)*5
        cur.execute("INSERT INTO product_price_history(product_id,old_price,new_price,changed_by,changed_at) VALUES(%s,%s,%s,%s,%s)",(pid,p,newp,CATALOG,dt.datetime.combine(d,dt.time(8,0))))
        lst.append((d,newp)); p=newp
    cur.execute("UPDATE products SET unit_price=%s WHERE product_id=%s",(p,pid))
    price_at[pid]=lst
def price_on(pid,d):
    pr=None
    for f,p in price_at[pid]:
        if f<=d: pr=p
    return pr
cur.execute("SELECT product_id,cost_price,tax_rate,category_id FROM products"); prod_info={r[0]:r[1:] for r in cur.fetchall()}
cur.execute("SELECT category_id,parent_id FROM categories"); parent={r[0]:r[1] for r in cur.fetchall()}

# ---- customers (card numbers aligned with CSV: C000100..C000259)
cities_c=['Colombo','Kotte','Nugegoda','Kandy','Galle','Negombo','Dehiwala','Maharagama','Jaffna','Kurunegala']
cust=[]
for i in range(160):
    jd = D(2021,1,1)+dt.timedelta(days=int(random.betavariate(1.3,1.0)*1900))
    cust.append(dict(id=i+1,card=f'C{100+i:06d}',join=jd,w=random.lognormvariate(0,0.9)))
    cur.execute("INSERT INTO customers(card_no,full_name,phone,email,city,join_date,tier,points_balance) VALUES(%s,%s,%s,%s,%s,%s,'BRONZE',0)",
                (f'C{100+i:06d}',nm(),'07'+str(60000000+i*137),f'cust{i+1}@mail.example',random.choice(cities_c),jd))
# tier history for ~50 customers
tier_order=['BRONZE','SILVER','GOLD','PLATINUM']; cust_hist={}
for c in random.sample(cust,55):
    t=0; d=c['join']; hist=[]
    for _ in range(random.randint(1,3)):
        d=d+dt.timedelta(days=random.randint(90,500))
        if d>D(2026,9,30) or t>=3: break
        hist.append((tier_order[t],tier_order[t+1],d)); t+=1
    if hist:
        cust_hist[c['id']]=hist
        for o,n,dd in hist:
            cur.execute("INSERT INTO customer_tier_history(customer_id,old_tier,new_tier,reason,changed_at) VALUES(%s,%s,%s,%s,%s)",(c['id'],o,n,'Annual spend threshold reached',dt.datetime.combine(dd,dt.time(2,0))))
        cur.execute("UPDATE customers SET tier=%s WHERE customer_id=%s",(hist[-1][1],c['id']))
def tier_on(cid,d):
    h=cust_hist.get(cid)
    if not h: return None
    t=h[0][0]
    for o,n,dd in h:
        if dd<=d: t=n
    return t

# ---- promotions
promos=[]  # (name,pct,start,end,product,category)
for y in range(2022,2027): promos.append((f'Avurudu Rice Festival {y}',10,D(y,4,1),D(y,4,17),None,7))
for y in range(2022,2026): promos.append((f'Christmas Storewide {y}',5,D(y,12,15),D(y,12,31),None,None))
promos+= [('Dairy Fresh Week 2023',8,D(2023,6,1),D(2023,6,14),None,9),('Poson Beverage Offer 2024',10,D(2024,6,1),D(2024,6,30),None,10),
          ('Cleaning Month 2024',12,D(2024,9,1),D(2024,9,30),None,13),('Tea Lovers 2025',15,D(2025,2,1),D(2025,2,28),17,None),
          ('Coconut Oil Deal 2023',10,D(2023,1,10),D(2023,2,10),8,None),('Household Saver 2025',10,D(2025,9,1),D(2025,9,30),None,5),
          ('Skin & Hair Glow 2026',12,D(2026,5,1),D(2026,5,31),None,6)]
for p in promos: cur.execute("INSERT INTO promotions(name,discount_percent,start_date,end_date,product_id,category_id) VALUES(%s,%s,%s,%s,%s,%s)",(p[0],p[1],p[2],p[3],p[4],p[5]))
def promo_for(d,pid):
    cat=prod_info[pid][2]
    for i,p in enumerate(promos,1):
        if p[2]<=d<=p[3]:
            if p[4]==pid or (p[4] is None and p[5] is None) or (p[4] is None and p[5] in (cat,parent[cat])): return i,p[1]
    return None

# ---- sales
branch_w=[22,16,15,13,12,10,7,5]; opened=[D.fromisoformat(c[4]) for c in cities]
pop=[random.lognormvariate(0,0.6) for _ in range(30)]
partner={9:11,17:19,24:25,27:28,1:4,22:23,6:7,14:15,12:13,29:30}
pay_methods=['CASH','CARD','MOBILE']
poya_days=set()
import json
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))
for h in json.load(open(os.path.join(data_dir, "holidays_lk_offline_sample.json")))['response']['holidays']:
    if 'Poya' in h['name']: poya_days.add(D.fromisoformat(h['date']['iso']))
sales_rows=[]; d=D(2022,1,1); sale_no=0; item_no=0
def poisson(l):
    L=math.exp(-l);k=0;p=1
    while True:
        p*=random.random()
        if p<=L: return k
        k+=1
while d<=TODAY:
    lam=3.3
    if d.month==12: lam*=1.45
    if d.month==4 and d.day>=5 and d.day<=14: lam*=1.55
    if d.month==1 and d.day<=3: lam*=0.8
    if d.weekday()>=5: lam*=1.35
    if d in poya_days: lam*=0.75
    lam*=1+0.03*(d.year-2022)    # growth
    for _ in range(poisson(lam)):
        bw=[w if opened[i]<=d else 0 for i,w in enumerate(branch_w)]
        b=random.choices(range(1,9),weights=bw)[0]
        cust_id=None
        if random.random()<0.55:
            el=[c for c in cust if c['join']<=d]
            if el: cust_id=random.choices(el,weights=[c['w'] for c in el])[0]['id']
        t=dt.time(random.randint(8,21),random.randint(0,59),random.randint(0,59))
        n_lines=min(7,1+int(random.expovariate(0.55)))
        pids=[]
        while len(pids)<n_lines:
            pid=random.choices(range(1,31),weights=pop)[0]
            if pid not in pids: pids.append(pid)
            if pid in partner and random.random()<0.35 and partner[pid] not in pids and len(pids)<7: pids.append(partner[pid])
        r=random.random(); status='COMPLETED' if r<0.955 else ('CANCELLED' if r<0.985 else 'OPEN')
        lines=[];promo_id=None;sub=disc=tax=0.0
        for pid in pids:
            up=price_on(pid,d); q=random.choices([1,2,3,4],weights=[50,28,14,8])[0]
            pr=promo_for(d,pid); dsc=0.0
            if pr and (promo_id is None or promo_id==pr[0]):
                promo_id=pr[0]; dsc=round(q*up*pr[1]/100,2)
            lt=round(q*up-dsc,2); lines.append((pid,q,up,dsc,lt))
            sub+=q*up; disc+=dsc; tax+=lt*float(prod_info[pid][1])/100
        sub=round(sub,2); disc=round(disc,2); tax=round(tax,2); total=round(sub-disc+tax,2)
        cash_id=random.choice(cashiers[b])
        cur.execute("INSERT INTO sales(branch_id,cashier_id,customer_id,promo_id,sale_date,status,subtotal,discount_total,tax_total,total_amount) VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
                    (b,cash_id,cust_id,promo_id,dt.datetime.combine(d,t),status,sub,disc,tax,total))
        sid=cur.lastrowid
        ins("INSERT INTO sale_items(sale_id,product_id,quantity,unit_price,discount_amount,line_total) VALUES(%s,%s,%s,%s,%s,%s)",[(sid,)+l for l in lines])
        if status=='COMPLETED':
            m=random.choices(pay_methods+['POINTS'],weights=[40,38,17,5 if cust_id else 0])[0]
            cur.execute("INSERT INTO payments(sale_id,method,amount,paid_at) VALUES(%s,%s,%s,%s)",(sid,m,total,dt.datetime.combine(d,t)))
            if cust_id:
                cur.execute("INSERT INTO loyalty_transactions(customer_id,branch_id,sale_id,points,type,created_at) VALUES(%s,%s,%s,%s,'EARN',%s)",(cust_id,b,sid,max(1,int(total//100)),dt.datetime.combine(d,t)))
    d+=dt.timedelta(days=1)
cur.execute("UPDATE customers c SET points_balance=(SELECT COALESCE(SUM(points),0) FROM loyalty_transactions l WHERE l.customer_id=c.customer_id)")

# ---- returns (~1.2% of completed lines)
cur.execute("""SELECT si.sale_item_id,si.quantity,si.unit_price,si.discount_amount,s.sale_date,s.branch_id FROM sale_items si JOIN sales s USING(sale_id) WHERE s.status='COMPLETED'""")
rows=cur.fetchall(); reasons=['Damaged packaging','Expired / near expiry','Wrong item','Customer changed mind','Quality complaint']
for r in random.sample(rows,int(len(rows)*0.012)):
    q=random.randint(1,r[1]); refund=round(q*float(r[2])-float(r[3])*q/r[1],2)
    rd=r[4]+dt.timedelta(days=random.randint(0,10))
    if rd.date()>TODAY: rd=dt.datetime.combine(TODAY,dt.time(12,0))
    cur.execute("INSERT INTO returns(sale_item_id,quantity,reason,refund_amount,processed_by,return_date) VALUES(%s,%s,%s,%s,%s,%s)",(r[0],q,random.choice(reasons),refund,mgr[r[5]],rd))

# ---- inventory
for b in range(1,9):
    for pid in range(1,31): cur.execute("INSERT INTO inventory(branch_id,product_id,quantity_on_hand,reserved_qty,reorder_level) VALUES(%s,%s,%s,%s,%s)",(b,pid,random.randint(5,320),random.randint(0,8),random.choice([20,30,40,60])))

# ---- purchase orders (procurement process -> fact #2)
cur.execute("SELECT product_id,supplier_id FROM products"); by_sup={}
for pid,s in cur.fetchall(): by_sup.setdefault(s,[]).append(pid)
reason_pool=['DAMAGED_IN_TRANSIT','PACKAGING_BROKEN','EXPIRED_ON_ARRIVAL','SUPPLIER_SHORTAGE','WRONG_PRODUCT','QUALITY_DEFECT']
sup_quality={1:(0.10,0.08,0.5),2:(0.18,0.10,0.9),3:(0.06,0.05,0.3),4:(0.30,0.20,1.4),5:(0.08,0.06,0.4)}  # P(issue),P(short),mean delay days
po_no=0
for b in range(1,9):
    d=max(D(2022,1,1),opened[b-1]+dt.timedelta(days=7))
    while d<TODAY-dt.timedelta(days=15):
        d+=dt.timedelta(days=random.randint(18,30))
        if d>=TODAY-dt.timedelta(days=15): break
        for s in random.sample(range(1,6),random.randint(1,3)):
            po_no+=1; exp=d+dt.timedelta(days=random.randint(3,7)); st=random.choices(['RECEIVED','CANCELLED','SENT'],weights=[93,4,3])[0]
            delay=max(-1,round(random.gauss(sup_quality[s][2],1.2))); rec=exp+dt.timedelta(days=delay) if st=='RECEIVED' else None
            items=random.sample(by_sup[s],random.randint(2,min(5,len(by_sup[s])))); total=0; its=[]
            for pid in items:
                q=random.choice([6,8,10,12,15,18]); uc=round(float(prod_info[pid][0])*(1+0.04*(d.year-2022))*random.uniform(0.97,1.03),2)
                rq=dmg=sh=None; rs='NONE'
                if st=='RECEIVED':
                    dmg=sh=0
                    if random.random()<sup_quality[s][0]: dmg=max(1,round(q*random.uniform(0.05,0.20))); rs=random.choice(['DAMAGED_IN_TRANSIT','PACKAGING_BROKEN','EXPIRED_ON_ARRIVAL','QUALITY_DEFECT','WRONG_PRODUCT'])
                    if random.random()<sup_quality[s][1]: sh=max(1,round(q*random.uniform(0.05,0.20))); rs='SUPPLIER_SHORTAGE' if dmg==0 else rs
                    rq=q-dmg-sh
                its.append((pid,q,rq,dmg,sh,rs,uc)); total+=q*uc
            cur.execute("INSERT INTO purchase_orders(po_number,supplier_id,branch_id,created_by,order_date,expected_date,status,total_cost,received_date) VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s)",
                        (f'PO-{d.year}-{po_no:04d}',s,b,mgr[b],d,exp,st,round(total,2),rec))
            poid=cur.lastrowid
            ins("INSERT INTO purchase_order_items(po_id,product_id,quantity,received_quantity,damaged_quantity,shortage_quantity,discrepancy_reason,unit_cost) VALUES(%s,%s,%s,%s,%s,%s,%s,%s)",[(poid,)+i for i in its])
cn.commit()
for t in ['suppliers','categories','branches','employees','products','product_price_history','customers','customer_tier_history','promotions','sales','sale_items','payments','loyalty_transactions','returns','inventory','purchase_orders','purchase_order_items']:
    cur.execute(f"select count(*) from {t}"); print(f"{t:24s}",cur.fetchone()[0])
