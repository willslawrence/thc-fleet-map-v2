#!/usr/bin/env python3
"""generate_sandbox.py - Regenerates THC Fleet Map from Obsidian vault."""
import os, re, glob
from datetime import datetime, timedelta

VAULT = "/thc-vault"
HELIS_DIR = f"{VAULT}/Helicopters"
PILOTS_DIR = f"{VAULT}/Pilots"
FLIGHTS_FILE = f"{VAULT}/Flights Schedule.md"
MISSIONS_DIR = f"{VAULT}/Missions"
HTML_FILE = "/willy/FleetMapAndTimeline/index.html"
TODAY = datetime.now()

def parse_frontmatter(filepath):
    data = {}
    try:
        with open(filepath, 'r') as f:
            txt = f.read()
        if txt.startswith('---'):
            parts = txt.split('---', 2)
            if len(parts) >= 3:
                key = None
                lst = []
                for ln in parts[1].strip().split('\n'):
                    if ln.strip().startswith('- '):
                        if key: lst.append(ln.strip()[2:].strip())
                    elif ':' in ln:
                        if key and lst:
                            data[key] = lst[0] if len(lst)==1 else ', '.join(lst)
                            lst = []
                        k, v = ln.split(':', 1)
                        key = k.strip()
                        v = v.strip().strip('"').strip("'")
                        if v: data[key] = v; key = None
                if key and lst:
                    data[key] = lst[0] if len(lst)==1 else ', '.join(lst)
    except: pass
    return data

def load_helicopters():
    helis = []
    for f in sorted(glob.glob(f"{HELIS_DIR}/HZHC*.md")):
        d = parse_frontmatter(f)
        st = d.get('status', 'parked').lower()
        if 'serviceable' in st: st = 'parked'
        elif 'maint' in st or 'aog' in st: st = 'maint'
        else: st = 'parked'
        helis.append({'reg': d.get('registration', os.path.basename(f).replace('.md','')), 'loc': d.get('location','UNK'), 'status': st, 'mission': d.get('current_mission',''), 'note': d.get('note','')})
    print(f"✅ Loaded {len(helis)} helicopters")
    return helis

def load_flights():
    flights, flying = [], {}
    try:
        txt = open(FLIGHTS_FILE).read()
        today_str = TODAY.strftime("%Y-%m-%d")
        for ln in txt.split('\n'):
            if ln.startswith(today_str) and '|' in ln:
                p = [x.strip() for x in ln.split('|')]
                if len(p) >= 4:
                    reg = 'HZHC' + p[1].replace('HC','') if not p[1].startswith('HZ') else p[1]
                    flights.append({'reg': reg, 'mission': p[2], 'pilot': p[3]})
                    flying[reg] = p[3]
    except: pass
    print(f"✅ Loaded {len(flights)} flights for today")
    return flights, flying

def load_currency():
    curr = []
    for pd in glob.glob(f"{PILOTS_DIR}/*/"):
        nm = os.path.basename(pd.rstrip('/'))
        pf = os.path.join(pd, f"{nm}.md")
        if os.path.exists(pf):
            try:
                txt = open(pf).read()
                med = rems = base = ""
                for ln in txt.split('\n'):
                    if 'Medical Certificate Date:' in ln: med = ln.split(':',1)[1].strip()
                    if '30 Mins REMS:' in ln: rems = ln.split(':',1)[1].strip()
                    if 'Base Month:' in ln: base = ln.split(':',1)[1].strip()
                if med or rems or base:
                    curr.append({'name': nm, 'medical': med, 'rems': rems, 'base_month': base})
            except: pass
    print(f"✅ Loaded {len(curr)} pilot currency records")
    return curr

def load_missions():
    missions = []
    for pat in [f"{MISSIONS_DIR}/*.md", f"{MISSIONS_DIR}/Past Missions/*.md"]:
        for f in glob.glob(pat):
            d = parse_frontmatter(f)
            t = d.get('title', os.path.basename(f).replace('.md',''))
            missions.append({'title': t, 'date': d.get('date',''), 'endDate': d.get('endDate', d.get('date','')), 'status': d.get('status','pending'), 'helicopters': d.get('Helicopter',''), 'pilots': d.get('Pilots','')})
    missions.sort(key=lambda x: x['date'] if x['date'] else 'zzzz')
    print(f"✅ Loaded {len(missions)} missions")
    return missions

def build_fleet_js(helis, flying):
    lines = ["const fleet = ["]
    cnt = {'parked':0, 'flying':0, 'maint':0}
    for h in helis:
        st = 'flying' if h['reg'] in flying else h['status']
        cnt[st] = cnt.get(st,0) + 1
        e = f'  {{ reg: "{h["reg"]}", loc: "{h["loc"]}", status: "{st}"'
        if h['note']: e += f', note: "{h["note"]}"'
        if h['mission']: e += f', mission: "{h["mission"]}"'
        if h['reg'] in flying: e += f', pilot: "{flying[h["reg"]]}"'
        lines.append(e + ' },')
    lines.append("];")
    print(f"✅ Fleet: {cnt['parked']} serviceable, {cnt['flying']} flying, {cnt['maint']} maintenance")
    return '\n'.join(lines)

