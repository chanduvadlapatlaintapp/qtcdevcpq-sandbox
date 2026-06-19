# Playwright Test Authoring & Deployment Guide

> **Audience:** Developers adding or maintaining Playwright E2E tests for the QTC CPQ automation suite.
> Tests run on GitHub Actions (cloud, headless) and results appear live in the Salesforce LWC dashboard.

---

## How the System Works (30-second overview)

```
Developer pushes test code to GitHub
        ↓
Salesforce LWC dashboard → click "Run Tests"
        ↓
Apex creates a Test_Run__c record → calls GitHub API
        ↓
GitHub Actions runner spins up (ubuntu-latest)
  • Checks out your code
  • Authenticates to Salesforce (SF CLI)
  • Runs npx playwright test <your-spec-file>
  • Uploads screenshots, video, results back to Salesforce
        ↓
LWC dashboard shows live status → PASSED / FAILED + all screenshots & data
```

The runner always uses **the latest code on `feature/github-actions-runner`** (or whatever branch is configured in the workflow). Push your spec → trigger a run → results appear in Salesforce.

---

## Repository Layout

```
qtcdevcpq-sandbox/
├── tests/e2e/
│   ├── helpers/
│   │   └── sfAuth.js                  ← SF login helper (don't modify)
│   ├── agenticQtcQuantityIncrease.spec.js   ← existing suite
│   ├── demo-pdf-generation.spec.js          ← existing suite
│   └── yourNewTest.spec.js                  ← ADD YOUR FILE HERE
│
├── .github/
│   ├── workflows/
│   │   └── playwright.yml             ← CI pipeline (add suite mapping here)
│   └── scripts/
│       ├── upload-results.js          ← posts results to Salesforce
│       └── update-run.js              ← marks run RUNNING / FAILED
│
├── playwright.config.js               ← timeout, viewport, video settings
└── force-app/main/default/lwc/
    └── agenticQtcTestDashboard/
        └── agenticQtcTestDashboard.js ← add suite to the dropdown here
```

---

## Step-by-step: Adding a New Test Suite

### Step 1 — Write your spec file

Create `tests/e2e/yourSuiteName.spec.js`. Use any existing spec as a reference. The bare minimum structure:

```js
// @ts-check
const { test, expect }                  = require('@playwright/test');
const { getSfCredentials, loginViaCookie } = require('./helpers/sfAuth');

test('my test description', async ({ page }) => {
    // 1. Authenticate — always start with this
    const { instanceUrl, lightningUrl, accessToken } = getSfCredentials();
    await loginViaCookie(page, instanceUrl, accessToken);

    // 2. Navigate to your Salesforce page
    await page.goto(`${lightningUrl}/lightning/n/Your_App_Name`, {
        waitUntil: 'domcontentloaded',
    });

    // 3. Your test logic
    await page.getByText('Some Element').waitFor({ state: 'visible' });
    await expect(page.getByText('Expected Text')).toBeVisible();

    // 4. Take screenshots (automatically uploaded to Salesforce Files)
    await page.screenshot({ path: `tests/e2e/results/runs/${Date.now()}/01-my-step.png` });
});
```

**Key helpers available in `sfAuth.js`:**

| Function | What it does |
|---|---|
| `getSfCredentials()` | Returns `{ instanceUrl, lightningUrl, accessToken }` from the authenticated SF CLI org |
| `loginViaCookie(page, instanceUrl, accessToken)` | Injects a Salesforce session into the browser via `frontdoor.jsp` — no login page |

The `QTC_SF_ORG` env var controls which org is used (`qtcmock` for mock, `qtcuat` for UAT). GitHub Actions sets this automatically based on which Salesforce org triggered the run.

---

### Step 2 — Register the suite in the workflow

Open `.github/workflows/playwright.yml`, find the `case` block around line 177 and add your mapping:

