#!/usr/bin/env node
/**
 * .github/scripts/create-run.js
 *
 * Creates a Test_Run__c record in Salesforce for GitHub-initiated runs
 * (push to main, PR merge, scheduled). When Salesforce triggers the run via
 * the LWC, the record already exists — this script is only needed when
 * GitHub is the originator.
 *
 * Usage:
 *   node create-run.js <testSuite> <eventName> <sha>
 *
 * Writes to GITHUB_OUTPUT:
 *   test_run_id=<salesforce record id>
 *   test_suite=<testSuite>
 *
 * Uses qtc-runner/auth.js for credentials (SF CLI must be authenticated before calling this).
 */

'use strict';

const https   = require('https');
const http    = require('http');
const path    = require('path');
const fs      = require('fs');
const { URL } = require('url');

const { getSfCredentials } = require(path.join(__dirname, '../../qtc-runner/auth.js'));

const SF_API_VER = process.env.QTC_SF_API_VERSION || '62.0';

// ── Args ──────────────────────────────────────────────────────────────────────

const [,, testSuite = 'agenticQtcQuantityIncrease', eventName = 'unknown', sha = ''] = process.argv;

// ── REST helper ───────────────────────────────────────────────────────────────

async function sfPost(urlPath, body) {
    const { instanceUrl, accessToken } = getSfCredentials();
    const url     = new URL(urlPath, instanceUrl);
    const bodyStr = JSON.stringify(body);

    return new Promise((resolve, reject) => {
        const options = {
            hostname: url.hostname,
            path:     url.pathname + url.search,
            method:   'POST',
            headers: {
                Authorization:    `Bearer ${accessToken}`,
                'Content-Type':   'application/json',
                'Content-Length': Buffer.byteLength(bodyStr),
            },
        };
        const proto = url.protocol === 'https:' ? https : http;
        const req = proto.request(options, res => {
            let data = '';
            res.on('data', c => { data += c; });
            res.on('end', () => {
                if (res.statusCode >= 400) {
                    reject(new Error(`POST ${urlPath} → ${res.statusCode}: ${data}`));
                } else {
                    resolve(JSON.parse(data));
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
    // Build a descriptive agent ID so the LWC can show the trigger source
    const shortSha   = sha ? sha.slice(0, 7) : '';
    const agentId    = shortSha
        ? `github-actions:${eventName}:${shortSha}`
        : `github-actions:${eventName}`;

    console.error(`[create-run] Creating Test_Run__c — suite=${testSuite}, event=${eventName}, sha=${shortSha}`);

    const result = await sfPost(`/services/data/v${SF_API_VER}/sobjects/Test_Run__c`, {
        Test_Suite__c   : testSuite,
        Status__c       : 'CLAIMED',          // prevents local agent from picking it up
        Agent_Id__c     : agentId,
    });

    if (!result.id) {
        throw new Error(`Unexpected SF response: ${JSON.stringify(result)}`);
    }

    const runId = result.id;
    console.error(`[create-run] Created Test_Run__c: ${runId}`);

    // Write to GITHUB_OUTPUT so subsequent steps can read the ID
    const outputFile = process.env.GITHUB_OUTPUT;
    if (outputFile) {
        fs.appendFileSync(outputFile, `test_run_id=${runId}\n`);
        fs.appendFileSync(outputFile, `test_suite=${testSuite}\n`);
    } else {
        // Fallback: print to stdout for manual testing
        console.log(`test_run_id=${runId}`);
        console.log(`test_suite=${testSuite}`);
    }
}

main().catch(err => {
    console.error('[create-run] Fatal:', err.message);
    process.exit(1);
});
