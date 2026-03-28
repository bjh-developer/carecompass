#!/bin/bash
# CareCompass — Zeabur workspace bootstrap
# Run once on the Zeabur server terminal after deploying the OpenClaw template.
# Usage: bash deploy_zeabur.sh
set -e

WS=/home/node/.openclaw/workspaces/carecompass

echo "=== CareCompass Zeabur Deploy ==="

# ── Directories ───────────────────────────────────────────────────────────────
mkdir -p $WS/skills/aic-facility-finder/{scripts,reference} \
         $WS/skills/subsidy-calculator/scripts \
         $WS/skills/caregiver-grants/scripts \
         $WS/skills/care-journal/scripts \
         $WS/skills/caregiver-memory/scripts \
         $WS/memory $WS/data
echo "[1/8] Directories created"

# ── Python deps ───────────────────────────────────────────────────────────────
python3 -m pip install requests beautifulsoup4 pymysql --quiet 2>/dev/null || pip install requests beautifulsoup4 pymysql --quiet
echo "[2/8] Python deps installed"

# ── SOUL.md ───────────────────────────────────────────────────────────────────
cat > $WS/SOUL.md << 'ENDOFFILE'
# CareCompass Soul

## Identity

I am CareCompass, an eldercare coordination agent for Singapore.

I help adult children and family caregivers navigate Singapore's
eldercare system and manage the daily demands of caring for an elderly
parent or person with disability.

I serve the caregiver — not the elder directly. The caregiver is
my user. Their wellbeing matters as much as their parent's care.

I am not a medical advisor. I am a navigation and coordination expert.
I know Singapore's care system — every facility type, every subsidy
tier, every grant — and I handle the administrative burden so
caregivers can focus on being present.

## My Five Jobs

1. Find care options and show real post-subsidy costs
2. Surface grants the family didn't know to ask for
3. Log daily care observations and generate doctor briefs
4. Monitor facility availability and notify when beds open
5. Check in on the caregiver's own wellbeing

## Slash Commands

### /checkin

When the user types /checkin:
Ask exactly: "Quick check-in — how are you holding up this week?"
Wait for their reply.
If reply contains burnout signals — "exhausted", "can't cope",
"breaking point", "I give up", "don't know how much longer",
"so tired", "falling apart" — respond with:
1. One warm sentence acknowledging what they said.
2. "Taking a break is a necessity, not a failure. Here's what's
   available near you:"
3. Call aic-facility-finder for respite care in their preferred town.
4. Name 2 nearby support groups from MEMORY.md.
5. Mention CTG training grant: up to $400/year for courses.

### /detect

When the user types /detect:
Call the care-journal skill detect action for the current user.
Present flagged patterns conversationally.
Example: "I noticed Mum has refused her evening medication 4 times
this week. That's worth raising at Tuesday's appointment."
If no patterns: "Nothing unusual in the past 7 days — the care log
looks stable."

## How I Work

I act, I don't ask for permission. If I need data, I get it.
I never say "would you like me to look that up?" — I look it up.

I am specific, not vague.
"$900/month after subsidies" not "much more affordable."
"Call AIC Link at 1800-650-6060" not "contact the relevant authority."

I am warm but efficient. Caregivers are exhausted. I get to the point.

When logging a care event, I confirm in one line and stop. Done.

I never make a caregiver feel guilty for asking about costs,
needing a break, or not coping. These are practical necessities.

## Starting a Session

1. Call caregiver-memory skill to retrieve the profile.
2. Profile found: greet warmly, reference last conversation,
   surface any unread notifications first.
3. No profile: onboard naturally. 1-2 questions at a time.
   Collect: condition → location → income → citizenship → care preference.
4. As soon as I have condition + location + income: call
   aic-facility-finder and subsidy-calculator immediately.

## Care Journal Logging

When a caregiver sends a care update:
1. Parse silently. Assign category and severity myself.
2. Call care-journal skill to log it.
3. Reply with exactly ONE warm line.
4. Emergency signals: "Call 995 or your care team immediately."

## Response Style

Real numbers: "$900/month after subsidies" not "more affordable"
Real next steps: "Call AIC Link at 1800-650-6060" not "contact AIC"
Never end without: "Verify current availability and fees directly
with the facility or AIC before making any decisions."

## What I Never Do

- Medical diagnosis or treatment advice
- Fabricate facility names, addresses, or costs
- Store NRIC, bank details, or passwords
- Share one user's data with another
- End a session without saving the profile update via caregiver-memory
ENDOFFILE

# ── AGENTS.md ─────────────────────────────────────────────────────────────────
cat > $WS/AGENTS.md << 'ENDOFFILE'
# CareCompass Operating Rules

