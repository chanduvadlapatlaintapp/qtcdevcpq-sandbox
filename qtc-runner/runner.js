/**
 * runner.js  —  Invokes Playwright for a given test suite and collects results.
 *
 * Returns a structured result object that agent.js feeds into uploader.js.
 *
 * Playwright is run as a child process (via `npx playwright test`) so this
 * module has no compile-time dependency on @playwright/test — that package
 * lives in the parent project (qtcdevcpq-sandbox), NOT in qtc-runner.
 */

'use strict';

const { spawnSync } = require('child_process');
const path          = require('path');
const fs            = require('fs');
const os            = require('os');

// ─── Locate the Playwright project root ──────────────────────────────────────

// When running from the installed location (~/.qtc-runner/), __dirname is NOT
// the project root. The installer writes the real project path to .project_root.
// Fall back to the parent directory only when running directly from source.
function resolveProjectRoot() {
    const dotFile = path.join(__dirname, '.project_root');
    if (fs.existsSync(dotFile)) {
        return fs.readFileSync(dotFile, 'utf8').trim();
    }
    // Running from source (qtcdevcpq-sandbox/qtc-runner/) — go up one level
    return path.resolve(__dirname, '..');
}

const PROJECT_ROOT = resolveProjectRoot();
const RESULTS_DIR  = path.join(PROJECT_ROOT, 'test-results');

// ─── Main export ─────────────────────────────────────────────────────────────

/**
 * Run a Playwright suite and return a result object.
 *
 * @param {string} suiteName  - Test suite name (maps to tests/e2e/{suiteName}.spec.js)
 * @param {string} testRunId  - Salesforce Test_Run__c Id (used for result folder naming)
 * @param {string} [accountName]  - Target Account name chosen on the dashboard.
 *                                  Passed to the spec via QTC_ACCOUNT_* env vars;
 *                                  when blank the spec uses its hard-coded fallback.
 * @param {string} [accountsJson] - JSON array of {id, search, fullName} objects for
 *                                  multi-account runs. When present, QTC_ACCOUNTS is set
 *                                  to this value so agenticQtcFullRegressionE2E iterates
 *                                  over every account in the list.
 * @returns {{
 *   status       : 'PASSED'|'FAILED'|'ERROR',
 *   passed       : number,
 *   failed       : number,
 *   durationMs   : number,
 *   logOutput    : string,
 *   errorMessage : string|null,
 *   tests        : Array<{title,status,durationMs,suiteName,errorMessage,retryCount}>,
 *   screenshots  : Array<string>,   // absolute file paths
 *   videoPath    : string|null,
 * }}
 */
