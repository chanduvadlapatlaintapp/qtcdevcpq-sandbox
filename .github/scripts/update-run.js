#!/usr/bin/env node
/**
 * .github/scripts/update-run.js
 *
 * Patches a Test_Run__c record's status in Salesforce.
 *
 * Usage:
 *   node update-run.js <testRunId> <status>
 *
 * Status values: RUNNING, PASSED, FAILED, ERROR
 *
 * Uses qtc-runner/auth.js for credentials (relies on SF CLI being authenticated
 * via `sf org login sfdx-url --alias qtcmock` earlier in the workflow).
 */

'use strict';

const https  = require('https');
const http   = require('http');
const path   = require('path');
const { URL } = require('url');

// Resolve qtc-runner auth relative to this script
const { getSfCredentials } = require(path.join(__dirname, '../../qtc-runner/auth.js'));

const SF_API_VER = process.env.QTC_SF_API_VERSION || '62.0';

// ── Args ─────────────────────────────────────────────────────────────────────

const [,, testRunId, status] = process.argv;

if (!testRunId || !status) {
    console.error('Usage: node update-run.js <testRunId> <status>');
    process.exit(1);
}

// ── REST helper ───────────────────────────────────────────────────────────────

async function sfPatch(urlPath, body) {
    const { instanceUrl, accessToken } = getSfCredentials();
    const url     = new URL(urlPath, instanceUrl);
    const bodyStr = JSON.stringify(body);

    return new Promise((resolve, reject) => {
        const options = {
            hostname: url.hostname,
            path:     url.pathname + url.search,
            method:   'PATCH',
            headers: {
                Authorization:   `Bearer ${accessToken}`,
                'Content-Type':  'application/json',
                'Content-Length': Buffer.byteLength(bodyStr),
            },
        };
        const proto = url.protocol === 'https:' ? https : http;
        const req = proto.request(options, res => {
            let data = '';
            res.on('data', c => { data += c; });
            res.on('end', () => {
                if (res.statusCode >= 400) {
                    reject(new Error(`PATCH ${urlPath} → ${res.statusCode}: ${data}`));
                } else {
                    resolve(data ? JSON.parse(data) : null);
                }
            });
        });
        req.on('error', reject);
        req.write(bodyStr);
        req.end();
    });
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
    const now  = new Date().toISOString();
    const body = { Status__c: status };

    if (status === 'RUNNING') {
        body.Started_At__c = now;
        body.Agent_Last_Heartbeat__c = now;
    } else {
        body.Completed_At__c = now;
    }

    const urlPath = `/services/data/v${SF_API_VER}/sobjects/Test_Run__c/${testRunId}`;
    console.log(`[update-run] Patching ${testRunId} → ${status}`);

    try {
        await sfPatch(urlPath, body);
    } catch (err) {
        // If the PATCH failed due to missing optional fields (e.g. org missing
        // Started_At__c / Completed_At__c), fall back to updating Status only.
        if (err.message && err.message.includes('INVALID_FIELD')) {
            console.warn('[update-run] Optional fields missing, retrying with Status__c only');
            await sfPatch(urlPath, { Status__c: status });
        } else {
            throw err;
        }
    }

    console.log(`[update-run] Done.`);
}

main().catch(err => {
    console.error('[update-run] Error:', err.message);
    process.exit(1);
});
