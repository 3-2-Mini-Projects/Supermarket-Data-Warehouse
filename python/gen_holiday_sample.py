"""Offline Calendarific-shaped holiday sample for Sri Lanka (sandbox/testing only).
Fixed-date holidays + Good Friday (Easter algorithm) + approximate Poya (full-moon) days.
Replace with live API output (extract_holidays.py) for real data."""
import json, math, datetime as dt, os
def full_moon_jde(k):
    k+=0.5; T=k/1236.85
    jde=2451550.09766+29.530588861*k+0.00015437*T*T
    M=math.radians((2.5534+29.10535670*k)%360); Mp=math.radians((201.5643+385.81693528*k)%360); F=math.radians((160.7108+390.67050284*k)%360)
    E=1-0.002516*T
    jde+=(-0.40614*math.sin(Mp)+0.17302*E*math.sin(M)+0.01614*math.sin(2*Mp)+0.01043*math.sin(2*F)
          +0.00734*math.sin(Mp-M)*E-0.00515*math.sin(Mp+M)*E+0.00209*math.sin(2*M)*E*E)
    return jde
def jd_to_dt(jd):
    return dt.datetime(2000,1,1,12)+dt.timedelta(days=jd-2451545.0)
def easter(y):
    a=y%19;b=y//100;c=y%100;d=b//4;e=b%4;f=(b+8)//25;g=(b-f+1)//3;h=(19*a+b-d-g+15)%30
    i=c//4;k=c%4;l=(32+2*e+2*i-h-k)%7;m=(a+11*h+22*l)//451
    mo=(h+l-7*m+114)//31;da=((h+l-7*m+114)%31)+1
    return dt.date(y,mo,da)
def poyas(y):
    out=[]
    for k in range(int((y-2000)*12.3685)-2,int((y-2000)*12.3685)+16):
        t=jd_to_dt(full_moon_jde(k))+dt.timedelta(hours=5,minutes=30)   # Sri Lanka time
        d=t.date() if t.hour>=16 else t.date()-dt.timedelta(days=1)   # empirical Poya-day rule (calibrated on 2025 published dates)
        if d.year==y: out.append(d)
    return out
names={1:'Duruthu',2:'Navam',3:'Medin',4:'Bak',5:'Vesak',6:'Poson',7:'Esala',8:'Nikini',9:'Binara',10:'Vap',11:'Il',12:'Unduvap'}
hol=[]
def add(d,n,t='National holiday'): hol.append({"name":n,"description":n,"country":{"id":"lk","name":"Sri Lanka"},"date":{"iso":d.isoformat()},"type":[t]})
for y in range(2022,2028):
    for d in poyas(y): add(d,f"{names[d.month]} Full Moon Poya Day")
    add(dt.date(y,1,14),"Tamil Thai Pongal Day"); add(dt.date(y,2,4),"National Day")
    add(dt.date(y,4,13),"Sinhala and Tamil New Year's Eve"); add(dt.date(y,4,14),"Sinhala and Tamil New Year's Day")
    add(dt.date(y,5,1),"May Day"); add(easter(y)-dt.timedelta(days=2),"Good Friday"); add(dt.date(y,12,25),"Christmas Day")
    add(dt.date(y,2,14),"Valentine's Day","Observance")
data_dir = os.path.join(os.path.dirname(__file__), "..", "data")
json.dump({"meta":{"code":200,"note":"OFFLINE SAMPLE - approximate; replace with live Calendarific output"},"response":{"holidays":sorted(hol,key=lambda h:h['date']['iso'])}},open(os.path.join(data_dir, "holidays_lk_offline_sample.json"),'w'),indent=1)
exp=['2025-01-13','2025-02-12','2025-03-13','2025-04-12','2025-05-12','2025-06-10','2025-07-10','2025-08-08','2025-09-07','2025-10-06','2025-11-05']
got=[d.isoformat() for d in poyas(2025)]
print("2025 poya match:",[e in got for e in exp].count(True),"/",len(exp), got)
print(len(hol),"holiday rows")
