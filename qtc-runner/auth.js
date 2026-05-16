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

// ─── Constants ──────────────────────────────────────────────────────────────

const SF_ORG_ALIAS = process.env.QTC_SF_ORG || 'qtcmock';
const SF_API_VER   = process.env.QTC_SF_API_VERSION || '62.0';

// ─── Locate the `sf` binary ──────────────────────────────────────────────────

function findSfCli() {
    // 1. Honour explicit env override
    if (process.env.SF_CLI_PATH) return process.env.SF_CLI_PATH;

    // 2. Try PATH first
    try {
        const p = execSync('which sf', { stdio: ['pipe','pipe','pipe'] })
            .toString().trim();
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

    throw new Error(
        '`sf` CLI not found. Install from https://developer.salesforce.com/tools/salesforcecli'
    );
}

// ─── Public API ──────────────────────────────────────────────────────────────

let _cached = null;

/**
 * Returns { instanceUrl, accessToken, apiBase } for the target org.
 * Result is cached for the lifetime of the process (token is session-scoped).
 */
function getSfCredentials() {
    if (_cached) return _cached;

    const sf  = findSfCli();
    const raw = execSync(`"${sf}" org display --target-org ${SF_ORG_ALIAS} --json`, {
        stdio: ['pipe', 'pipe', 'pipe'],
    }).toString();

    const parsed = JSON.parse(raw);
    if (parsed.status !== 0) {
        throw new Error(`sf org display failed: ${JSON.stringify(parsed.message)}`);
    }

    const result      = parsed.result;
    const instanceUrl = result.instanceUrl.replace(/\/$/, '');
    const accessToken = result.accessToken;

    if (!accessToken) {
        throw new Error(
            `No access token found for org "${SF_ORG_ALIAS}". ` +
            `Run: sf org login web --target-org ${SF_ORG_ALIAS}`
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

module.exports = { getSfCredentials, authHeader, SF_ORG_ALIAS };
