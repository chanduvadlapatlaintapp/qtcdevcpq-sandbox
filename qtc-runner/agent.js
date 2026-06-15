#!/usr/bin/env node
/**
 * agent.js  —  The qtc-runner local agent.
 *
 * Loop:
 *   1. Poll Salesforce every 3 s for Test_Run__c records with Status = PENDING.
 *   2. Claim one record (PENDING → CLAIMED) via a conditional PATCH.
 *   3. Set status to RUNNING and launch Playwright.
 *   4. Upload results, screenshots, and video back to Salesforce.
 *   5. Set final status to PASSED / FAILED / ERROR.
 *
 * Nothing external is required — just:
 *   • `sf` CLI authenticated to the target org
 *   • Node.js ≥ 18
 *   • `npm install` run inside this directory (for node-fetch / form-data)
 *   • Playwright + dependencies in the parent project
 */

'use strict';

const https             = require('https');
const http              = require('http');
const { URL }           = require('url');
const os                = require('os');

const { getSfCredentials, refreshCredentials } = require('./auth');
const { runSuite }         = require('./runner');
const { uploadFile, insertTestResults, patchTestRun } = require('./uploader');

// ─── Config ──────────────────────────────────────────────────────────────

const POLL_INTERVAL_MS = parseInt(process.env.QTC_POLL_INTERVAL || '3000', 10);
const AGENT_ID         = `${os.hostname()}-${process.pid}`;
const SF_API_VER       = process.env.QTC_SF_API_VERSION || '62.0';

// ─── Helpers ─────────────────────────────────────────────────────────────

function log(msg) {
    console.log(`[${new Date().toISOString()}] ${msg}`);
}

async function sfGet(path, _retried = false) {
    const { instanceUrl, accessToken } = getSfCredentials();
    const url = new URL(path, instanceUrl);

    return new Promise((resolve, reject) => {
        const options = {
            hostname : url.hostname,
            path     : url.pathname + url.search,
            method   : 'GET',
            headers  : { Authorization: `Bearer ${accessToken}` },
        };
        const proto = url.protocol === 'https:' ? https : http;
        const req = proto.request(options, res => {
            let data = '';
            res.on('data', c => { data += c; });
            res.on('end', () => {
                // Salesforce session token expired (~2hr) — refresh and retry once.
                if (res.statusCode === 401 && !_retried) {
                    log(`Got 401 on GET ${path}; refreshing SF credentials and retrying once.`);
                    refreshCredentials();
                    sfGet(path, true).then(resolve, reject);
                    return;
                }
                if (res.statusCode >= 400) {
                    reject(new Error(`GET ${path} → ${res.statusCode}: ${data}`));
                } else {
                    resolve(JSON.parse(data));
                }
            });
        });
        req.on('error', reject);
        req.end();
    });
}

