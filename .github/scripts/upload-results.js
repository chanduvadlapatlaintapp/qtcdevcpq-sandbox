#!/usr/bin/env node
/**
 * .github/scripts/upload-results.js
 *
 * After Playwright finishes, this script:
 *   1. Parses the Playwright JSON reporter output (test-results/<runId>/results.json)
 *   2. Finds the spec's richResults JSON (tests/e2e/results/runs/<newest>/results.json)
 *   3. Inserts Test_Result__c child records
 *   4. Uploads screenshots as Salesforce Files (ContentVersion + ContentDocumentLink)
 *   5. PATCHes Test_Run__c with final status, passed/failed counts, log, and richResults
 *
 * Reuses qtc-runner/uploader.js and qtc-runner/auth.js directly — zero code duplication.
 *
 * Usage:
 *   node upload-results.js <testRunId>
 */

'use strict';

const fs   = require('fs');
const path = require('path');

// ── Resolve modules relative to repo root ─────────────────────────────────────
const REPO_ROOT  = path.join(__dirname, '../..');
const { insertTestResults, uploadFile, patchTestRun } = require(
    path.join(REPO_ROOT, 'qtc-runner/uploader.js')
);

const SF_API_VER = process.env.QTC_SF_API_VERSION || '62.0';

// ── Args ──────────────────────────────────────────────────────────────────────

const [,, testRunId] = process.argv;