async function runSuite(suiteName, testRunId, accountName, accountsJson, contractId, quoteName) {
    // Build the spec file path from suite name
    const specFile = `tests/e2e/${suiteName}.spec.js`;
    const specPath = path.join(PROJECT_ROOT, specFile);
    if (!fs.existsSync(specPath)) {
        return _errorResult(`Spec file not found: ${specPath}`);
    }

    // Output dir for this run's artifacts
    const outputDir = path.join(RESULTS_DIR, testRunId);
    fs.mkdirSync(outputDir, { recursive: true });

    const jsonReporter = path.join(outputDir, 'results.json');

    const args = [
        'playwright', 'test',
        specFile,
        '--reporter=json',
        `--output=${outputDir}`,
    ];

    const env = {
        ...process.env,
        PLAYWRIGHT_JSON_OUTPUT_FILE : jsonReporter,
        // Headed Chrome: never run headless
        HEADED: '1',
    };

    // Multi-account mode: accountsJson is a JSON array of {id, search, fullName} objects
    // stored in Test_Run__c.Multiple_Accounts__c. Pass the full JSON to QTC_ACCOUNTS so
    // agenticQtcFullRegressionE2E's resolveAccounts() iterates over every account.
    // Also seed the singular QTC_ACCOUNT_* vars from the first entry so other specs
    // that only read those vars still get a sensible default.
    if (accountsJson && String(accountsJson).trim()) {
        const json = String(accountsJson).trim();
        env.QTC_ACCOUNTS = json;
        try {
            const arr = JSON.parse(json);
            if (Array.isArray(arr) && arr.length > 0) {
                const first = arr[0];
                const firstName = first.fullName || first.search || first.name || '';
                if (firstName) {
                    env.QTC_ACCOUNT_NAME      = firstName;
                    env.QTC_ACCOUNT_SEARCH    = first.search || firstName;
                    env.QTC_ACCOUNT_FULL_NAME = first.fullName || firstName;
                }
            }
        } catch (e) {
            console.warn(`[runner] Could not parse accountsJson: ${e.message}`);
        }
        console.log(`[runner] Multi-account mode: ${json}`);
    } else if (accountName && String(accountName).trim()) {
        // Single-account mode: spec reads QTC_ACCOUNTS (plural) or QTC_ACCOUNT_* (singular)
        const acct = String(accountName).trim();
        env.QTC_ACCOUNT_NAME      = acct;
        env.QTC_ACCOUNT_SEARCH    = acct;
        env.QTC_ACCOUNT_FULL_NAME = acct;
        env.QTC_ACCOUNTS          = acct;
        console.log(`[runner] Target account: "${acct}"`);
    }

    // Contract scoping — tells the spec which contract to use (skips SOQL discovery).
    if (contractId && String(contractId).trim()) {
        env.QTC_CONTRACT_ID = String(contractId).trim();
        console.log(`[runner] Contract: "${env.QTC_CONTRACT_ID}"`);
    }

    // Quote scoping — tells the spec an existing QTC draft quote to open (Mode 2).
    // When set, QTC opens this draft and updates qty; SF Standard creates a new amendment.
    if (quoteName && String(quoteName).trim()) {
        env.QTC_QUOTE_NAME = String(quoteName).trim();
        console.log(`[runner] Existing QTC quote: "${env.QTC_QUOTE_NAME}"`);
    }

    console.log(`[runner] Starting Playwright: npx ${args.join(' ')}`);
    const start   = Date.now();

    // shell:true required on Windows / Node 20+ to spawn npx.cmd (CVE-2024-27980).
    // Without it: spawnSync('npx', ...) throws ENOENT because Node refuses to
    // spawn .cmd files via the direct execve path. Harmless on Linux/Mac.
    const isWin = process.platform === 'win32';
    // Per-suite timeout: most suites finish well within 10 min; multi-scenario
    // regression suites (e.g. agenticQtcFullRegressionE2E) need up to 30 min
    // because they drive 3 contracts sequentially with a 10-min per-test cap.
    const LONG_SUITES  = new Set(['agenticQtcFullRegressionE2E', 'agenticQtcAmendmentUIComparison']);
    const processTimeout = LONG_SUITES.has(suiteName)
        ? 30 * 60 * 1000   // 30 min for multi-scenario regression
        : 10 * 60 * 1000;  // 10 min for all other suites

    const result = spawnSync('npx', args, {
        cwd   : PROJECT_ROOT,
        env,
        stdio : 'pipe',
        shell : isWin,
        timeout: processTimeout,
    });

    const durationMs = Date.now() - start;
    const stdout     = result.stdout ? result.stdout.toString() : '';
    const stderr     = result.stderr ? result.stderr.toString() : '';
    const logOutput  = stdout + (stderr ? '\n--- STDERR ---\n' + stderr : '');

    if (result.error) {
        return _errorResult(`Playwright spawn error: ${result.error.message}`, logOutput);
    }

    // Parse JSON reporter output
    let tests = [];
    if (fs.existsSync(jsonReporter)) {
        try {
            const raw  = JSON.parse(fs.readFileSync(jsonReporter, 'utf8'));
            tests      = _parsePlaywrightJson(raw);
            const p = tests.filter(t => t.status === 'PASSED').length;
            const f = tests.filter(t => t.status === 'FAILED').length;
            const s = tests.filter(t => t.status === 'SKIPPED').length;
            console.log(`[runner] JSON reporter parsed: ${tests.length} test(s) — ${p} passed, ${f} failed, ${s} skipped`);
        } catch (e) {
            console.error('[runner] Could not parse Playwright JSON:', e);
        }
    } else {
        console.warn(`[runner] JSON reporter file not found — Test_Result__c records will not be created. Expected: ${jsonReporter}`);
    }

    const passed = tests.filter(t => t.status === 'PASSED').length;
    const failed = tests.filter(t => t.status === 'FAILED').length;
    // Status must reflect BOTH the process exit code and the per-test failure
    // count. Trusting exit code alone produced a "PASSED" badge with failed=1
    // when Playwright exits 0 despite a failure in its JSON output.
    // An all-skipped run (beforeAll returned early) also exits 0 with failed=0 —
    // treat that as FAILED so the dashboard doesn't show "PASSED" with 0 tests.
    const status = (result.status === 0 && failed === 0 && passed > 0) ? 'PASSED' : 'FAILED';

    // Collect richResults + spec screenshots from the spec's run directory
    // The spec writes to tests/e2e/results/runs/<timestamp>/ — pick the newest.
    let richResults     = null;
    let richResultsPath = null;
    let screenshots     = _collectScreenshots(outputDir); // fallback: Playwright artifacts

    const specRunsDir = path.join(PROJECT_ROOT, 'tests', 'e2e', 'results', 'runs');
    if (fs.existsSync(specRunsDir)) {
        try {
            const entries = fs.readdirSync(specRunsDir, { withFileTypes: true })
                .filter(e => e.isDirectory())
                .map(e => {
                    const full = path.join(specRunsDir, e.name);
                    return { full, mtime: fs.statSync(full).mtimeMs };
                })
                .sort((a, b) => b.mtime - a.mtime); // newest first

            // Pick the newest folder that actually contains a results.json —
            // a skipped final test creates the run folder but never writes the file.
            const targetEntry = entries.find(e =>
                fs.existsSync(path.join(e.full, 'results.json'))
            );

            if (targetEntry) {
                const newestDir = targetEntry.full;

                // Load richResults JSON
                const richPath = path.join(newestDir, 'results.json');
                richResultsPath = richPath;
                try {
                    richResults = JSON.parse(fs.readFileSync(richPath, 'utf8'));
                    console.log(`[runner] Loaded richResults from ${path.basename(newestDir)}`);
                } catch (e) {
                    console.warn('[runner] Could not parse spec results.json:', e.message);
                }

                // Prefer spec screenshots (higher quality, named) over Playwright artifacts
                const specShots = _collectScreenshots(newestDir);
                if (specShots.length > 0) {
                    screenshots = specShots;
                    console.log(`[runner] Using ${specShots.length} spec screenshot(s) from run dir`);
                }
            }
        } catch (e) {
            console.warn('[runner] Could not scan spec runs dir:', e.message);
        }
    }

    // Collect video (Playwright saves as webm inside test-results/<hash>/video.webm)
    const videoPath = _findVideo(outputDir);

    return {
        status,
        passed,
        failed,
        durationMs,
        logOutput,
        errorMessage : status === 'FAILED' ? `${failed} test(s) failed` : null,
        tests,
        screenshots,
        richResults,
        richResultsPath,
        videoPath,
    };
}