```yaml
# Before
case "$SUITE" in
  agenticQtcQuantityIncrease) SPEC="tests/e2e/agenticQtcQuantityIncrease.spec.js" ;;
  demoPdfGeneration)          SPEC="tests/e2e/demo-pdf-generation.spec.js" ;;
  *)                          SPEC="tests/e2e/${SUITE}.spec.js" ;;
esac

# After — add your line
case "$SUITE" in
  agenticQtcQuantityIncrease) SPEC="tests/e2e/agenticQtcQuantityIncrease.spec.js" ;;
  demoPdfGeneration)          SPEC="tests/e2e/demo-pdf-generation.spec.js" ;;
  yourSuiteName)              SPEC="tests/e2e/yourSuiteName.spec.js" ;;   # ADD THIS
  *)                          SPEC="tests/e2e/${SUITE}.spec.js" ;;
esac
```

> **Shortcut:** If your suite name exactly matches the spec filename (without `.spec.js`), the `*` catch-all handles it automatically and you can skip this step.

---

### Step 3 — Add to the LWC dropdown

Open `force-app/main/default/lwc/agenticQtcTestDashboard/agenticQtcTestDashboard.js`, find `SUITE_OPTIONS` near the top and add your suite:

```js
const SUITE_OPTIONS = [
    { label: 'Quantity Increase (Full Flow)', value: 'agenticQtcQuantityIncrease' },
    { label: 'PDF Generation Demo',           value: 'demoPdfGeneration' },
    { label: 'Your Suite Display Name',       value: 'yourSuiteName' },  // ADD THIS
];
```

The `value` must match exactly what you put in the `case` block in step 2.

---

### Step 4 — Push and deploy

```bash
# Push test code + workflow changes to GitHub
git add tests/e2e/yourSuiteName.spec.js .github/workflows/playwright.yml
git commit -m "feat: add yourSuiteName Playwright suite"
git push origin feature/github-actions-runner

# Deploy the LWC dropdown change to Salesforce
export PATH="$HOME/.local/node-v20.12.2-darwin-arm64/bin:$PATH"
sf project deploy start \
  --source-dir force-app/main/default/lwc/agenticQtcTestDashboard \
  --target-org qtcmock --wait 10

# Also deploy to UAT if needed
sf project deploy start \
  --source-dir force-app/main/default/lwc/agenticQtcTestDashboard \
  --target-org qtcuat --wait 10
```

---

### Step 5 — Run your test

1. Open the Salesforce LWC dashboard
   - **Mock:** `https://intapp--qtcmock.sandbox.lightning.force.com/lightning/n/QTC_Test_Runner`
   - **UAT:** `https://intapp--uat.sandbox.lightning.force.com/lightning/n/QTC_Test_Runner`
2. Select your suite from the dropdown
3. Make sure runner is set to **☁️ GitHub**
4. Click **Run on GitHub**
5. Status transitions: `CLAIMED → RUNNING → PASSED / FAILED` (typically 2–4 min)

---

## Viewing Results

### In Salesforce (primary)

The LWC dashboard shows everything after the run:

| Tab | What it shows |
|---|---|
| **Screenshots** | Every `page.screenshot()` call, in order |
| **UI↔DB** | Cross-check between UI values and database |
| **DB Lines** | Raw quote line data from Salesforce |
| **Metrics** | ACV, TCV, pricing metrics before/after save |
| **Anomalies** | DB inconsistencies detected during the run |
| **Spec** | Playwright test pass/fail per `test()` block |
| **Log** | Full console output from the runner |

### In GitHub Actions (debugging)

All runs: **https://github.com/chanduvadlapatlaintapp/qtcdevcpq-sandbox/actions/workflows/playwright.yml**

Each run has:
- **Step-by-step logs** — see exactly which Playwright step failed and why
- **Artifact** named `playwright-<runId>` — download for the full HTML report, all screenshots, and the video recording

Direct link to the workflow file: **https://github.com/chanduvadlapatlaintapp/qtcdevcpq-sandbox/blob/feature/github-actions-runner/.github/workflows/playwright.yml**

---

## Running Locally (optional, for development)

Before pushing, run your test on your own machine against mock:

```bash
# Prerequisites: sf CLI authenticated, node installed
export QTC_SF_ORG=qtcmock    # or qtcuat
npx playwright test tests/e2e/yourSuiteName.spec.js
```

This runs **headed** (browser visible) so you can watch it step through. `CI=true` is not set locally, so the browser opens in a window.

To run headed but with the Chromium window: just omit `CI=true`. The `playwright.config.js` controls this:
```js
headless: !!process.env.CI,   // false locally = browser opens; true on GitHub = headless
```

---

## Writing Good Specs — Practical Tips

**Authentication** — always use `loginViaCookie`, never hardcode credentials:
```js
const { instanceUrl, lightningUrl, accessToken } = getSfCredentials();
await loginViaCookie(page, instanceUrl, accessToken);
```

**Waiting** — Salesforce Lightning is async. Prefer waiting for elements over fixed timeouts:
```js
// Good
await page.getByText('Save').waitFor({ state: 'visible', timeout: 30_000 });

// Avoid
await page.waitForTimeout(5000);  // fragile
```

**Screenshots** — name them sequentially so they sort correctly in the dashboard:
```js
await page.screenshot({ path: `${RUN_DIR}/01-before-edit.png` });
await page.screenshot({ path: `${RUN_DIR}/02-after-save.png` });
```

**Rich results JSON** — if your test collects structured data (DB values, metrics, cross-checks), write it to `${RUN_DIR}/results.json`. The upload script automatically picks it up and sends it to Salesforce, populating the UI↔DB, DB Lines, and Metrics tabs:
```js
const RUN_DIR = path.join(__dirname, 'results', 'runs', new Date().toISOString().replace(/[:.]/g, '-'));
fs.mkdirSync(RUN_DIR, { recursive: true });
fs.writeFileSync(path.join(RUN_DIR, 'results.json'), JSON.stringify({
    quoteName: 'Q-12345',
    lineResults: [...],
    uiDbCrossCheck: [...],
    dbAnomalies: [...],
    // ... whatever your test collects
}));
```

Look at `agenticQtcQuantityIncrease.spec.js` for a complete example of the results JSON schema.

**Timeouts** — the global test timeout is 5 minutes (`playwright.config.js`). For long flows, break into multiple `test()` blocks or bump a specific test's timeout:
```js
test('long flow', async ({ page }) => {
    test.setTimeout(480_000);  // 8 minutes for this test only
    // ...
});
```

---

## Secrets & Credentials

Never commit credentials. The GitHub Actions runner authenticates via repository secrets set by the org admin:

| Secret | What it is | Who manages it |
|---|---|---|
| `SF_SFDX_AUTH_URL` | SFDX auth URL for **mock** org | Repo admin (GitHub Settings → Secrets) |
| `SF_SFDX_AUTH_URL_UAT` | SFDX auth URL for **UAT** org | Repo admin (GitHub Settings → Secrets) |

The GitHub Personal Access Token (PAT) that lets Salesforce trigger Actions is stored in Salesforce Custom Metadata:
**Setup → Custom Metadata Types → GitHub Actions Config → Manage Records → Default**

---

## Quick Reference

| Task | Where |
|---|---|
| Add a test spec | `tests/e2e/yourSuiteName.spec.js` |
| Register suite name | `.github/workflows/playwright.yml` (case block) |
| Add to LWC dropdown | `agenticQtcTestDashboard.js` → `SUITE_OPTIONS` |
| Deploy LWC change | `sf project deploy start --source-dir force-app/main/default/lwc/agenticQtcTestDashboard --target-org qtcmock` |
| See all CI runs | https://github.com/chanduvadlapatlaintapp/qtcdevcpq-sandbox/actions/workflows/playwright.yml |
| View results in mock | https://intapp--qtcmock.sandbox.lightning.force.com/lightning/n/QTC_Test_Runner |
| View results in UAT | https://intapp--uat.sandbox.lightning.force.com/lightning/n/QTC_Test_Runner |