## Tool Usage
- shell: enabled — for running Python scripts in skills/*/scripts/
- web: enabled — for scraping AIC pages
- file: read within workspace only

Do not run shell commands outside skill scripts.
Do not write files outside data/ and memory/.

## Session Rules
- Call caregiver-memory at session start before any response
- Call subsidy-calculator before recommending any facility
- Log care events immediately via care-journal when received
- Save profile silently after any message revealing new information
- Never ask permission before calling a skill

## Hard Limits
- No medical diagnosis or treatment advice
- No NRIC, bank account, or password storage
- No data sharing between user profiles
- No fabricating facility data

## Graceful Degradation
Scraper fails:
  → Read skills/aic-facility-finder/reference/facilities_fallback.json
  → Tell user: "Using recent data — verify at AIC.sg"
  → Suggest: AIC Link at 1800-650-6060

Calculator fails:
  → Use SOUL.md hardcoded tiers
  → Tell user to verify at AIC.sg

caregiver-memory unavailable:
  → Continue session, ask key details directly
  → Note: profile will not persist
ENDOFFILE

# ── HEARTBEAT.md ──────────────────────────────────────────────────────────────
cat > $WS/HEARTBEAT.md << 'ENDOFFILE'
# CareCompass Heartbeat

## Every 6 Hours: Bed Availability Check

For each profile in memory/profiles.json where alerts_active is true:
1. Call aic-facility-finder for preferred care_type and towns
2. Compare vacancy_status against last_vacancy_status in profile
3. If changed to "accepting" or "vacancies available":
   - Write notification to carecompass.db notifications table
4. Notification surfaces on caregiver's next session load

## Daily at 8am SGT: Care Journal Pattern Check

For each profile with care events in the past 7 days:
- Call care-journal detect action
- Thresholds:
    Medication refusals: 3+ in 7 days → flag
    Incidents: 2+ in 5 days → flag
    Poor appetite: 3+ consecutive days → flag
    Disrupted sleep: 4+ nights in 7 → flag
- For each flag: write notification to database

## Caregiver Check-In

### Reactive (within 24 hours of stress signal)
Message: "I noticed it's been a tough few days. How are you holding up?"

### Baseline (every Friday at 7pm SGT)
Message: "Week's wrapping up — how are you doing?"

### Response handling
If burnout language detected:
  → Call aic-facility-finder for respite care nearby
  → Surface 2 support groups from MEMORY.md
  → "Taking a break is a necessity, not a failure."
ENDOFFILE

# ── TOOLS.md ──────────────────────────────────────────────────────────────────
cat > $WS/TOOLS.md << 'ENDOFFILE'
# CareCompass Tool Guidance

## shell
Used to run Python scripts in skills/*/scripts/.
Run from workspace root. Pass all arguments explicitly.

Key invocations:
  python3 skills/subsidy-calculator/scripts/calculate.py \
    --income 8000 --size 4 --citizenship SC
  python3 skills/aic-facility-finder/scripts/scrape.py \
    --care_type nursing_home --location BISHAN
  python3 skills/care-journal/scripts/journal.py \
    --action log --user_id usr_123 --message "Mum took her Aricept"
  python3 skills/care-journal/scripts/journal.py \
    --action brief --user_id usr_123
  python3 skills/care-journal/scripts/journal.py \
    --action detect --user_id usr_123

## web
Used by aic-facility-finder only. Target AIC.sg pages.
Fallback to reference/facilities_fallback.json if web fails.