def build_flights_html():
    lines = []
    try:
        txt = open(FLIGHTS_FILE).read()
        today_str = TODAY.strftime("%Y-%m-%d")
        for ln in txt.split('\n'):
            if ln.startswith('## '): lines.append(f'  <h4>{ln[3:].strip()}</h4>')
            elif '|' in ln and 'HC' in ln and not ln.startswith('#'):
                p = [x.strip() for x in ln.split('|')]
                if len(p) >= 4:
                    reg = p[1].replace('HZHC','HC') if 'HZ' in p[1] else p[1]
                    cls = "flight-row today" if p[0]==today_str else "flight-row"
                    lines.append(f'  <div class="{cls}"><span class="reg">{reg}</span><span class="info">{p[2]}</span><span class="pilot">{p[3]}</span></div>')
    except: pass
    return '\n'.join(lines) if lines else '  <div>No flights</div>'

def build_currency_html(curr):
    L = []
    this_mo = TODAY.strftime("%B")
    next_mo = (TODAY.replace(day=1) + timedelta(days=32)).strftime("%B")
    due_this = [c['name'] for c in curr if c.get('base_month')==this_mo]
    due_next = [c['name'] for c in curr if c.get('base_month')==next_mo]
    L.append('  <h4>Competency Checks</h4>')
    for n in due_this: L.append(f'  <div class="alert warn">⚠️ {this_mo} — {n}</div>')
    if due_next: L.append(f'  <div class="alert ok">✅ {next_mo} — {", ".join(due_next)}</div>')
    elif not due_this: L.append(f'  <div class="alert ok">✅ {next_mo} — nobody due</div>')
    
    rems = []
    for c in curr:
        r = c.get('rems','')
        if r:
            try:
                rd = datetime.strptime(r, "%Y-%m")
                mo = (TODAY.year-rd.year)*12 + (TODAY.month-rd.month)
                if mo > 6: rems.append((c['name'], rd.strftime("%B %Y"), 'danger'))
                elif mo >= 5: rems.append((c['name'], rd.strftime("%B %Y"), 'warn'))
            except: pass
    if rems:
        L.append('  <h4>30-Min REMS (6 month cycle)</h4>')
        for n,d,l in sorted(rems, key=lambda x: x[2]!='danger'):
            L.append(f'  <div class="alert {l}">{"🔴" if l=="danger" else "⚠️"} {n} — expired {d}</div>')
    
    meds = []
    for c in curr:
        m = c.get('medical','')
        if m:
            try:
                md = datetime.strptime(m, "%Y-%m-%d")
                days = (md - TODAY).days
                if days < 0: meds.append((c['name'], md.strftime("%B"), 'danger'))
                elif days < 60: meds.append((c['name'], md.strftime("%B"), 'warn'))
            except: pass
    if meds:
        L.append('  <h4>Medical Certificate (12 month validity)</h4>')
        for n,d,l in sorted(meds, key=lambda x: x[2]!='danger'):
            L.append(f'  <div class="alert {l}">{"🔴" if l=="danger" else "⚠️"} {n} — {d}</div>')
    return '\n'.join(L)

