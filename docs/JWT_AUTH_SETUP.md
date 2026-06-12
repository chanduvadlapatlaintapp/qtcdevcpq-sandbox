# Salesforce JWT Authentication — GitHub Actions Runner

**Purpose:** Document everything done to fix the Salesforce authentication / token
problem in the QTC Playwright GitHub Actions runner, and to make the setup
self-service for any future org.

---

## 1. The problem we were solving

The original runner authenticated to Salesforce using **SFDX auth URLs** stored as
GitHub Secrets (`SF_SFDX_AUTH_URL`, `SF_SFDX_AUTH_URL_UAT`). Those URLs embed an
**OAuth refresh token**.

Symptoms:

- Refresh tokens **expired or were revoked** (session-settings timeout, password
  reset, admin revoke, "Block OAuth" policies, sandbox refresh).
- When the token died, the workflow could authenticate-but-not-really: runs got
  **stuck at `CLAIMED`/`RUNNING` indefinitely** or failed at the first Salesforce
  call, and the `Test_Run__c` record never moved to a terminal state.
- Every breakage required a human to **regenerate and re-paste the auth URL** —
  manual token rotation that kept recurring.

**Root cause:** refresh tokens are inherently expirable/revocable credentials, so
any CI that depends on them needs babysitting.

---

## 2. The fix — JWT Bearer Flow

We migrated CI authentication to the **OAuth 2.0 JWT Bearer Flow**:

- Authentication is done with an **RSA private key** signing a JWT, exchanged for a
  short-lived access token at run time.
- The **private key never expires** — no refresh token, no manual rotation.
- The matching **certificate** is uploaded to an **External Client App** in each org
  ("Use digital signatures"), which authorizes the key.

To avoid adding a new pair of secrets every time an org is onboarded, **all
org-specific configuration lives in a single JSON secret**. Adding a new org is a
JSON edit — usually **zero workflow changes**.

> Terminology: we use a Salesforce **External Client App (ECA)** as the OAuth app
> for the JWT flow — the modern replacement for the classic Connected App.

---

## 3. GitHub Secrets (two, forever, for all orgs)

