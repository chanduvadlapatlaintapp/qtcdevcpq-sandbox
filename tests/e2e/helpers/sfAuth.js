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
// Walk PATH manually (cross-platform; no shelling out to `which`/`where`),
// then fall back to common install prefixes per OS.
function findSfCli() {
  const isWin = process.platform === 'win32';
  // On Windows, only the cmd-executable variants count — the bare `sf` (no extension)
  // is a /bin/sh script that cmd.exe cannot execute.
  const exts  = isWin ? ['.cmd', '.exe', '.bat'] : [''];

  const fileForDir = (dir) => {
    for (const ext of exts) {
      const p = path.join(dir, `sf${ext}`);
      try { if (fs.statSync(p).isFile()) return p; } catch {}
    }
    return null;
  };

  // 1. Walk PATH
  const pathVar = process.env.PATH || process.env.Path || '';
  for (const dir of pathVar.split(path.delimiter)) {
    if (!dir) continue;
    const hit = fileForDir(dir.replace(/^"|"$/g, ''));
    if (hit) return hit;
  }

  // 2. Common fixed install locations per OS
  const home = process.env.HOME || process.env.USERPROFILE || '';
  const candidateDirs = isWin ? [
    path.join(process.env.APPDATA || '', 'npm'),                  // npm global on Windows
    path.join(process.env.ProgramFiles || 'C:\\Program Files', 'sf', 'bin'),
    path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Salesforce CLI', 'bin'),
    path.join(home, 'AppData', 'Roaming', 'npm'),
  ] : [
    '/opt/homebrew/bin',
    '/usr/local/bin',
    '/usr/bin',
    path.join(home, '.local/bin'),
    path.join(home, '.npm-global/bin'),
    path.join(home, '.volta/bin'),
  ];
  for (const dir of candidateDirs) {
    const hit = fileForDir(dir);
    if (hit) return hit;
  }

  throw new Error(
    '`sf` CLI not found on PATH or in common install locations.\n' +
    'Install it with: npm install --global @salesforce/cli\n' +
    'Then run: sf org login web --alias qtcmock'
  );
}

const SF = findSfCli();

function getSfCredentials() {
  // Don't redirect stderr in the command string — `2>/dev/null` is Unix-only and
  // breaks on cmd.exe. Use stdio:'pipe' so stderr is captured (and silent) instead.
  const raw = execSync(
    `"${SF}" org display --target-org qtcmock --json`,
    {
      env: { ...process.env, NO_COLOR: '1', FORCE_COLOR: '0' },
      stdio: ['ignore', 'pipe', 'pipe'],
    }
  ).toString().replace(/\x1B\[[0-9;]*m/g, '');
  const result = JSON.parse(raw).result;

  const instanceUrl = result.instanceUrl;

  // The access token must NOT come from `org display --json`: modern Salesforce
  // CLI redacts it to the literal placeholder "[REDACTED] Use 'sf org auth
  // show-access-token' to view". Used as a frontdoor `sid`, that placeholder
  // produces an invalid session and dumps the test on the SF login page. Fetch
  // the real token from the dedicated, unredacted command instead.
  const tokRaw = execSync(
    `"${SF}" org auth show-access-token --target-org qtcmock --json`,
    {
      env: { ...process.env, NO_COLOR: '1', FORCE_COLOR: '0' },
      stdio: ['ignore', 'pipe', 'pipe'],
    }
  ).toString().replace(/\x1B\[[0-9;]*m/g, '');
  const accessToken = JSON.parse(tokRaw).result.accessToken;

  if (!accessToken || /REDACTED/.test(accessToken)) {
    throw new Error(
      'No usable access token for org "qtcmock". Run: sf org login web --alias qtcmock'
    );
  }

  // SF CLI returns the REST API URL (*.my.salesforce.com).
  // The Lightning UI lives on a different hostname (*.lightning.force.com).
  // Convert:  intapp--qtcmock.sandbox.my.salesforce.com
  //       →   intapp--qtcmock.sandbox.lightning.force.com
  const lightningUrl = instanceUrl.replace(/\.my\.salesforce\.com$/, '.lightning.force.com');

  return {
    instanceUrl,    // used for REST API calls  (my.salesforce.com)
    lightningUrl,   // used for browser nav     (lightning.force.com)
    accessToken,    // real token from `org auth show-access-token` (unredacted)
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
  // Salesforce can chain frontdoor → contentDoor (file.force.com) → lightning.force.com.
  // Wait for the URL to actually land on the Lightning host before returning, so the
  // caller's next page.goto() doesn't race an in-flight redirect.
  await page.waitForURL(/\.lightning\.force\.com\//, { timeout: 60_000 });
  await page.waitForLoadState('domcontentloaded').catch(() => {});
  await page.waitForLoadState('networkidle', { timeout: 15_000 }).catch(() => {});

  // Surface the browser window. When Playwright is launched from a background
  // process (e.g. the dashboard's spawned npx playwright), Windows' foreground-
  // focus lock keeps the new Chrome window minimized in the taskbar even
  // though --start-maximized was on the command line.
  //
  // page.bringToFront() alone only switches *tabs* within Chrome — it does
  // NOT restore a minimized OS window. To force the window manager to
  // restore + maximize, we drive CDP's Browser.setWindowBounds directly:
  // it sets windowState at the OS level and overrides the focus-lock.
  await page.bringToFront().catch(() => {});
  try {
    const session = await page.context().newCDPSession(page);
    const { windowId } = await session.send('Browser.getWindowForTarget');
    // Two-step: 'normal' first to un-minimize, then 'maximized'. A direct
    // 'minimized' → 'maximized' transition is a no-op on some Chromium
    // builds, but 'minimized' → 'normal' → 'maximized' is reliable.
    await session.send('Browser.setWindowBounds', { windowId, bounds: { windowState: 'normal'    } }).catch(() => {});
    await session.send('Browser.setWindowBounds', { windowId, bounds: { windowState: 'maximized' } }).catch(() => {});
    await session.detach().catch(() => {});
  } catch { /* CDP unavailable (non-chromium) — best-effort only */ }
}

module.exports = { getSfCredentials, loginViaCookie };
