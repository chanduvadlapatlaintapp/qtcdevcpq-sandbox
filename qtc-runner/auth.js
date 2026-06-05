/**
 * auth.js  —  Reads Salesforce credentials from the local `sf` CLI.
 *
 * Requirements:
 *   • `sf` (Salesforce CLI) must be installed and authenticated.
 *   • The target org alias defaults to "qtcmock" but can be overridden
 *     via the QTC_SF_ORG environment variable.
 */

'use strict';

const { execSync } = require('child_process');
const path         = require('path');
const os           = require('os');

// ─── Constants ───────────────────────────────────────────────────────────

const SF_ORG_ALIAS = process.env.QTC_SF_ORG || 'qtcmock';
const SF_API_VER   = process.env.QTC_SF_API_VERSION || '62.0';

// ─── Locate the `sf` binary ───────────────────────────────────────────────

function findSfCli() {
    // 1. Honour explicit env override
    if (process.env.SF_CLI_PATH) return process.env.SF_CLI_PATH;

    // 2. Try PATH first
    try {
        const p = execSync('which sf', { stdio: ['pipe','pipe','pipe'] }).toString().trim();
        if (p) return p;
    } catch (_) {}

    // 3. Common install locations
    const candidates = [
        '/usr/local/bin/sf',
        '/usr/bin/sf',
        path.join(os.homedir(), '.local', 'bin', 'sf'),
        path.join(os.homedir(), 'AppData', 'Local', 'sf', 'bin', 'sf.cmd'), // Windows
        'C:\\Program Files\\sf\\bin\\sf.cmd',
    ];
    for (const c of candidates) {
        try {
            execSync(`"${c}" --version`, { stdio: 'pipe' });
            return c;
        } catch (_) {}
    }

    throw new Error('`sf` CLI not found. Install from https://developer.salesforce.com/tools/salesforcecli');
}

// ─── Public API ──────────────────────────────────────────────────────────

let _cached = null;

/**
 * Clears the cached credentials so the next getSfCredentials() call re-runs
 * `sf org display` and picks up a fresh access token. Call this after a 401
 * from any REST request — Salesforce session tokens expire (~2 hours), and
 * without this the agent's REST writes silently fail forever after expiry.
 */
function refreshCredentials() {
    _cached = null;
}

/**
 * Returns { instanceUrl, accessToken, apiBase } for the target org.
 * Result is cached until refreshCredentials() is called.
 */
function getSfCredentials() {
    if (_cached) return _cached;

    const sf  = findSfCli();

    // instanceUrl comes from `org display` — it is not a secret and is never
    // redacted, so this call stays as-is.
    const raw = execSync(`"${sf}" org display --target-org ${SF_ORG_ALIAS} --json`, {
        stdio: ['pipe', 'pipe', 'pipe'],
    }).toString();

    const parsed = JSON.parse(raw);
    if (parsed.status !== 0) {
        throw new Error(`sf org display failed: ${JSON.stringify(parsed.message)}`);
    }

    const result      = parsed.result;
    const instanceUrl = result.instanceUrl.replace(/\/$/, '');

    // The access token must NOT be read from `org display --json`: modern
    // Salesforce CLI redacts secrets there, returning the literal placeholder
    // "[REDACTED] Use 'sf org auth show-access-token' to view". That string is
    // truthy, so the old `result.accessToken` guard passed and we sent
    // `Authorization: Bearer [REDACTED] …` — which Salesforce rejects with a
    // 401 INVALID_AUTH_HEADER. Use the dedicated, unredacted command instead.
    const tokRaw = execSync(`"${sf}" org auth show-access-token --target-org ${SF_ORG_ALIAS} --json`, {
        stdio: ['pipe', 'pipe', 'pipe'],
    }).toString();

    const tokParsed = JSON.parse(tokRaw);
    if (tokParsed.status !== 0) {
        throw new Error(`sf org auth show-access-token failed: ${JSON.stringify(tokParsed.message)}`);
    }

    const accessToken = tokParsed.result && tokParsed.result.accessToken;

    if (!accessToken || /REDACTED/.test(accessToken)) {
        throw new Error(
            `No usable access token for org "${SF_ORG_ALIAS}". Run: sf org login web --target-org ${SF_ORG_ALIAS}`
        );
    }

    _cached = {
        instanceUrl,
        accessToken,
        apiBase: `${instanceUrl}/services/data/v${SF_API_VER}`,
    };
    return _cached;
}

/**
 * Returns a standard Authorization header object.
 */
function authHeader() {
    const { accessToken } = getSfCredentials();
    return { Authorization: `Bearer ${accessToken}` };
}

module.exports = { getSfCredentials, refreshCredentials, authHeader, SF_ORG_ALIAS };