## file
Read reference JSON in skills/*/reference/.
Write only to data/carecompass.db and memory/.
ENDOFFILE

# ── MEMORY.md ─────────────────────────────────────────────────────────────────
cat > $WS/MEMORY.md << 'ENDOFFILE'
# CareCompass Memory

## Singapore Eldercare Subsidy Reference (2026)

Source: AIC.sg and MOH.gov.sg. Last verified: March 2026.
Enhanced subsidies effective July 2026 — always advise users
to verify current rates at AIC.

### Nursing Home Subsidies (Singapore Citizens)

PCHI = total monthly household income ÷ household members

| PCHI Range        | Subsidy | Effective Cost/month |
|-------------------|---------|----------------------|
| ≤ $1,200          | 80%     | $700 – $900          |
| $1,201 – $2,000   | 75%     | $900 – $1,100        |
| $2,001 – $2,800   | 65%     | $1,100 – $1,600      |
| $2,801 – $3,600   | 50%     | $1,400 – $2,000      |
| $3,601 – $4,800   | 25%     | $2,000 – $2,600      |
| > $4,800          | 0%      | $4,500 – $6,000+     |

PR: subtract 10 percentage points from SC rate at same PCHI.

### Day Care (SC)

| PCHI Range        | Effective Cost/day |
|-------------------|--------------------|
| ≤ $1,200          | $25 – $35          |
| $1,201 – $2,000   | $35 – $50          |
| $2,001 – $2,800   | $45 – $65          |
| $2,801 – $3,600   | $55 – $80          |
| $3,601 – $4,800   | $65 – $90          |
| > $4,800          | $90 – $150         |

### Caregiver Financial Assistance

Home Caregiving Grant (HCG):
  $250/month — permanent moderate disability, caring at home
  $400/month — permanent severe disability, caring at home
  Apply: AIC.sg or any AIC Link

Caregivers Training Grant (CTG):
  Up to $400/year for approved caregiver courses.
  All caregivers qualify. Also usable with SkillsFuture Credit.

MDW Levy Concession:
  Saves $240/month if employing FDW for care. Apply via MOM.

CareShield Life:
  $662+/month when severely disabled (3+ ADLs).
  Auto-enrolled: SC/PR born 1980 or later.

ElderFund: Up to $250/month for needy severely disabled SC aged 30+.

SMF: Subsidised consumables (diapers, hearing aids, wheelchair).
  SC aged 60+, PCHI ≤ $4,800.

### Caregiver Support Groups (Singapore)

Dementia Singapore — Caregiver Support Group
  Monthly sessions. Free. Contact: 6377 0700 | dementia.org.sg

NTUC Health CREST
  Islandwide community support and guidance. ntuchealth.sg/crest

Caregivers Alliance Limited (CAL)
  For caregivers of persons with mental health conditions.
  Contact: 6512 0347 | cal.org.sg

AIC Caregiver Support Line
  1800-650-6060 (toll-free, Mon–Fri 8:30am–8:30pm)

### AIC Contact

AIC Link: 1800-650-6060 (toll-free)
Website: www.aic.sg
ENDOFFILE

echo "[3/8] Workspace .md files written"

# ── Skills ────────────────────────────────────────────────────────────────────

# subsidy-calculator/SKILL.md
cat > $WS/skills/subsidy-calculator/SKILL.md << 'ENDOFFILE'
---
name: subsidy-calculator
description: >
  Calculates the means-tested LTC subsidy tier and effective monthly
  cost for Singapore eldercare. Use every time before presenting
  facility options. Never show a facility cost without running this.
version: 1.0.0
metadata:
  openclaw:
    requires:
      bins:
        - python3
---

## When to Use
Every time a caregiver mentions costs, income, or asks about care options.

## How to Run
python3 skills/subsidy-calculator/scripts/calculate.py \
  --income [monthly household income] \
  --size [number of household members] \
  --care_type [nursing_home|day_care] \
  --citizenship [SC|PR]

## Critical Test
income=8000 size=4 SC nursing_home → must return pchi=2000,
subsidy_tier=75%, effective=$900–1,100/month
ENDOFFILE

# caregiver-grants/SKILL.md
cat > $WS/skills/caregiver-grants/SKILL.md << 'ENDOFFILE'
---
name: caregiver-grants
description: >
  Identifies all financial assistance schemes a Singapore caregiver
  qualifies for: HCG, CTG, MDW Levy Concession, CareShield Life,
  ElderFund, SMF. Call automatically after subsidy-calculator.
version: 1.0.0
metadata:
  openclaw:
    requires:
      bins:
        - python3
---

## When to Use
Immediately after subsidy-calculator. Do not wait to be asked.

## How to Run
python3 skills/caregiver-grants/scripts/grants.py \
  --disability [mild|moderate|severe|permanent_moderate|permanent_severe] \
  --care_setting [home|facility] \
  --citizenship [SC|PR] \
  --has_fdw [true|false] \
  --income [number] \
  --size [number]
ENDOFFILE

# aic-facility-finder/SKILL.md
cat > $WS/skills/aic-facility-finder/SKILL.md << 'ENDOFFILE'
---
name: aic-facility-finder
description: >
  Finds eldercare facilities in Singapore matching a care type and
  location. Use when a caregiver asks about nursing homes, day care,
  home care, or respite options near a specific town.
version: 1.0.0
metadata:
  openclaw:
    requires:
      bins:
        - python3
      env:
        - BRIGHTDATA_API_KEY
    primaryEnv: BRIGHTDATA_API_KEY
---

## How to Run
python3 skills/aic-facility-finder/scripts/scrape.py \
  --care_type [nursing_home|day_care|home_care|respite] \
  --location [TOWN IN CAPS]

## Fallback Chain
1. Try scraping live AIC pages (via Bright Data proxy if available)
2. If empty: query TiDB/SQLite facilities table
3. If empty: read reference/facilities_fallback.json
ENDOFFILE

# care-journal/SKILL.md
cat > $WS/skills/care-journal/SKILL.md << 'ENDOFFILE'
---
name: care-journal
description: >
  Logs daily care observations in natural language, detects patterns
  over time, and generates structured medical briefs before doctor
  appointments.
version: 1.0.0
metadata:
  openclaw:
    requires:
      bins:
        - python3
---

## Three Actions
python3 skills/care-journal/scripts/journal.py --action log --user_id [id] --message "[msg]"
python3 skills/care-journal/scripts/journal.py --action detect --user_id [id]
python3 skills/care-journal/scripts/journal.py --action brief --user_id [id]
ENDOFFILE

# caregiver-memory/SKILL.md
cat > $WS/skills/caregiver-memory/SKILL.md << 'ENDOFFILE'
---
name: caregiver-memory
description: >
  Saves and retrieves caregiver and elder profiles across sessions.
  Call at the start of every session to retrieve context.
version: 1.0.0
metadata:
  openclaw:
    requires:
      bins:
        - python3
---

## How to Use
python3 skills/caregiver-memory/scripts/memory.py --action get --user_id [id]
python3 skills/caregiver-memory/scripts/memory.py --action save --user_id [id] --data '{"key":"value"}'
ENDOFFILE

echo "[4/8] SKILL.md files written"

# ── Python scripts ────────────────────────────────────────────────────────────

cat > $WS/skills/subsidy-calculator/scripts/calculate.py << 'ENDOFFILE'
import json, argparse, os

SQLITE_DB = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         '../../../data/carecompass.db')

def _get_conn():
    cs = os.environ.get('TIDB_CONNECTION_STRING', '')
    if cs:
        try:
            import pymysql
            from urllib.parse import urlparse
            p = urlparse(cs)
            conn = pymysql.connect(
                host=p.hostname, port=p.port or 4000,
                user=p.username, password=p.password or '',
                database=(p.path or '/carecompass').lstrip('/') or 'carecompass',
                ssl={'ssl_verify_cert': False, 'ssl_verify_identity': False},
                autocommit=True, charset='utf8mb4'
            )
            return conn, '%s'
        except Exception as e:
            print(f"TiDB fallback to SQLite: {e}", flush=True)
    import sqlite3
    return sqlite3.connect(SQLITE_DB), '?'

def calculate(income, size, care_type, citizenship):
    pchi = income / size
    conn, ph = _get_conn()
    c = conn.cursor()
    c.execute(f"""
        SELECT subsidy_pct, effective_cost_min, effective_cost_max
        FROM subsidy_tiers
        WHERE care_type={ph} AND pchi_min<={ph} AND pchi_max>={ph}
          AND citizenship={ph}
        LIMIT 1
    """, (care_type, pchi, pchi, citizenship))
    row = c.fetchone()
    conn.close()
    if not row:
        return {"error": "No matching tier", "pchi": round(pchi), "note": "Verify at AIC.sg"}
    pct, cost_min, cost_max = row
    return {
        "pchi": round(pchi),
        "subsidy_tier": f"{pct}%",
        "effective_monthly_cost": f"${cost_min}–{cost_max}",
        "unsubsidised_private_rate": "$4,500–6,000+/month",
        "annual_saving_vs_private": f"${(4500-cost_max)*12:,}–{(6000-cost_min)*12:,}",
        "note": "Enhanced subsidies from July 2026 — verify at AIC"
    }

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--income', type=int, required=True)
    p.add_argument('--size', type=int, required=True)
    p.add_argument('--care_type', default='nursing_home')
    p.add_argument('--citizenship', default='SC')
    args = p.parse_args()
    print(json.dumps(calculate(args.income, args.size, args.care_type, args.citizenship)))
ENDOFFILE

# caregiver-grants/scripts/grants.py (no DB needed)
cat > $WS/skills/caregiver-grants/scripts/grants.py << 'ENDOFFILE'
import json, argparse

def get_grants(disability, care_setting, citizenship, has_fdw, income, size):
    pchi = income / size if size > 0 else 0
    grants = []
    grants.append({
        "grant": "Caregivers Training Grant (CTG)",
        "amount": "Up to $400/year",
        "why_eligible": "All caregivers of seniors qualify",
        "how_to_apply": "Apply at AIC.sg or any AIC Link",
        "monthly_value": 33,
        "note": "Also usable with SkillsFuture Credit"
    })
    if care_setting == 'home' and disability in ['permanent_moderate','permanent_severe','severe']:
        amount = 400 if disability in ['permanent_severe','severe'] else 250
        grants.append({
            "grant": "Home Caregiving Grant (HCG)",
            "amount": f"${amount}/month",
            "why_eligible": "Caring for parent with permanent disability at home",
            "how_to_apply": "Apply at AIC.sg or any AIC Link",
            "monthly_value": amount
        })
    if has_fdw:
        grants.append({
            "grant": "MDW Levy Concession",
            "amount": "$240/month saved",
            "why_eligible": "Employing FDW to care for a senior",
            "how_to_apply": "Apply through MOM at mom.gov.sg",
            "monthly_value": 240
        })
    if citizenship in ['SC', 'PR']:
        grants.append({
            "grant": "CareShield Life",
            "amount": "$662+/month (on successful claim)",
            "why_eligible": "SC/PR born 1980+ — auto-enrolled",
            "how_to_apply": "Claim when severely disabled via cpf.gov.sg",
            "monthly_value": 0,
            "note": "Future protection — activates on severe disability"
        })
    if citizenship == 'SC' and pchi <= 4800:
        grants.append({
            "grant": "Seniors' Mobility and Enabling Fund (SMF)",
            "amount": "Subsidised diapers, hearing aids, wheelchair",
            "why_eligible": "SC aged 60+, PCHI below $4,800",
            "how_to_apply": "Through home healthcare provider or AIC",
            "monthly_value": 0
        })
    if citizenship == 'SC' and disability in ['severe','permanent_severe']:
        grants.append({
            "grant": "ElderFund",
            "amount": "Up to $250/month",
            "why_eligible": "Needy severely disabled SC — verify at AIC",
            "how_to_apply": "Apply at any AIC Link",
            "monthly_value": 250
        })
    cash = sum(g['monthly_value'] for g in grants if g.get('monthly_value',0) > 0)
    return {
        "grants": grants,
        "total_monthly_relief": f"${cash}/month in grants and savings",
        "note": "Verify eligibility at AIC.sg"
    }

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--disability', default='moderate')
    p.add_argument('--care_setting', default='home')
    p.add_argument('--citizenship', default='SC')
    p.add_argument('--has_fdw', default='false')
    p.add_argument('--income', type=int, default=8000)
    p.add_argument('--size', type=int, default=4)
    args = p.parse_args()
    print(json.dumps(get_grants(
        args.disability, args.care_setting, args.citizenship,
        args.has_fdw == 'true', args.income, args.size
    ), indent=2))
ENDOFFILE

# Embed the full journal.py and scrape.py and memory.py from local copies
cp /dev/stdin $WS/skills/care-journal/scripts/journal.py << 'ENDOFFILE'
import json, argparse, os
from datetime import datetime, timedelta
from collections import defaultdict

SQLITE_DB = os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../data/carecompass.db')

def _get_conn():
    cs = os.environ.get('TIDB_CONNECTION_STRING', '')
    if cs:
        try:
            import pymysql
            from urllib.parse import urlparse
            p = urlparse(cs)
            conn = pymysql.connect(
                host=p.hostname, port=p.port or 4000,
                user=p.username, password=p.password or '',
                database=(p.path or '/carecompass').lstrip('/') or 'carecompass',
                ssl={'ssl_verify_cert': False, 'ssl_verify_identity': False},
                autocommit=True, charset='utf8mb4'
            )
            return conn, '%s'
        except Exception as e:
            print(f"TiDB fallback to SQLite: {e}", flush=True)
    import sqlite3
    return sqlite3.connect(SQLITE_DB), '?'

CATEGORIES = {
    'medication': ['took','tablet','pill','dose','aricept','medication','medicine','drug','refused her','refused medication'],
    'nutrition':  ['ate','food','meal','dinner','lunch','breakfast','refused dinner','appetite','banana','drink','eating','barely','nothing','only half'],
    'incident':   ['fall','fell','injury','hurt','accident','wandering','found','confused at','emergency','ambulance','fainted'],
    'sleep':      ['slept','sleep','woke','night','awake','2am','3am','insomnia','restless','up three','up twice','no sleep'],
    'mood':       ['happy','sad','agitated','calm','anxious','good mood','bad mood','cheerful','distressed','upset','irritable'],
    'behaviour':  ['aggressive','wandered','asking for','repeated','sundowning','yelling','resistant','refusing'],
    'medical_update': ['doctor','hospital','prescription','changed dose','increased','decreased','diagnosed','appointment','referral','discharged','new medication'],
}
CONFIRM = {
    'medication':'Logged ✓ Medication noted.','nutrition':'Logged ✓ Hope her appetite improves.',
    'incident':'Logged ✓ Glad there was no serious injury.','sleep':'Logged ✓ Hope tonight is better.',
    'mood':'Logged ✓','behaviour':'Logged ✓ Behaviour noted.',
    'medical_update':'Logged ✓ Medical update recorded.','other':'Logged ✓',
}

def categorise(msg):
    m = msg.lower()
    for cat, kws in CATEGORIES.items():
        if any(k in m for k in kws): return cat
    return 'other'

def severity(msg):
    m = msg.lower()
    if any(w in m for w in ['fell','fall','emergency','995','ambulance']): return 'urgent'
    if any(w in m for w in ['refused','wandering','confused','agitated','bad','terrible','up three','up twice','barely','nothing']): return 'notable'
    return 'routine'

def log_event(user_id, message):
    cat = categorise(message); sev = severity(message)
    conn, ph = _get_conn(); c = conn.cursor()
    c.execute(f"INSERT INTO care_events (user_id,category,summary,severity,raw_message,created_at) VALUES({ph},{ph},{ph},{ph},{ph},{ph})",
              (user_id, cat, message[:100], sev, message, datetime.now().isoformat()))
    if hasattr(conn,'commit'): conn.commit()
    conn.close()
    return CONFIRM.get(cat, 'Logged ✓')

def detect_patterns(user_id, days=7):
    cutoff = (datetime.now()-timedelta(days=days)).isoformat()
    conn, ph = _get_conn(); c = conn.cursor()
    c.execute(f"SELECT category, raw_message, created_at FROM care_events WHERE user_id={ph} AND created_at>={ph} ORDER BY created_at", (user_id, cutoff))
    events = c.fetchall(); conn.close()
    grouped = defaultdict(list)
    for cat, raw, ts in events: grouped[cat].append({'raw': raw or '', 'date': str(ts)[:10]})
    flags = []
    refusals = [e for e in grouped.get('medication',[]) if 'refus' in e['raw'].lower()]
    if len(refusals) >= 3: flags.append(f"Medication refused {len(refusals)} times this week.")
    if len(grouped.get('incident',[])) >= 2: flags.append(f"{len(grouped['incident'])} incidents in the past 5 days.")
    poor = [e for e in grouped.get('nutrition',[]) if any(w in e['raw'].lower() for w in ['refused','barely','nothing','only half'])]
    if len(poor) >= 3: flags.append(f"Poor appetite noted {len(poor)} times.")
    if len(grouped.get('sleep',[])) >= 4: flags.append(f"Disrupted sleep {len(grouped['sleep'])} nights.")
    return {"flags": flags}

def generate_brief(user_id, days=14):
    cutoff = (datetime.now()-timedelta(days=days)).isoformat()
    conn, ph = _get_conn(); c = conn.cursor()
    c.execute(f"SELECT category, summary, severity, raw_message, created_at FROM care_events WHERE user_id={ph} AND created_at>={ph} ORDER BY created_at", (user_id, cutoff))
    events = c.fetchall(); conn.close()
    if not events: return "No care events logged in the past 14 days."
    grouped = defaultdict(list)
    for cat, summary, sev, raw, ts in events:
        grouped[cat].append({'summary':summary,'severity':sev,'raw':raw or '','date':str(ts)[:10]})
    today = datetime.now().strftime('%d %B %Y')
    start = (datetime.now()-timedelta(days=days)).strftime('%d %B %Y')
    sections = [f"CARE SUMMARY\nPrepared: {today} | Period: {start}–{today}"]
    if 'medication' in grouped:
        meds = grouped['medication']; refusals = [e for e in meds if 'refus' in e['raw'].lower()]
        taken = len(meds) - len(refusals)
        line = f"MEDICATION ADHERENCE\n{taken} doses confirmed."
        if refusals: line += f" Refused on: {', '.join(sorted(set(e['date'] for e in refusals)))}."
        sections.append(line)
    if 'incident' in grouped:
        sections.append("INCIDENTS\n" + "\n".join(f"  {e['date']}: {e['summary']}" for e in grouped['incident']))
    if 'sleep' in grouped:
        sections.append(f"SLEEP\n{len(grouped['sleep'])} nights with disrupted sleep.")
    if 'nutrition' in grouped:
        poor = [e for e in grouped['nutrition'] if any(w in e['raw'].lower() for w in ['refused','barely','little','nothing','half','only'])]
        sections.append(f"APPETITE & NUTRITION\n{len(poor)} instances of poor appetite.")
    beh = grouped.get('behaviour',[]) + grouped.get('mood',[])
    if beh: sections.append(f"MOOD & BEHAVIOUR\n{len(beh)} observations.")
    questions = []
    refusals = [e for e in grouped.get('medication',[]) if 'refus' in e['raw'].lower()]
    if len(refusals) >= 2: questions.append("Medication refusals are recurring — is there a different formulation or timing that might help?")
    if 'medical_update' in grouped and ('behaviour' in grouped or 'mood' in grouped):
        questions.append("A medication change was logged alongside behavioural changes — could these be related?")
    if len(grouped.get('incident',[])) >= 2:
        questions.append(f"{len(grouped['incident'])} incidents logged — should we assess the home for fall risks?")
    if not questions: questions.append("Are current care arrangements still appropriate for her current stage?")
    sections.append("QUESTIONS FOR TODAY'S APPOINTMENT\n" + "\n".join(f"• {q}" for q in questions))
    return "\n\n".join(sections)

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--action', choices=['log','detect','brief'], required=True)
    p.add_argument('--user_id', default='usr_demo001')
    p.add_argument('--message', default='')
    args = p.parse_args()
    if args.action == 'log': print(log_event(args.user_id, args.message))
    elif args.action == 'detect': print(json.dumps(detect_patterns(args.user_id)))
    elif args.action == 'brief': print(generate_brief(args.user_id))
ENDOFFILE

cat > $WS/skills/aic-facility-finder/scripts/scrape.py << 'ENDOFFILE'
import requests
from bs4 import BeautifulSoup
import json, argparse, os
from datetime import datetime

BASE = os.path.dirname(os.path.abspath(__file__))
SQLITE_DB = os.path.join(BASE, '../../../data/carecompass.db')
FALLBACK = os.path.join(BASE, '../reference/facilities_fallback.json')

URLS = {
    'nursing_home': 'https://www.aic.sg/care-services/nursing-home/',
    'day_care':     'https://www.aic.sg/care-services/senior-day-care/',
    'home_care':    'https://www.aic.sg/care-services/home-personal-care/',
    'respite':      'https://www.aic.sg/care-services/nursing-home-respite-care/',
}
HEADERS = {'User-Agent': 'Mozilla/5.0 (compatible; CareCompass/1.0)'}

def _get_conn():
    cs = os.environ.get('TIDB_CONNECTION_STRING', '')
    if cs:
        try:
            import pymysql
            from urllib.parse import urlparse
            p = urlparse(cs)
            conn = pymysql.connect(
                host=p.hostname, port=p.port or 4000,
                user=p.username, password=p.password or '',
                database=(p.path or '/carecompass').lstrip('/') or 'carecompass',
                ssl={'ssl_verify_cert': False, 'ssl_verify_identity': False},
                autocommit=True, charset='utf8mb4'
            )
            return conn, '%s'
        except Exception as e:
            print(f"TiDB fallback to SQLite: {e}", flush=True)
    import sqlite3
    return sqlite3.connect(SQLITE_DB), '?'

def fetch_page(url):
    api_key = os.environ.get('BRIGHTDATA_API_KEY', '')
    zone = os.environ.get('BRIGHTDATA_SERP_ZONE', '')
    if api_key and zone:
        try:
            proxy = f'http://{zone}:{api_key}@brd.superproxy.io:22225'
            return requests.get(url, headers=HEADERS, timeout=20,
                                proxies={'http': proxy, 'https': proxy}, verify=False)
        except Exception as e:
            print(f"Bright Data failed, trying direct: {e}", flush=True)
    return requests.get(url, headers=HEADERS, timeout=10)

def parse(html, care_type, location):
    soup = BeautifulSoup(html, 'html.parser')
    results = []
    for item in soup.select('.facility-item, .provider-item, .care-provider, li'):
        name = item.select_one('h3, h4, .name, strong')
        addr = item.select_one('.address, .location, p')
        phone = item.select_one('a[href^="tel"], .phone')
        if name and len(name.get_text(strip=True)) > 5:
            results.append({
                'name': name.get_text(strip=True), 'address': addr.get_text(strip=True) if addr else '',
                'town': location.upper(), 'care_types': [care_type],
                'accepts_subsidies': True, 'vacancy_status': 'unknown',
                'contact': phone.get_text(strip=True) if phone else '',
                'scraped_at': datetime.now().isoformat()
            })
    return results

def save_db(items):
    conn, ph = _get_conn(); c = conn.cursor()
    for f in items:
        try:
            c.execute(f"INSERT INTO facilities (name,address,town,care_types,accepts_subsidies,vacancy_status,contact_phone,scraped_at) VALUES({ph},{ph},{ph},{ph},{ph},{ph},{ph},{ph})",
                      (f['name'],f['address'],f['town'],json.dumps(f['care_types']),int(f['accepts_subsidies']),f['vacancy_status'],f['contact'],f['scraped_at']))
        except Exception: pass
    if hasattr(conn,'commit'): conn.commit()
    conn.close()

def from_db(care_type, location):
    conn, ph = _get_conn(); c = conn.cursor()
    c.execute(f"SELECT name,address,town,care_types,vacancy_status,contact_phone FROM facilities WHERE town={ph} AND care_types LIKE {ph} ORDER BY scraped_at DESC LIMIT 5",
              (location.upper(), f'%{care_type}%'))
    rows = c.fetchall(); conn.close()
    return [{'name':r[0],'address':r[1],'town':r[2],'care_types':json.loads(r[3] or '[]'),'accepts_subsidies':True,'vacancy_status':r[4],'contact':r[5]} for r in rows]

def from_fallback(care_type, location):
    if not os.path.exists(FALLBACK): return []
    with open(FALLBACK) as f: data = json.load(f)
    return [x for x in data if location.upper() in x.get('town','').upper() and care_type in x.get('care_types',[])][:5]

def run(care_type, location):
    url = URLS.get(care_type)
    if url:
        try:
            resp = fetch_page(url)
            items = parse(resp.text, care_type, location)
            if items:
                save_db(items)
                return items[:5]
        except Exception as e:
            print(f"Scraper error: {e}", flush=True)
    cached = from_db(care_type, location)
    if cached: return cached
    return from_fallback(care_type, location)

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--care_type', default='nursing_home')
    p.add_argument('--location', default='BISHAN')
    args = p.parse_args()
    print(json.dumps(run(args.care_type, args.location), indent=2))
ENDOFFILE

cat > $WS/skills/caregiver-memory/scripts/memory.py << 'ENDOFFILE'
import json, os, argparse

BASE = os.path.dirname(os.path.abspath(__file__))
PROFILES = os.path.join(BASE, '../../memory/profiles.json')

def _get_conn():
    cs = os.environ.get('TIDB_CONNECTION_STRING', '')
    if cs:
        try:
            import pymysql
            from urllib.parse import urlparse
            p = urlparse(cs)
            return pymysql.connect(
                host=p.hostname, port=p.port or 4000,
                user=p.username, password=p.password or '',
                database=(p.path or '/carecompass').lstrip('/') or 'carecompass',
                ssl={'ssl_verify_cert': False, 'ssl_verify_identity': False},
                autocommit=True, charset='utf8mb4'
            )
        except Exception as e:
            print(f"TiDB fallback to JSON: {e}", flush=True)
    return None

def get(uid):
    conn = _get_conn()
    if conn:
        c = conn.cursor()
        c.execute("SELECT profile_json FROM caregiver_profiles WHERE user_id=%s", (uid,))
        row = c.fetchone(); conn.close()
        return json.loads(row[0]) if row else None
    if os.path.exists(PROFILES):
        with open(PROFILES) as f: return json.load(f).get(uid)
    return None

def save(uid, data):
    conn = _get_conn()
    if conn:
        existing = get(uid) or {}; existing.update(data)
        c = conn.cursor()
        c.execute("INSERT INTO caregiver_profiles (user_id,profile_json) VALUES (%s,%s) ON DUPLICATE KEY UPDATE profile_json=%s",
                  (uid, json.dumps(existing), json.dumps(existing)))
        conn.close(); return existing
    profiles = {}
    if os.path.exists(PROFILES):
        with open(PROFILES) as f: profiles = json.load(f)
    profiles.setdefault(uid, {}).update(data)
    os.makedirs(os.path.dirname(PROFILES), exist_ok=True)
    with open(PROFILES, 'w') as f: json.dump(profiles, f, indent=2)
    return profiles[uid]

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--action', choices=['get','save'], required=True)
    p.add_argument('--user_id', required=True)
    p.add_argument('--data', default='{}')
    args = p.parse_args()
    if args.action == 'get':
        profile = get(args.user_id)
        print(json.dumps(profile) if profile else 'null')
    elif args.action == 'save':
        print(json.dumps(save(args.user_id, json.loads(args.data))))
ENDOFFILE

echo "[5/8] Python scripts written"

# ── Fallback JSON ─────────────────────────────────────────────────────────────
cat > $WS/skills/aic-facility-finder/reference/facilities_fallback.json << 'ENDOFFILE'
[
  {"name":"Bright Hill Evergreen Home","address":"22 Sin Ming Road, Singapore 575580","town":"BISHAN","care_types":["nursing_home","dementia_care"],"accepts_subsidies":true,"vacancy_status":"unknown","contact":"6453 3644"},
  {"name":"Lions Home for the Elders","address":"10 Bishan Street 13, Singapore 579779","town":"BISHAN","care_types":["nursing_home"],"accepts_subsidies":true,"vacancy_status":"unknown","contact":"6255 0655"},
  {"name":"Thye Hua Kwan Nursing Home (Bishan)","address":"9 Bishan Place, Singapore 579839","town":"BISHAN","care_types":["nursing_home","day_care"],"accepts_subsidies":true,"vacancy_status":"unknown","contact":"6251 3038"},
  {"name":"St Luke's ElderCare (Ang Mo Kio)","address":"3 Ang Mo Kio Street 62, Singapore 569141","town":"ANG MO KIO","care_types":["nursing_home","day_care","dementia_care"],"accepts_subsidies":true,"vacancy_status":"unknown","contact":"6453 6930"},
  {"name":"NTUC Health Nursing Home (Jurong West)","address":"2 Jurong West Avenue 1, Singapore 649520","town":"JURONG WEST","care_types":["nursing_home"],"accepts_subsidies":true,"vacancy_status":"unknown","contact":"6563 8998"},
  {"name":"Apex Harmony Lodge","address":"10 Buangkok View, Singapore 539747","town":"HOUGANG","care_types":["nursing_home","dementia_care"],"accepts_subsidies":true,"vacancy_status":"unknown","contact":"6385 1538"},
  {"name":"Orange Valley Nursing Home (Clementi)","address":"55 Clementi Road, Singapore 129908","town":"CLEMENTI","care_types":["nursing_home"],"accepts_subsidies":true,"vacancy_status":"unknown","contact":"6463 2889"}
]
ENDOFFILE

echo "[6/8] Fallback JSON written"

# ── TiDB setup or SQLite fallback ─────────────────────────────────────────────
echo '{}' > $WS/memory/profiles.json

if [ -n "$TIDB_CONNECTION_STRING" ]; then
    echo "Running TiDB setup..."
    python3 $WS/data/tidb_setup.py
else
    echo "TIDB_CONNECTION_STRING not set — initialising SQLite fallback..."
    python3 - << 'PYEOF'
import sqlite3, os
from datetime import datetime, timedelta
import json

DB = os.path.expanduser("~/.openclaw/workspaces/carecompass/data/carecompass.db")
conn = sqlite3.connect(DB)
conn.executescript(open(os.path.expanduser("~/.openclaw/workspaces/carecompass/data/schema.sql")).read())
conn.executescript(open(os.path.expanduser("~/.openclaw/workspaces/carecompass/data/subsidy_tiers.sql")).read())
conn.executescript(open(os.path.expanduser("~/.openclaw/workspaces/carecompass/data/facilities_fallback_seed.sql")).read())
conn.executescript(open(os.path.expanduser("~/.openclaw/workspaces/carecompass/data/demo_seed.sql")).read())
conn.commit(); conn.close()
print("SQLite initialised")
PYEOF
fi

echo "[7/8] Database ready"

# ── Register agent ────────────────────────────────────────────────────────────
openclaw agents add carecompass --workspace $WS 2>/dev/null || true
openclaw gateway restart 2>/dev/null || true
echo "[8/8] Agent registered — done!"
echo ""
echo "✓ CareCompass workspace deployed to $WS"
echo "  Next: paste openclaw_zeabur.json into Zeabur File Management"
echo "  at /home/node/.openclaw/openclaw.json, then restart the service."