def build_timeline_html(missions):
    tbd = [m for m in missions if not m['date']]
    dated = [m for m in missions if m['date']]
    if not dated: return "<!-- No missions -->"
    def pdt(d):
        try: return datetime.strptime(d, "%Y-%m-%d")
        except: return None
    for m in dated:
        m['s'] = pdt(m['date'])
        m['e'] = pdt(m['endDate']) or m['s']
    dated = [m for m in dated if m['s']]
    dated.sort(key=lambda x: x['s'])
    mn, mx = datetime(2025,10,1), datetime(2026,12,31)
    td = (mx-mn).days
    def pos(s,e):
        l = ((max(s,mn)-mn).days/td)*100
        w = max(((min(e,mx)-max(s,mn)).days/td)*100, 1.2)
        return round(l,1), round(w,1)
    def fdt(s,e):
        if s==e: return s.strftime("%-d %b")
        elif s.month==e.month: return f"{s.day}-{e.strftime('%-d %b')}"
        return f"{s.strftime('%-d %b')} - {e.strftime('%-d %b')}"
    def ovl(a,b):
        buf = timedelta(days=2)
        return not (a['e']+buf < b['s'] or b['e']+buf < a['s'])
    def pack(evs):
        lanes = []
        for ev in evs:
            placed = False
            for lane in lanes:
                if not any(ovl(ev,e) for e in lane): lane.append(ev); placed=True; break
            if not placed: lanes.append([ev])
        return lanes
    lanes = pack(dated)
    above, below = lanes[::2], lanes[1::2]
    L = ['    <div class="timeline-wrapper">']
    if tbd:
        L.append('    <div class="tbd-sidebar">')
        L.append('      <div class="tbd-header">📋 Dates TBD</div>')
        for m in tbd:
            t = m['title']
            L.append(f'      <div class="tbd-item" data-name="{t}" data-status="pending" data-dates="TBD" data-aircraft="TBD" data-pilots="TBD" onclick="showEventPopup(this,event)">')
            L.append(f'        {t}')
            L.append('      </div>')
        L.append('    </div>')
    def bar(m):
        l,w = pos(m['s'],m['e'])
        t,st,dt = m['title'], m['status'], fdt(m['s'],m['e'])
        sh = "short" if w<8 else ""
        dp = (t[:10]+"...") if len(t)>12 and sh else t
        h,p = m.get('helicopters') or 'TBD', m.get('pilots') or 'TBD'
        b = [f'          <div class="event-bar {st} {sh}" style="left:{l}%;width:{w}%;" data-name="{t}" data-status="{st}" data-dates="{dt}" data-aircraft="{h}" data-pilots="{p}" onclick="showEventPopup(this,event)" title="{t} ({dt})">']
        b.append(f'            <span class="event-title">{dp}</span>')
        if not sh: b.append(f'            <span class="event-dates">{dt}</span>')
        b.append('          </div>')
        return '\n'.join(b)
    L.append('    <div class="timeline-body">')
    L.append('      <div class="lanes-above">')
    for lane in above:
        L.append('        <div class="lane">')
        for m in sorted(lane, key=lambda x: x['s']): L.append(bar(m))
        L.append('        </div>')
    L.append('      </div>')
    L.append('      <div class="timeline-axis">')
    L.append('        <div class="axis-line"></div>')
    c = mn
    while c <= mx:
        l = round(((c-mn).days/td)*100,1)
        L.append(f'        <div class="month-marker" style="left:{l}%;">{c.strftime("%b %Y")}</div>')
        c = (c.replace(day=1)+timedelta(days=32)).replace(day=1)
    if mn <= TODAY <= mx:
        L.append(f'      <div class="today-marker" style="left:{round(((TODAY-mn).days/td)*100,1)}%;"><span>Today</span></div>')
    L.append('      </div>')
    L.append('      <div class="lanes-below">')
    for lane in below:
        L.append('        <div class="lane">')
        for m in sorted(lane, key=lambda x: x['s']): L.append(bar(m))
        L.append('        </div>')
    L.append('      </div>')
    L.append('    </div>')
    L.append('    </div>')
    return '\n'.join(L)

def update_html(html, fleet, flights, curr, timeline):
    html = re.sub(r'const fleet = \[.*?\];', fleet, html, flags=re.DOTALL)
    html = re.sub(r'<!-- FLIGHTS_START -->.*?<!-- FLIGHTS_END -->', f'<!-- FLIGHTS_START -->\n{flights}\n  <!-- FLIGHTS_END -->', html, flags=re.DOTALL)
    html = re.sub(r'<!-- CURRENCY_START -->.*?<!-- CURRENCY_END -->', f'<!-- CURRENCY_START -->\n{curr}\n  <!-- CURRENCY_END -->', html, flags=re.DOTALL)
    html = re.sub(r'<!-- TIMELINE_START -->.*?<!-- TIMELINE_END -->', f'<!-- TIMELINE_START -->\n{timeline}\n    <!-- TIMELINE_END -->', html, flags=re.DOTALL)
    html = re.sub(r'<title>THC Fleet Map.*?</title>', f'<title>THC Fleet Map — {TODAY.strftime("%-d %b %Y")}</title>', html)
    html = re.sub(r'<!-- LAST_UPDATED -->.*?<!-- /LAST_UPDATED -->', f'<!-- LAST_UPDATED -->{TODAY.strftime("%-d %b %Y %H:%M")}<!-- /LAST_UPDATED -->', html)
    return html

def main():
    print(f"\n🚁 THC Fleet Map Generator\n   {TODAY.strftime('%Y-%m-%d %H:%M:%S')}\n")
    helis = load_helicopters()
    flights, flying = load_flights()
    curr = load_currency()
    missions = load_missions()
    fjs = build_fleet_js(helis, flying)
    fhtml = build_flights_html()
    chtml = build_currency_html(curr)
    thtml = build_timeline_html(missions)
    html = open(HTML_FILE).read()
    html = update_html(html, fjs, fhtml, chtml, thtml)
    open(HTML_FILE, 'w').write(html)
    print(f"\n✅ Updated {HTML_FILE}")
    print(f"Done!")

if __name__ == "__main__": main()
