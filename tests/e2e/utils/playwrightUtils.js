// @ts-check
/**
 * Generic, app-agnostic Playwright helpers.
 *
 * Keep this file free of selectors or domain knowledge — only utilities
 * that could be reused by any spec.
 */
const fs   = require('fs');
const path = require('path');

/** @typedef {import('@playwright/test').Page} Page */
/** @typedef {import('@playwright/test').Locator} Locator */

// ─── Locator helpers ─────────────────────────────────────────────────────────

/**
 * Returns true if locator becomes visible within `timeout` ms, false otherwise.
 * Never throws.
 * @param {Locator} locator
 * @param {number}  [timeout=3000]
 */
async function isVisibleSafe(locator, timeout = 3_000) {
  return locator.isVisible({ timeout }).catch(() => false);
}

/**
 * Triple-click to select, fill new value, tab to commit. Common pattern
 * for numeric/text inputs that don't accept programmatic .fill alone.
 * @param {Locator} locator
 * @param {string}  value
 */
async function fillAndTab(locator, value) {
  await locator.click({ clickCount: 3 });
  await locator.fill(value);
  await locator.press('Tab');
}

/**
 * Click a locator if visible within `timeout`. Returns whether the click happened.
 * @param {Locator} locator
 * @param {number}  [timeout=3000]
 */
async function clickIfVisible(locator, timeout = 3_000) {
  if (await isVisibleSafe(locator, timeout)) {
    await locator.click();
    return true;
  }
  return false;
}

/**
 * Wait for any of several locators to become visible. Returns the index of
 * whichever appears first, or -1 if none did before `timeout`.
 *
 * Uses Promise.any so the function returns as soon as ONE locator wins —
 * it does NOT wait for the losing locators to time out.
 *
 * @param {Locator[]} locators
 * @param {number}    timeout
 */
async function waitForAny(locators, timeout = 30_000) {
  try {
    return await Promise.any(
      locators.map((loc, i) =>
        loc.waitFor({ state: 'visible', timeout }).then(() => i)
      )
    );
  } catch {
    return -1;   // all locators rejected (timed out)
  }
}

// ─── Run folder + screenshot helpers ─────────────────────────────────────────

/**
 * Build a timestamped run folder (YYYY-MM-DD_HH-MM-SS) under `baseDir`
 * and create it on disk. Returns { runTs, runDir }.
 * @param {string} baseDir
 */
function createRunFolder(baseDir) {
  const runTs  = new Date().toISOString().replace(/T/, '_').replace(/:/g, '-').slice(0, 19);
  const runDir = path.join(baseDir, 'runs', runTs);
  fs.mkdirSync(runDir, { recursive: true });
  return { runTs, runDir };
}

/**
 * Take a full-page screenshot saved as `<runDir>/<name>.png`.
 * @param {Page}   page
 * @param {string} runDir
 * @param {string} name    Filename without extension.
 */
async function screenshot(page, runDir, name) {
  await page.screenshot({ path: path.join(runDir, `${name}.png`), fullPage: true });
}

// ─── Date / currency helpers ─────────────────────────────────────────────────

/**
 * Format a Date as YYYY-MM-DD (the format HTML <input type="date"> accepts
 * via .fill() and the format Salesforce returns from REST API).
 * @param {Date} d
 */
function formatDateISO(d) {
  const y  = d.getFullYear();
  const m  = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${dd}`;
}

/**
 * Format a Date as MM/DD/YYYY (US locale — what many LWC date inputs display).
 * @param {Date} d
 */
function formatDateUS(d) {
  const y  = d.getFullYear();
  const m  = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${m}/${dd}/${y}`;
}

/**
 * Add `days` to a Date and return a new Date.
 * @param {Date}   d
 * @param {number} days
 */
function addDays(d, days) {
  const out = new Date(d);
  out.setDate(out.getDate() + days);
  return out;
}

/**
 * Format a Date as "Month DD, YYYY" (e.g. "May 14, 2026") — full month name.
 * @param {Date} d
 */
