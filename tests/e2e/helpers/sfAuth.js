/**
 * Salesforce auth helper for Playwright.
 * Uses the access token from SF CLI to inject a session cookie,
 * bypassing the Salesforce login page entirely.
 *
 * Portable: auto-discovers the `sf` CLI via PATH / common install locations.
 * No hardcoded user-specific paths — works on any developer machine.
 */
const { execSync } = require('child_process');
const fs   = require('fs');
const path = require('path');

// ── Resolve the `sf` CLI binary ──────────────────────────────────────────────
// Priority: (1) which/where, (2) common install prefixes, (3) nvm/volta/fnm dirs
function findSfCli() {
  // 1. Try PATH first (covers homebrew, npm global, volta, mise, etc.)
  try {
    const found = execSync('which sf 2>/dev/null || where sf 2>nul', { stdio: ['pipe','pipe','pipe'] })
      .toString().trim().split('\n')[0].trim();
    if (found && fs.existsSync(found)) return found;
  } catch {}

  // 2. Common fixed install locations
  const candidates = [
    '/opt/homebrew/bin/sf',
    '/usr/local/bin/sf',
    '/usr/bin/sf',
    path.join(process.env.HOME || '', '.local/bin/sf'),
    // npm global on macOS/Linux
    path.join(process.env.HOME || '', '.npm-global/bin/sf'),
    // volta
    path.join(process.env.HOME || '', '.volta/bin/sf'),
  ];
  const found = candidates.find(p => { try { return fs.statSync(p).isFile(); } catch { return false; } });
  if (found) return found;

  throw new Error(
    '`sf` CLI not found. Install it with: npm install --global @salesforce/cli\n' +
    'Then run: sf org login web --alias qtcmock'
  );
}

const SF = findSfCli();

function getSfCredentials() {
  const raw = execSync(
    `"${SF}" org display --target-org qtcmock --json 2>/dev/null`,
    { env: { ...process.env, NO_COLOR: '1', FORCE_COLOR: '0' } }
  ).toString().replace(/\x1B\[[0-9;]*m/g, '');
  const result = JSON.parse(raw).result;

  const instanceUrl = result.instanceUrl;

  // SF CLI returns the REST API URL (*.my.salesforce.com).
  // The Lightning UI lives on a different hostname (*.lightning.force.com).
  // Convert:  intapp--qtcmock.sandbox.my.salesforce.com
  //       →   intapp--qtcmock.sandbox.lightning.force.com
  const lightningUrl = instanceUrl.replace(/\.my\.salesforce\.com$/, '.lightning.force.com');

  return {
    instanceUrl,    // used for REST API calls  (my.salesforce.com)
    lightningUrl,   // used for browser nav     (lightning.force.com)
    accessToken: result.accessToken,
  };
}

/**
 * Injects the Salesforce session cookie into the Playwright browser context
 * so tests start already authenticated — no login page needed.
 */
async function loginViaCookie(page, instanceUrl, accessToken) {
  // Always derive the Lightning UI URL (handles both my.salesforce.com and lightning.force.com inputs)
  const lightningBase = instanceUrl
    .replace(/\.my\.salesforce\.com$/, '.lightning.force.com')
    .replace(/\/+$/, '');

  // Use frontdoor.jsp — the official SF mechanism to exchange an OAuth Bearer token
  // for a browser session cookie. This avoids manual cookie injection which can fail
  // when Salesforce changes their cookie/domain requirements.
  // After hitting this URL, Salesforce sets the real `sid` session cookie and redirects.
  const frontdoorUrl = `${lightningBase}/secur/frontdoor.jsp?sid=${encodeURIComponent(accessToken)}&retURL=%2F`;

  await page.goto(frontdoorUrl, { waitUntil: 'domcontentloaded' });
  // Give Lightning a moment to fully establish the session before the next navigation
  await page.waitForTimeout(2000);
}

module.exports = { getSfCredentials, loginViaCookie };