if (!testRunId) {
    console.error('Usage: node upload-results.js <testRunId>');
    process.exit(1);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function log(msg) {
    console.log(`[upload-results] ${msg}`);
}

/** Walk a directory recursively and return all .png/.jpg/.jpeg file paths */
function collectScreenshots(dir) {
    const files = [];
    if (!fs.existsSync(dir)) return files;
    function walk(d) {
        for (const entry of fs.readdirSync(d, { withFileTypes: true })) {
            const full = path.join(d, entry.name);
            if (entry.isDirectory())                         walk(full);
            else if (/\.(png|jpg|jpeg)$/i.test(entry.name)) files.push(full);
        }
    }
    walk(dir);
    return files;
}

/** Parse Playwright JSON reporter output into a flat test array */
function parsePlaywrightJson(json) {
    const results = [];
    function walkSuite(suite) {
        for (const spec of (suite.specs || [])) {
            for (const test of (spec.tests || [])) {
                const pw     = (test.status || '').toLowerCase();
                const status = pw === 'passed' ? 'PASSED'
                             : pw === 'skipped' ? 'SKIPPED'
                             : 'FAILED';
                const last   = test.results && test.results[test.results.length - 1];
                results.push({
                    title       : spec.title,
                    suiteName   : suite.title || '',
                    status,
                    durationMs  : last ? last.duration : 0,
                    retryCount  : (test.results || []).length - 1,
                    errorMessage: last && last.error
                        ? (last.error.message || last.error.value || '')
                        : null,
                });
            }
        }
        for (const child of (suite.suites || [])) walkSuite(child);
    }
    for (const suite of (json.suites || [])) walkSuite(suite);
    return results;
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
    const startTime = Date.now();

    // ── 1. Read Playwright JSON reporter output ───────────────────────────────
    const pwJsonPath = path.join(REPO_ROOT, 'test-results', testRunId, 'results.json');
    let tests        = [];
    let passed       = 0;
    let failed       = 0;
    let durationMs   = 0;
    let logOutput    = '';

    if (fs.existsSync(pwJsonPath)) {
        log(`Reading Playwright JSON: ${pwJsonPath}`);
        try {
            const raw  = JSON.parse(fs.readFileSync(pwJsonPath, 'utf8'));
            tests      = parsePlaywrightJson(raw);
            passed     = tests.filter(t => t.status === 'PASSED').length;
            failed     = tests.filter(t => t.status === 'FAILED').length;
            durationMs = raw.stats ? (raw.stats.duration || 0) : 0;
        } catch (e) {
            log(`Warning: could not parse Playwright JSON: ${e.message}`);
        }
    } else {
        log(`Warning: Playwright JSON not found at ${pwJsonPath}`);
    }

    // ── 2. Find spec richResults (tests/e2e/results/runs/<newest>/results.json) ──
    let richResults     = null;
    let specScreenshots = [];
    const runsDir       = path.join(REPO_ROOT, 'tests', 'e2e', 'results', 'runs');

    if (fs.existsSync(runsDir)) {
        try {
            const entries = fs.readdirSync(runsDir, { withFileTypes: true })
                .filter(e => e.isDirectory())
                .map(e => {
                    const full = path.join(runsDir, e.name);
                    return { full, mtime: fs.statSync(full).mtimeMs };
                })
                .sort((a, b) => b.mtime - a.mtime); // newest first

            if (entries.length > 0) {
                const newest = entries[0].full;
                log(`Newest run dir: ${path.basename(newest)}`);

                const richPath = path.join(newest, 'results.json');
                if (fs.existsSync(richPath)) {
                    try {
                        richResults = JSON.parse(fs.readFileSync(richPath, 'utf8'));
                        log(`richResults loaded (keys: ${Object.keys(richResults).join(', ')})`);
                    } catch (e) {
                        log(`Warning: could not parse spec results.json: ${e.message}`);
                    }
                }

                specScreenshots = collectScreenshots(newest);
                log(`Spec screenshots found: ${specScreenshots.length}`);

                // Collect log from any .txt / stdout files the spec may have written
                const logFile = path.join(newest, 'output.log');
                if (fs.existsSync(logFile)) {
                    logOutput = fs.readFileSync(logFile, 'utf8');
                }
            }
        } catch (e) {
            log(`Warning: could not scan runs dir: ${e.message}`);
        }
    }

    // Also grab stdout captured by the workflow (written to test-results/<id>/)
    const stdoutPath = path.join(REPO_ROOT, 'test-results', testRunId, 'stdout.log');
    if (fs.existsSync(stdoutPath) && !logOutput) {
        logOutput = fs.readFileSync(stdoutPath, 'utf8');
    }

    // ── 3. Determine final status ─────────────────────────────────────────────
    // Honour PLAYWRIGHT_EXIT_CODE env var set by the workflow step outcome.
    const playwrightExitCode = parseInt(process.env.PLAYWRIGHT_EXIT_CODE || '0', 10);
    const finalStatus = playwrightExitCode === 0 && failed === 0 ? 'PASSED' : 'FAILED';
    log(`Final status: ${finalStatus} (${passed}✓ ${failed}✗, ${durationMs}ms)`);

    // ── 4. Insert Test_Result__c records ──────────────────────────────────────
    if (tests.length > 0) {
        log(`Inserting ${tests.length} Test_Result__c records…`);
        try {
            await insertTestResults(testRunId, tests);
        } catch (e) {
            log(`Warning: insertTestResults failed: ${e.message}`);
        }
    }

    // ── 5. Upload screenshots ─────────────────────────────────────────────────
    const screenshots = specScreenshots.length > 0
        ? specScreenshots
        : collectScreenshots(path.join(REPO_ROOT, 'test-results', testRunId));

    log(`Uploading ${screenshots.length} screenshot(s)…`);
    for (const screenshotPath of screenshots) {
        try {
            const title = path.basename(screenshotPath);
            await uploadFile(screenshotPath, title, testRunId);
        } catch (e) {
            log(`Warning: screenshot upload failed (${path.basename(screenshotPath)}): ${e.message}`);
        }
    }

    // ── 6. Patch Test_Run__c with final status ────────────────────────────────
    log(`Patching Test_Run__c ${testRunId} → ${finalStatus}`);
    await patchTestRun(testRunId, {
        status      : finalStatus,
        passed,
        failed,
        durationMs,
        logOutput,
        richResults,
        completedAt : new Date().toISOString(),
    });

    log(`Done. Total upload time: ${((Date.now() - startTime) / 1000).toFixed(1)}s`);
}

main().catch(err => {
    console.error('[upload-results] Fatal error:', err.message);
    process.exit(1);
});