| Secret | Holds | Sensitive? |
|---|---|---|
| `SF_JWT_PRIVATE_KEY` | Contents of `server.key` — **one key shared across all orgs** (same cert uploaded to each org's External Client App) | **Yes** — never log/print/commit |
| `SF_JWT_ORG_CONFIG` | JSON mapping each org key → External Client App details (clientId / username / instanceUrl) | Low (client IDs + usernames are not secret) |

### `SF_JWT_ORG_CONFIG` structure

```json
{
  "qtcmock": {
    "clientId": "<Consumer Key from qtcmock External Client App>",
    "username": "vaibhav.kumar@intapp.com.qtcmock",
    "instanceUrl": "https://intapp--qtcmock.sandbox.my.salesforce.com"
  },
  "uat": {
    "clientId": "<Consumer Key from UAT External Client App>",
    "username": "vaibhav.kumar@intapp.com.uat",
    "instanceUrl": "https://intapp--uat.sandbox.my.salesforce.com"
  }
}
```

Both live in the repo's **Settings → Secrets and variables → Actions → Secrets**.

---

## 4. One-time setup

### 4.1 Generate the RSA key pair (once, shared by all orgs)

```bash
# Private key (→ SF_JWT_PRIVATE_KEY secret)
openssl genrsa -out server.key 2048
# Self-signed cert valid 10 years (→ uploaded to each External Client App)
openssl req -x509 -new -nodes -key server.key -sha256 -days 3650 -out server.crt \
  -subj "/CN=qtc-ci"
```

- `server.key` → paste the **full contents** into the `SF_JWT_PRIVATE_KEY` secret.
- `server.crt` → upload to each org's External Client App (next step).
- **Never commit either file.** Locally the key lives at `~/Desktop/server.key`.

### 4.2 Create the External Client App in each org

We use an **External Client App (ECA)** — Salesforce's newer replacement for the
classic Connected App — for the JWT integration. The JWT-relevant settings are the
same (OAuth, digital signature/cert, consumer key, pre-authorization), but ECA
splits the **app definition** from its **policies**.

In each org (e.g. `https://intapp--qtcmock.sandbox.my.salesforce.com`):

1. **Setup → External Client App Manager → New External Client App**.
2. Fill in name / contact email. Under **API (Enable OAuth Settings)**:
   - **Enable OAuth**.
   - Callback URL: `https://login.salesforce.com/services/oauth2/callback`.
   - OAuth scopes: **Manage user data via APIs (api)** and **Perform requests at any time (refresh_token, offline_access)**.
   - Enable **Use digital signatures** and upload **`server.crt`** (this is what authorizes the JWT private key).
3. **Save / Create.** Wait 2–10 min for propagation.
4. Open the app → **Settings → OAuth Settings → Consumer Key and Secret** → copy the **Consumer Key** → this is the org's `clientId` in `SF_JWT_ORG_CONFIG`.
5. **Policies** tab → **OAuth Policies** → set **Permitted Users = "Admin approved users are pre-authorized"** (JWT requires pre-authorization). Make sure the JWT/`client_credentials`-style flow is enabled in the policies if your org gates flow enablement.
6. Pre-authorize the integration/runner user (e.g. `vaibhav.kumar@intapp.com.qtcmock`) by assigning the app via a **Profile or Permission Set** in the app's Policies.

> Same `server.crt` is uploaded to the External Client App in **every** org, so a
> single private key (`SF_JWT_PRIVATE_KEY`) works everywhere.

> **Note:** ECAs may require **"Allow creation of External Client Apps"** to be
> enabled in **Setup → External Client App Settings** before you can create one.

### 4.3 Add the GitHub Secrets

In `chanduvadlapatlaintapp/qtcdevcpq-sandbox` → **Settings → Secrets → Actions**:

1. `SF_JWT_PRIVATE_KEY` — full contents of `server.key`.
2. `SF_JWT_ORG_CONFIG` — the JSON from §3 (start with `qtcmock`; add `uat` when ready).

---

## 5. Workflow change — `.github/workflows/playwright.yml` (Step 6)

The auth step picks the org key from the instance URL, pulls that org's config out
of the JSON secret with a Node one-liner, writes the private key to a temp file,
runs `sf org login jwt`, then deletes the key file.

```yaml
- name: Authenticate to Salesforce
  id: sf-auth
  run: |
    INSTANCE_URL="${{ inputs.sf_instance_url }}"
    if [[ "$INSTANCE_URL" == *"uat"* ]]; then
      ORG_KEY="uat";     ORG_ALIAS="qtcuat"
    else
      ORG_KEY="qtcmock"; ORG_ALIAS="qtcmock"
    fi

    # Extract this org's credentials from the JSON config (Node is already installed)
    CLIENT_ID=$(ORG_KEY="$ORG_KEY" node -p \
      "const c=JSON.parse(process.env.SF_JWT_ORG_CONFIG); \
       const o=c[process.env.ORG_KEY]; \
       if(!o){process.stderr.write('No JWT config for org: '+process.env.ORG_KEY+'\n');process.exit(1);} \
       o.clientId")
    USERNAME=$(ORG_KEY="$ORG_KEY" node -p \
      "JSON.parse(process.env.SF_JWT_ORG_CONFIG)[process.env.ORG_KEY].username")
    INSTANCE=$(ORG_KEY="$ORG_KEY" node -p \
      "JSON.parse(process.env.SF_JWT_ORG_CONFIG)[process.env.ORG_KEY].instanceUrl")

    printf '%s' "$SF_JWT_PRIVATE_KEY" > /tmp/server.key
    sf org login jwt \
      --client-id    "$CLIENT_ID" \
      --jwt-key-file /tmp/server.key \
      --username     "$USERNAME" \
      --instance-url "$INSTANCE" \
      --alias        "$ORG_ALIAS" \
      --set-default
    rm -f /tmp/server.key

    echo "org_alias=$ORG_ALIAS" >> $GITHUB_OUTPUT
    echo "Authenticated to: $INSTANCE_URL (alias: $ORG_ALIAS)"
  env:
    SF_JWT_PRIVATE_KEY: ${{ secrets.SF_JWT_PRIVATE_KEY }}
    SF_JWT_ORG_CONFIG:  ${{ secrets.SF_JWT_ORG_CONFIG }}
```

Key points:

- **Org routing** is by instance URL substring (`*uat*` → `uat`, else `qtcmock`).
  The resolved `org_alias` is exported as a step output and threaded to every later
  step via `QTC_SF_ORG`, so scripts and Playwright auth use the right org.
- **Missing-org guard:** if the JSON has no entry for the resolved key, the Node
  one-liner prints a clear error and exits non-zero (fail fast instead of a
  confusing downstream auth error).
- The private key is written to `/tmp/server.key` only for the duration of the
  login and **deleted immediately after**.

---

## 6. Downstream token use (the runtime/browser side)

Authenticating the CLI is step one; the Playwright specs and the result-upload
scripts also need a usable token. Two fixes landed here so the JWT session works
end-to-end:

1. **Access token via `org auth show-access-token`**
   ([`tests/e2e/helpers/sfAuth.js`](../tests/e2e/helpers/sfAuth.js), and the
   `qtc-runner` scripts). `getSfCredentials()` runs
   `sf org auth show-access-token --target-org <QTC_SF_ORG> --json` to get a **real,
   unredacted** access token for REST calls. It also guards against the redacted
   `"<REDACTED — run ...>"` placeholder so a bad token fails loudly instead of
   silently 401-ing.

2. **Browser login via a properly-signed frontdoor URL**
   (`loginViaCookie`). A raw JWT access token can't be used directly as a
   frontdoor `sid`, so we call `sf org open --url-only --target-org <org> --path /`
   and extract the signed `…/secur/frontdoor.jsp?…` URL from its output, then
   navigate Playwright to it. There's a manual-construction fallback if
   `sf org open` fails. (Commits: `8a68849`, `aff9ff1`.)

3. **Org alias plumbing** — every script reads `QTC_SF_ORG` (default `qtcmock`) so
   the same code authenticates against whichever org the run targeted. (Commits:
   `90e6d89`, `292b307`.)

---

## 7. Security constraints (must always hold)

- `SF_JWT_PRIVATE_KEY` must **never** be logged, printed, or committed.
- `server.key` lives at `~/Desktop/server.key` locally and is **never committed**.
- `SF_JWT_PRIVATE_KEY` / `SF_JWT_ORG_CONFIG` must **not** be echoed in workflow logs.
- `sf org open --url-only` frontdoor URLs (which contain a one-time `sid`) must
  **not** be stored in env vars that surface in logs.
- The PAT in `GitHub_Actions_Config__mdt` must **not** be touched during metadata
  deploys (use nil-preserving deploys).

---

## 8. Adding a new org later (zero/near-zero workflow changes)

1. Create an External Client App in the new org and upload the **same** `server.crt` (§4.2).
2. Add a new entry to the `SF_JWT_ORG_CONFIG` secret:
   ```json
   "prod": {
     "clientId": "...",
     "username": "service@intapp.com",
     "instanceUrl": "https://intapp.my.salesforce.com"
   }
   ```
3. Only if the new org isn't matched by the existing URL routing, add one `elif` to
   the `ORG_KEY` detection block in Step 6 (e.g. `*prod*` → `prod`).

---

## 9. Verification

Local smoke test after the External Client App is created:

```bash
export PATH="$HOME/.local/node-v20.12.2-darwin-arm64/bin:$PATH"
sf org login jwt \
  --client-id    <CONSUMER_KEY> \
  --jwt-key-file ~/Desktop/server.key \
  --username     vaibhav.kumar@intapp.com.qtcmock \
  --instance-url https://intapp--qtcmock.sandbox.my.salesforce.com \
  --alias        jwt-test-mock
sf org display --target-org jwt-test-mock
```

In CI:

1. Add the two secrets, trigger a run from the LWC dashboard ("Run on GitHub").
2. Step 6 logs: `Authenticated to: https://intapp--qtcmock... (alias: qtcmock)`.
3. The run progresses **CLAIMED → RUNNING → PASSED/FAILED** — never stuck.
4. Once confirmed, delete the legacy `SF_SFDX_AUTH_URL*` secrets.

---

## 10. Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `invalid_grant - user hasn't approved this consumer` | External Client App OAuth Policy not set to "Admin approved users are pre-authorized", or the runner user isn't pre-authorized (Profile/Permission Set). |
| `invalid_grant - invalid assertion` | Cert/key mismatch — the uploaded `server.crt` doesn't match `SF_JWT_PRIVATE_KEY`, or the Consumer Key in the JSON is wrong/stale. |
| `No JWT config for org: <key>` | The resolved org key has no entry in `SF_JWT_ORG_CONFIG`. Add it. |
| Auth succeeds but REST calls 401 | Token came back redacted — ensure `org auth show-access-token` is used (§6) and `QTC_SF_ORG` is set. |
| Can't create the app / option missing | Enable **"Allow creation of External Client Apps"** in Setup → External Client App Settings. |
| External Client App just created, login fails | Wait 2–10 min for propagation after upload, then retry. |

---

## 11. Files involved

| File | Role |
|---|---|
| `.github/workflows/playwright.yml` (Step 6) | JWT login + org routing |
| `tests/e2e/helpers/sfAuth.js` | Runtime token retrieval + frontdoor browser login |
| `qtc-runner/*.js` | Local agent scripts — same `QTC_SF_ORG` + token handling |
| `SF_JWT_PRIVATE_KEY` (GitHub Secret) | RSA private key |
| `SF_JWT_ORG_CONFIG` (GitHub Secret) | Per-org External Client App config JSON |