async function sfPatch(path, body, _retried = false) {
    const { instanceUrl, accessToken } = getSfCredentials();
    const url     = new URL(path, instanceUrl);
    const bodyStr = JSON.stringify(body);
    return new Promise((resolve, reject) => {
        const options = {
            hostname : url.hostname,
            path     : url.pathname + url.search,
            method   : 'PATCH',
            headers  : {
                Authorization   : `Bearer ${accessToken}`,
                'Content-Type'  : 'application/json',
                'Content-Length': Buffer.byteLength(bodyStr),
            },
        };
        const proto = url.protocol === 'https:' ? https : http;
        const req = proto.request(options, res => {
            let data = '';
            res.on('data', c => { data += c; });
            res.on('end', () => {
                // Salesforce session token expired (~2hr) — refresh and retry once.
                if (res.statusCode === 401 && !_retried) {
                    log(`Got 401 on PATCH ${path}; refreshing SF credentials and retrying once.`);
                    refreshCredentials();
                    sfPatch(path, body, true).then(resolve, reject);
                    return;
                }
                if (res.statusCode >= 400) {
                    reject(new Error(`PATCH ${path} → ${res.statusCode}: ${data}`));
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

// ─── Core loop ────────────────────────────────────────────────────────────

async function pollOnce() {
    const { apiBase } = getSfCredentials();

    // Query for the oldest PENDING run
    const query = encodeURIComponent(
        `SELECT Id, Name, Test_Suite__c, Account_Name__c, Contract__c, Contract_Number__c, Quote_Name__c FROM Test_Run__c ` +
        `WHERE Status__c = 'PENDING' ORDER BY CreatedDate ASC LIMIT 1`
    );
    const result = await sfGet(`/services/data/v${SF_API_VER}/query?q=${query}`);

    if (!result.records || result.records.length === 0) return; // nothing to do

    const run = result.records[0];
    log(`Found PENDING run: ${run.Name} (${run.Id}) suite="${run.Test_Suite__c}"` +
        (run.Account_Name__c ? ` account="${run.Account_Name__c}"` : ''));

    // ── Step 1: Claim the run (PENDING → CLAIMED) ────────────────────────
    // Two agents running simultaneously both see the record as PENDING.
    // We PATCH and re-query to confirm we own it (cheap and reliable).
    try {
        await sfPatch(
            `/services/data/v${SF_API_VER}/sobjects/Test_Run__c/${run.Id}`,
            { Status__c: 'CLAIMED', Agent_Id__c: AGENT_ID }
        );
    } catch (e) {
        log(`Could not claim run ${run.Id}: ${e.message}`);
        return;
    }

    // Re-read to confirm we won the claim race
    const verify = await sfGet(
        `/services/data/v${SF_API_VER}/sobjects/Test_Run__c/${run.Id}` +
        `?fields=Status__c,Agent_Id__c`
    );
    if (verify.Agent_Id__c !== AGENT_ID) {
        log(`Run ${run.Id} was claimed by another agent (${verify.Agent_Id__c}). Skipping.`);
        return;
    }

    // ── Step 2: Set RUNNING ──────────────────────────────────────────────
    await sfPatch(
        `/services/data/v${SF_API_VER}/sobjects/Test_Run__c/${run.Id}`,
        {
            Status__c                : 'RUNNING',
            Started_At__c            : new Date().toISOString(),
            Agent_Last_Heartbeat__c  : new Date().toISOString(),
        }
    );
    log(`Claimed and set RUNNING: ${run.Id}`);

    // ── Step 3: Run Playwright ───────────────────────────────────────────
    let playwrightResult;
    try {
        playwrightResult = await runSuite(run.Test_Suite__c, run.Id, run.Account_Name__c, run.Contract__c, run.Contract_Number__c, run.Quote_Name__c);
    } catch (e) {
        playwrightResult = {
            status       : 'ERROR',
            passed       : 0,
            failed       : 0,
            durationMs   : 0,
            logOutput    : '',
            errorMessage : `Runner threw: ${e.message}`,
            tests        : [],
            screenshots  : [],
            videoPath    : null,
        };
    }

    log(`Playwright finished: ${playwrightResult.status} (${playwrightResult.passed}✓ ${playwrightResult.failed}✗ ${playwrightResult.durationMs}ms)`);

    // ── Step 4: Upload Test_Result__c records ────────────────────────────
    if (playwrightResult.tests.length > 0) {
        try {
            await insertTestResults(run.Id, playwrightResult.tests);
        } catch (e) {
            log(`Warning: could not insert Test_Result__c records: ${e.message}`);
        }
    }

    // ── Step 5: Upload screenshots ───────────────────────────────────────
    for (const screenshotPath of playwrightResult.screenshots) {
        try {
            const title = require('path').basename(screenshotPath);
            await uploadFile(screenshotPath, title, run.Id);
        } catch (e) {
            log(`Warning: screenshot upload failed (${screenshotPath}): ${e.message}`);
        }
    }

    // ── Step 6: Upload video ─────────────────────────────────────────────
    if (playwrightResult.videoPath) {
        try {
            await uploadFile(playwrightResult.videoPath, `video-${run.Name}.webm`, run.Id);
        } catch (e) {
            log(`Warning: video upload failed: ${e.message}`);
        }
    }

    // ── Step 6.5: Upload rich-results.json ───────────────────────────────
    // The dashboard's UI↔DB / DB Lines / Anomalies / Metrics tabs are
    // populated by parsing a ContentDocumentLink whose title is exactly
    // 'rich-results.json' (see agenticQtcTestDashboard.js _loadRunFiles).
    // Without this upload those tabs stay empty even when the spec wrote
    // a valid results.json under tests/e2e/results/runs/<ts>/.
    if (playwrightResult.richResultsPath) {
        try {
            await uploadFile(playwrightResult.richResultsPath, 'rich-results.json', run.Id);
        } catch (e) {
            log(`Warning: rich-results.json upload failed: ${e.message}`);
        }
    }

    // ── Step 7: Finalise the Test_Run__c record ──────────────────────────
    // Wrap in try/catch so a final-patch failure (e.g. transient SF outage
    // even after the 401-retry) is loud in the agent log instead of just
    // bubbling up to the loop's generic "Poll error" catch — which would
    // leave the dashboard stuck on RUNNING with no indication of why.
    try {
        await patchTestRun(run.Id, {
            status       : playwrightResult.status,
            passed       : playwrightResult.passed,
            failed       : playwrightResult.failed,
            durationMs   : playwrightResult.durationMs,
            errorMessage : playwrightResult.errorMessage,
            logOutput    : playwrightResult.logOutput,
            completedAt  : new Date().toISOString(),
        });
        log(`Run ${run.Id} complete → ${playwrightResult.status}`);
    } catch (e) {
        log(`ERROR: final patchTestRun for ${run.Id} failed — dashboard will stay on RUNNING. Cause: ${e.message}`);
        // Last-ditch: try once more with only the status field so at least the
        // dashboard moves off RUNNING. Body size limits / field-level security
        // could be the cause of the original failure.
        try {
            await patchTestRun(run.Id, {
                status      : playwrightResult.status,
                completedAt : new Date().toISOString(),
                errorMessage: 'Result upload partially failed — see agent log',
            });
            log(`Fallback patch succeeded — ${run.Id} marked ${playwrightResult.status}`);
        } catch (e2) {
            log(`ERROR: fallback patch also failed for ${run.Id}: ${e2.message}`);
        }
    }
}

async function startAgent() {
    log(`qtc-runner agent starting. Agent ID: ${AGENT_ID}`);
    log(`Polling every ${POLL_INTERVAL_MS}ms for PENDING Test_Run__c records…`);

    // Verify credentials on startup
    try {
        const creds = getSfCredentials();
        log(`Connected to: ${creds.instanceUrl}`);
    } catch (e) {
        console.error('[agent] FATAL: Cannot connect to Salesforce:', e.message);
        process.exit(1);
    }

    // Main loop
    async function loop() {
        try {
            await pollOnce();
        } catch (e) {
            log(`Poll error (will retry): ${e.message}`);
        }
        setTimeout(loop, POLL_INTERVAL_MS);
    }
    loop();
}

// ─── Entry point ─────────────────────────────────────────────────────────

startAgent().catch(e => {
    console.error('[agent] Unhandled error:', e);
    process.exit(1);
});