// ─── Parse Playwright JSON reporter output ───────────────────────────────────

function _parsePlaywrightJson(json) {
    const results = [];
    for (const suite of (json.suites || [])) {
        _walkSuite(suite, results);
    }
    return results;
}

function _walkSuite(suite, results) {
    for (const spec of (suite.specs || [])) {
        for (const test of (spec.tests || [])) {
            const status = _mapStatus(test.status);
            const lastResult = test.results && test.results[test.results.length - 1];
            results.push({
                title       : spec.title,
                suiteName   : suite.title || '',
                status,
                durationMs  : lastResult ? lastResult.duration : 0,
                retryCount  : (test.results || []).length - 1,
                errorMessage: (lastResult && lastResult.error)
                    ? (lastResult.error.message || lastResult.error.value || '')
                    : null,
            });
        }
    }
    for (const child of (suite.suites || [])) {
        _walkSuite(child, results);
    }
}

function _mapStatus(pw) {
    // Playwright JSON reporter sets test.status to:
    //   'expected'   — test passed as expected
    //   'unexpected' — test failed
    //   'flaky'      — failed then passed on retry (still counts as PASSED)
    //   'skipped'    — skipped
    // NOT 'passed'/'failed' — those only appear on individual test.results[n].status
    switch ((pw || '').toLowerCase()) {
        case 'expected':    return 'PASSED';
        case 'flaky':       return 'PASSED';   // passed after retry
        case 'skipped':     return 'SKIPPED';
        case 'unexpected':  return 'FAILED';
        default:            return 'FAILED';
    }
}

// ─── Collect artifacts ───────────────────────────────────────────────────────

function _collectScreenshots(dir) {
    const files = [];
    if (!fs.existsSync(dir)) return files;

    function walk(d) {
        for (const entry of fs.readdirSync(d, { withFileTypes: true })) {
            const full = path.join(d, entry.name);
            if (entry.isDirectory()) {
                walk(full);
            } else if (/\.(png|jpg|jpeg)$/i.test(entry.name)) {
                files.push(full);
            }
        }
    }
    walk(dir);
    return files;
}

function _findVideo(dir) {
    if (!fs.existsSync(dir)) return null;
    const found = [];
    function walk(d) {
        for (const entry of fs.readdirSync(d, { withFileTypes: true })) {
            const full = path.join(d, entry.name);
            if (entry.isDirectory()) walk(full);
            else if (/\.(webm|mp4)$/i.test(entry.name)) found.push(full);
        }
    }
    walk(dir);
    // Return the largest video file (most likely to be the full recording)
    if (!found.length) return null;
    return found.sort((a, b) =>
        fs.statSync(b).size - fs.statSync(a).size
    )[0];
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function _errorResult(errorMessage, logOutput = '') {
    return {
        status: 'ERROR',
        passed: 0,
        failed: 0,
        durationMs: 0,
        logOutput,
        errorMessage,
        tests: [],
        screenshots: [],
        videoPath: null,
    };
}

module.exports = { runSuite };
