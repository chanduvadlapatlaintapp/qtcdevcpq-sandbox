# AgenticQTC — E2E Test Suite · Team Setup Guide

> **Audience:** Any developer cloning this repo who wants to run the Playwright E2E tests  
> and the live test dashboard against the `qtcmock` Salesforce sandbox.

---

## What this does

| Component | What it is |
|---|---|
| `tests/e2e/agenticQtcQuantityIncrease.spec.js` | Full E2E test — logs in, navigates to AgenticQTC, selects Baker McKenzie LLP, opens a contract, edits quantities, saves, then verifies both the UI state and the actual Salesforce DB records via REST API |
| `tests/e2e/agenticQtc.spec.js` | Lighter smoke test — Steps 1–7 navigation only, no DB checks |
| `tests/e2e/dashboard/server.js` | Local web server at `http://localhost:7777` — "Run Tests" button, live terminal output, KPI cards, anomaly list, screenshot gallery, run history |
| `tests/e2e/helpers/sfAuth.js` | Auth helper — reads your SF CLI session to log the test browser in via `frontdoor.jsp` (no passwords stored anywhere) |

**No AI tokens are consumed at runtime.** The test uses Playwright + Salesforce REST API only.

---

## Prerequisites

### 1 · Node.js 20+

```bash
node --version   # must be v20 or higher
```

If not installed: https://nodejs.org/en/download  
Or via Homebrew: `brew install node`  
Or via Volta: `volta install node`

### 2 · Salesforce CLI (`sf`)

```bash
sf --version   # must be @salesforce/cli v2+
```

If not installed:
```bash
npm install --global @salesforce/cli
```

### 3 · Playwright browsers

After `npm install` (step below), install the Chromium binary:
```bash
npx playwright install chromium
```

---

## Setup (first time only)

```bash
# 1. Clone / pull the repo
git clone <repo-url>
cd qtcdevcpq-sandbox

# 2. Install Node dependencies
npm install

# 3. Install Playwright's Chromium browser
npx playwright install chromium

# 4. Authenticate with the qtcmock Salesforce sandbox
sf org login web --alias qtcmock --instance-url https://intapp--qtcmock.sandbox.my.salesforce.com
#   ↑ This opens a browser. Log in with your Salesforce credentials once.
#     SF CLI saves the session token — Playwright uses it automatically.

# 5. Verify the connection
sf org display --target-org qtcmock
#   You should see: Status: Connected  and an accessToken
```

---

## Running tests

### Option A — Dashboard (recommended)

Start the dashboard server in one terminal:
```bash
npm run dashboard
# → Opens http://localhost:7777 automatically
```

Then click **Run Tests** in the browser. You'll see:
- Live terminal output streaming in real time
- KPI cards (UI assertions, DB anomaly count, ACV before/after)
- Screenshot gallery (every run saved in its own timestamped folder)
- Run history — click any past run to reload its results

### Option B — CLI directly

```bash
# Full test with DB verification
npx playwright test tests/e2e/agenticQtcQuantityIncrease.spec.js

# Smoke test only
npx playwright test tests/e2e/agenticQtc.spec.js

# Run headless (no visible browser window)
npx playwright test --headed=false tests/e2e/agenticQtcQuantityIncrease.spec.js

# Show HTML report after a run
npx playwright show-report tests/e2e/report
```

---

## Directory structure

```
tests/e2e/
├── agenticQtcQuantityIncrease.spec.js   ← main test (quantity edit + DB verify)
├── agenticQtc.spec.js                   ← smoke test (navigation only)
├── helpers/
│   └── sfAuth.js                        ← SF CLI → Playwright session helper
├── dashboard/
│   └── server.js                        ← web dashboard (port 7777)
└── results/                             ← GITIGNORED — generated per run
    ├── results.json                      ← latest run data (read by dashboard)
    ├── quantity-increase-report.html     ← latest HTML report
    └── runs/
        └── 2025-01-15_14-30-00/         ← one folder per run (timestamped)
            ├── results.json
            ├── 01-contracts.png
            ├── 02-editor-loaded.png
            └── ...
```

> **Note:** `tests/e2e/results/` is in `.gitignore`. Screenshots and run data are generated locally and never committed. Each developer builds their own run history.

---

## How auth works (no passwords, no tokens in git)

1. You ran `sf org login web --alias qtcmock` once — SF CLI saved an OAuth access token in your local keychain/config (`~/.sf/`).
2. Before each test, `sfAuth.js` calls `sf org display --target-org qtcmock` to read that token.
3. Playwright opens `frontdoor.jsp?sid=<token>` — Salesforce's official OAuth-to-browser-session exchange — which sets a real `sid` session cookie.
4. All subsequent test navigation is authenticated.

**Your token never touches git.** If the session expires, just re-run `sf org login web --alias qtcmock`.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `sf CLI not found` error | Run `npm install -g @salesforce/cli` then retry |
| `INVALID_SESSION_ID` during test | Session expired — run `sf org login web --alias qtcmock` |
| Browser stays on Salesforce login page | Same as above — token expired |
| `Error: connect ECONNREFUSED 127.0.0.1:7777` | Dashboard not running — start with `npm run dashboard` |
| `Port 7777 is already in use` | Kill the existing server: `lsof -ti:7777 \| xargs kill` |
| Playwright browser not found | Run `npx playwright install chromium` |
| Test times out finding quote lines | The amendment quote creation is slow on first run (~60–90s). The test has 2-min patience — just wait. |
| `INVALID_FIELD` SOQL error in DB step | Field doesn't exist in this org version — the test auto-discovers available fields, so this should self-heal |

---

## Re-authenticating (token expiry)

Salesforce sandbox sessions typically expire after **24 hours** of inactivity.

```bash
sf org login web --alias qtcmock --instance-url https://intapp--qtcmock.sandbox.my.salesforce.com
```

Log in via the browser that opens. No other changes needed — tests will pick up the new token automatically.

---

## What the tests verify

The `agenticQtcQuantityIncrease` test:

1. **UI navigation** — loads AgenticQTC app, searches Baker McKenzie LLP, selects account, opens 3rd contract row (Microsoft Intune — single-product, loads fast)
2. **Quantity edit** — increases every editable line's quantity by +5
3. **Save** — clicks Save, waits for CPQ async recalculation
4. **UI assertions** — reads back all quantity inputs, asserts each increased by exactly +5
5. **DB verification** — queries `SBQQ__QuoteLine__c` via Salesforce REST API using your Bearer token, compares DB quantities and prices against what the UI showed
6. **Anomaly detection** — flags zero-price lines, zero net totals, missing segment keys
7. **Results export** — writes `results.json` + PNG screenshots to a timestamped run folder

---

*Questions? Ping the team or check the run screenshots in `tests/e2e/results/runs/` for visual debugging.*