function formatDateLong(d) {
  const months = ['January','February','March','April','May','June',
                  'July','August','September','October','November','December'];
  return `${months[d.getMonth()]} ${d.getDate()}, ${d.getFullYear()}`;
}

/**
 * Format a Date as "Mmm D, YYYY" (e.g. "May 14, 2026", "Jun 7, 2026")
 * — abbreviated month name. This is the format Salesforce lightning-input
 * type="date" renders by default in en-US locale (the format hint under
 * the field reads "Format: Dec 31, 2024"), so it parses cleanly back into
 * the component's ISO value when typed.
 * @param {Date} d
 */
function formatDateShort(d) {
  const months = ['Jan','Feb','Mar','Apr','May','Jun',
                  'Jul','Aug','Sep','Oct','Nov','Dec'];
  return `${months[d.getMonth()]} ${d.getDate()}, ${d.getFullYear()}`;
}

/**
 * Parse "Month DD, YYYY" back to "YYYY-MM-DD" (Salesforce REST format).
 * Returns null if the string can't be parsed.
 * @param {string|null|undefined} str
 */
function parseLongDateToISO(str) {
  if (!str) return null;
  const parsed = new Date(str.trim());
  if (isNaN(parsed.getTime())) return null;
  return formatDateISO(parsed);
}

/**
 * Parse "$1,234.56" / "+$1,234.56" / "+12.3%" to a number, or null if unparseable.
 * @param {string|null|undefined} str
 */
function parseCurrency(str) {
  if (!str || str === 'N/A' || str === '--') return null;
  const clean = str.replace(/[+\-$,%\s]/g, '');
  const n = parseFloat(clean);
  return isNaN(n) ? null : n;
}

// ─── Salesforce REST helpers ─────────────────────────────────────────────────

/**
 * Run a SOQL query from inside the page context using the OAuth Bearer token.
 * Works around HttpOnly Lightning session cookies.
 *
 * @param {Page}   page
 * @param {string} instanceUrl    e.g. https://x.my.salesforce.com
 * @param {string} accessToken
 * @param {string} soql
 * @param {string} [apiVersion='v62.0']
 * @returns {Promise<{records: any[], totalSize: number, error?: string}>}
 */
async function sfQuery(page, instanceUrl, accessToken, soql, apiVersion = 'v62.0') {
  return page.evaluate(async ({ instanceUrl, accessToken, soql, apiVersion }) => {
    const url = `${instanceUrl}/services/data/${apiVersion}/query?q=${encodeURIComponent(soql)}`;
    const resp = await fetch(url, {
      headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
    });
    const json = await resp.json();
    if (!Array.isArray(json.records)) {
      return { records: [], totalSize: 0, error: JSON.stringify(json) };
    }
    return { records: json.records, totalSize: json.totalSize };
  }, { instanceUrl, accessToken, soql, apiVersion });
}

/**
 * Same as sfQuery, but runs directly from Node using global `fetch` (Node 18+).
 * Use this when there's no page yet — e.g. inside a `test.beforeAll` that
 * needs to build a cache before any test opens a browser.
 *
 * @param {string} instanceUrl
 * @param {string} accessToken
 * @param {string} soql
 * @param {string} [apiVersion='v62.0']
 * @returns {Promise<{records: any[], totalSize: number, error?: string}>}
 */
async function sfQueryNode(instanceUrl, accessToken, soql, apiVersion = 'v62.0') {
  const url = `${instanceUrl}/services/data/${apiVersion}/query?q=${encodeURIComponent(soql)}`;
  const resp = await fetch(url, {
    headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
  });
  const json = await resp.json();
  if (!Array.isArray(json.records)) {
    return { records: [], totalSize: 0, error: JSON.stringify(json) };
  }
  return { records: json.records, totalSize: json.totalSize };
}

module.exports = {
  isVisibleSafe,
  fillAndTab,
  clickIfVisible,
  waitForAny,
  createRunFolder,
  screenshot,
  formatDateISO,
  formatDateUS,
  formatDateLong,
  formatDateShort,
  parseLongDateToISO,
  addDays,
  parseCurrency,
  sfQuery,
  sfQueryNode,
};
