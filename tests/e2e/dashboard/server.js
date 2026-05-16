#!/usr/bin/env node
/**
 * AgenticQTC Test Dashboard Server
 * Run: node tests/e2e/dashboard/server.js
 * Opens: http://localhost:7777
 */

'use strict';

const http       = require('http');
const fs         = require('fs');
const path       = require('path');
const { spawn }  = require('child_process');
const { execSync } = require('child_process');
const url        = require('url');

// ─── Config ─────────────────────────────────────────────────────────────────

const PORT        = 7777;
const REPO_DIR    = path.resolve(__dirname, '../../..');
const RESULTS_DIR = path.resolve(__dirname, '../results');
const RESULTS_JSON = path.join(RESULTS_DIR, 'results.json');
const REPORT_HTML  = path.join(RESULTS_DIR, 'quantity-increase-report.html');
const SPEC_REL     = 'tests/e2e/agenticQtcQuantityIncrease.spec.js';

// Find npx — check common install locations (portable, no hardcoded user paths)
const NODE_DIRS = [
  path.dirname(process.execPath),                           // same Node.js that's running this server
  '/opt/homebrew/bin',                                      // Homebrew (macOS ARM / Intel)
  path.join(process.env.HOME || '', '.volta/bin'),          // Volta
  path.join(process.env.HOME || '', '.npm-global/bin'),     // npm global prefix
  path.join(process.env.HOME || '', '.local/bin'),          // generic local bin
  '/usr/local/bin',
  '/usr/bin',
];
const NODE_PATH = NODE_DIRS.filter(d => {
  try { return fs.statSync(path.join(d, 'npx')).isFile(); } catch { return false; }
})[0] || '';

// ─── State ──────────────────────────────────────────────────────────────────

let runState = {
  running:   false,
  exitCode:  null,
  startedAt: null,
  finishedAt: null,
  logBuffer: [],        // { html, raw } — kept for page reload
};
let sseClients = [];    // active SSE response objects

// ─── SSE helpers ─────────────────────────────────────────────────────────────

function broadcast(event, data) {
  const msg = `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
  sseClients = sseClients.filter(c => !c.destroyed);
  sseClients.forEach(c => { try { c.write(msg); } catch {} });
}

// ─── ANSI → HTML ─────────────────────────────────────────────────────────────

const ANSI_MAP = {
  '0': 'reset', '1': 'bold',
  '30':'#374151','31':'#f87171','32':'#4ade80','33':'#fbbf24',
  '34':'#60a5fa','35':'#c084fc','36':'#22d3ee','37':'#e2e8f0',
  '90':'#6b7280','91':'#f87171','92':'#34d399','93':'#fcd34d',
  '94':'#818cf8','95':'#e879f9','96':'#67e8f9','97':'#f1f5f9',
};

function ansiToHtml(raw) {
  let out = raw
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');

  // Replace each ANSI escape sequence
  out = out.replace(/\x1B\[([0-9;]*)m/g, (_, codes) => {
    if (!codes || codes === '0') return '</span>';
    return codes.split(';').map(c => {
      const v = ANSI_MAP[c];
      if (!v) return '';
      if (v === 'bold') return '<span style="font-weight:700">';
      if (v === 'reset') return '</span>';
      return `<span style="color:${v}">`;
    }).join('');
  });

  // Wrap lines in divs for proper display
  return out.split('\n').map(l => `<div class="log-line">${l || '&nbsp;'}</div>`).join('');
}

// ─── Run test ────────────────────────────────────────────────────────────────

function startTestRun() {
  if (runState.running) return false;

  runState.running   = true;
  runState.exitCode  = null;
  runState.startedAt = new Date().toISOString();
  runState.finishedAt = null;
  runState.logBuffer = [];

  broadcast('status', { running: true, startedAt: runState.startedAt });

  const env = {
    ...process.env,
    PATH: NODE_PATH ? `${NODE_PATH}:${process.env.PATH || ''}` : process.env.PATH,
    FORCE_COLOR: '1',
    NO_COLOR: '0',
  };

  const proc = spawn('npx', ['playwright', 'test', SPEC_REL, '--reporter=list'], {
    cwd: REPO_DIR,
    env,
    shell: false,
  });

  const onData = (data) => {
    const raw  = data.toString();
    const html = ansiToHtml(raw);
    runState.logBuffer.push({ html, raw });
    broadcast('log', { html, raw });
  };

  proc.stdout.on('data', onData);
  proc.stderr.on('data', onData);

  proc.on('close', (code) => {
    runState.running    = false;
    runState.exitCode   = code;
    runState.finishedAt = new Date().toISOString();
    broadcast('done', {
      exitCode:   code,
      finishedAt: runState.finishedAt,
    });
  });

  proc.on('error', (err) => {
    const html = ansiToHtml(`\n❌ Failed to spawn playwright: ${err.message}\n`);
    runState.logBuffer.push({ html, raw: err.message });
    broadcast('log', { html, raw: err.message });
  });

  return true;
}

// ─── HTTP server ─────────────────────────────────────────────────────────────

function serve(req, res) {
  const parsed   = url.parse(req.url, true);
  const pathname = parsed.pathname;

  // CORS (for local dev)
  res.setHeader('Access-Control-Allow-Origin', '*');

  // ── SSE stream ──────────────────────────────────────────────────────────
  if (pathname === '/api/stream') {
    res.writeHead(200, {
      'Content-Type':  'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection':    'keep-alive',
    });
    // Send buffered logs so a reloaded page catches up
    if (runState.logBuffer.length > 0) {
      runState.logBuffer.forEach(({ html, raw }) => {
        res.write(`event: log\ndata: ${JSON.stringify({ html, raw })}\n\n`);
      });
    }
    // Send current status
    res.write(`event: status\ndata: ${JSON.stringify({
      running:    runState.running,
      startedAt:  runState.startedAt,
      finishedAt: runState.finishedAt,
      exitCode:   runState.exitCode,
    })}\n\n`);

    res.write(':keepalive\n\n');
    sseClients.push(res);
    const keepalive = setInterval(() => {
      if (res.destroyed) { clearInterval(keepalive); return; }
      res.write(':keepalive\n\n');
    }, 15_000);
    req.on('close', () => {
      clearInterval(keepalive);
      sseClients = sseClients.filter(c => c !== res);
    });
    return;
  }

  // ── POST /api/run ────────────────────────────────────────────────────────
  if (pathname === '/api/run' && req.method === 'POST') {
    const started = startTestRun();
    res.writeHead(started ? 202 : 409, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: started, running: runState.running }));
    return;
  }

  // ── GET /api/results ─────────────────────────────────────────────────────
  if (pathname === '/api/results') {
    try {
      const data = fs.readFileSync(RESULTS_JSON, 'utf-8');
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(data);
    } catch {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end('null');
    }
    return;
  }

  // ── GET /api/runs ─────────────────────────────────────────────────────────
  // Returns list of all historical runs sorted newest-first
  if (pathname === '/api/runs') {
    try {
      const runsDir = path.join(RESULTS_DIR, 'runs');
      if (!fs.existsSync(runsDir)) { res.writeHead(200, { 'Content-Type': 'application/json' }); res.end('[]'); return; }

      const runs = fs.readdirSync(runsDir)
        .filter(d => fs.statSync(path.join(runsDir, d)).isDirectory())
        .sort().reverse()   // newest first (ISO timestamp sorts lexicographically)
        .map(runTs => {
          const jsonPath = path.join(runsDir, runTs, 'results.json');
          try {
            const d = JSON.parse(fs.readFileSync(jsonPath, 'utf-8'));
            return {
              runTs,
              runAt:         d.runAt,
              passed:        d.passed,
              durationMs:    d.durationMs,
              quoteName:     d.quoteName,
              dbAnomalyCount: d.dbAnomalyCount,
              dbHighCount:   d.dbHighCount,
              allQtyPass:    d.allQtyPass,
              contract:      d.contract,
              screenshots:   (d.screenshots || []).map(s => `runs/${runTs}/${s}.png`),
            };
          } catch {
            return { runTs, runAt: runTs, passed: null, durationMs: null };
          }
        });

      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(runs));
    } catch (e) {
      res.writeHead(500); res.end(JSON.stringify({ error: String(e) }));
    }
    return;
  }

  // ── GET /api/state ───────────────────────────────────────────────────────
  if (pathname === '/api/state') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      running:    runState.running,
      exitCode:   runState.exitCode,
      startedAt:  runState.startedAt,
      finishedAt: runState.finishedAt,
    }));
    return;
  }

  // ── Static result files (screenshots, report HTML) ───────────────────────
  if (pathname.startsWith('/results/')) {
    const rel  = pathname.slice('/results/'.length);
    const file = path.join(RESULTS_DIR, rel);
    // Safety: stay inside RESULTS_DIR
    if (!file.startsWith(RESULTS_DIR)) { res.writeHead(403); res.end(); return; }
    try {
      const data = fs.readFileSync(file);
      const ext  = path.extname(file).toLowerCase();
      const mime = { '.png': 'image/png', '.html': 'text/html', '.json': 'application/json' }[ext] || 'application/octet-stream';
      res.writeHead(200, { 'Content-Type': mime });
      res.end(data);
    } catch {
      res.writeHead(404); res.end('Not found');
    }
    return;
  }

  // ── Dashboard SPA ────────────────────────────────────────────────────────
  if (pathname === '/' || pathname === '/index.html') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(DASHBOARD_HTML);
    return;
  }

  res.writeHead(404); res.end('Not found');
}

// ─── Dashboard HTML ──────────────────────────────────────────────────────────

const DASHBOARD_HTML = /* html */`<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>AgenticQTC · Test Dashboard</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
:root{
  --bg:#0c0f1a;--surface:#131929;--card:#1a2236;--border:#1f2d45;
  --text:#e2e8f0;--muted:#64748b;--accent:#3b82f6;
  --green:#22c55e;--red:#ef4444;--yellow:#f59e0b;--purple:#a855f7;
  --font:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
  --mono:'SF Mono','Fira Code','Consolas',monospace;
}
html,body{height:100%;background:var(--bg);color:var(--text);font-family:var(--font);font-size:14px;line-height:1.5}

/* ── Layout ── */
.app{display:grid;grid-template-rows:56px 1fr;height:100vh;overflow:hidden}
.topbar{display:flex;align-items:center;gap:16px;padding:0 24px;background:var(--surface);border-bottom:1px solid var(--border);flex-shrink:0}
.topbar-title{font-size:16px;font-weight:700;color:#f8fafc;letter-spacing:-.01em}
.topbar-title span{color:var(--accent)}
.topbar-right{margin-left:auto;display:flex;align-items:center;gap:10px}
.status-pill{display:inline-flex;align-items:center;gap:6px;padding:4px 12px;border-radius:20px;font-size:12px;font-weight:600;transition:all .3s}
.status-pill.idle   {background:#1e2d40;color:#60a5fa;border:1px solid #1d4ed8}
.status-pill.running{background:#1a3020;color:#4ade80;border:1px solid #166534}
.status-pill.passed {background:#14532d;color:#86efac;border:1px solid #16a34a}
.status-pill.failed {background:#450a0a;color:#fca5a5;border:1px solid #991b1b}
.dot{width:8px;height:8px;border-radius:50%;background:currentColor}
.dot.pulse{animation:pulse 1.4s infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.3}}

/* ── Buttons ── */
.btn{display:inline-flex;align-items:center;gap:8px;padding:8px 18px;border-radius:8px;border:none;font-size:13px;font-weight:600;cursor:pointer;transition:all .15s;white-space:nowrap}
.btn-primary{background:var(--accent);color:#fff}
.btn-primary:hover:not(:disabled){background:#2563eb}
.btn-primary:disabled{opacity:.5;cursor:not-allowed}
.btn-danger{background:#7f1d1d;color:#fca5a5;border:1px solid #991b1b}
.btn-danger:hover:not(:disabled){background:#991b1b}
.btn-sm{padding:5px 12px;font-size:12px}
.btn-ghost{background:transparent;color:var(--muted);border:1px solid var(--border)}
.btn-ghost:hover{border-color:var(--accent);color:var(--accent)}

/* ── Main panels ── */
.main{display:grid;grid-template-columns:1fr 420px;overflow:hidden;height:100%}
.left-col{overflow-y:auto;padding:20px;display:flex;flex-direction:column;gap:16px;border-right:1px solid var(--border)}
.right-col{overflow-y:auto;display:flex;flex-direction:column}

/* ── Cards ── */
.card{background:var(--card);border:1px solid var(--border);border-radius:10px;overflow:hidden}
.card-header{display:flex;align-items:center;justify-content:space-between;padding:12px 16px;border-bottom:1px solid var(--border)}
.card-title{font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:var(--muted)}
.card-body{padding:16px}

/* ── Terminal ── */
.terminal{background:#05080f;border-radius:10px;border:1px solid var(--border);display:flex;flex-direction:column;min-height:300px;max-height:500px}
.terminal-bar{display:flex;align-items:center;padding:8px 14px;gap:8px;border-bottom:1px solid var(--border);background:#0a0d17;border-radius:10px 10px 0 0}
.term-dot{width:12px;height:12px;border-radius:50%}
.terminal-label{font-size:11px;color:var(--muted);margin-left:4px;flex:1;font-family:var(--mono)}
.terminal-body{flex:1;overflow-y:auto;padding:12px 14px;font-family:var(--mono);font-size:12px;line-height:1.55}
.log-line{min-height:1.55em;white-space:pre-wrap;word-break:break-all}
.terminal-body::-webkit-scrollbar{width:6px}
.terminal-body::-webkit-scrollbar-track{background:transparent}
.terminal-body::-webkit-scrollbar-thumb{background:#1f2d45;border-radius:3px}
.empty-terminal{color:var(--muted);font-size:12px;font-family:var(--mono);padding:20px;text-align:center}

/* ── KPI Grid ── */
.kpi-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}
.kpi{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:12px 14px}
.kpi-label{font-size:10px;color:var(--muted);text-transform:uppercase;letter-spacing:.06em;margin-bottom:4px}
.kpi-value{font-size:20px;font-weight:700;color:var(--text);line-height:1}
.kpi-value.green{color:var(--green)}
.kpi-value.red  {color:var(--red)}
.kpi-value.blue {color:#60a5fa}
.kpi-value.sm   {font-size:13px;margin-top:2px}

/* ── Metrics table ── */
.metrics-row{display:flex;justify-content:space-between;align-items:center;padding:8px 0;border-bottom:1px solid var(--border)}
.metrics-row:last-child{border-bottom:none}
.metric-name{font-size:12px;color:var(--muted);font-weight:600}
.metric-vals{display:flex;gap:12px;align-items:center;font-size:12px;font-family:var(--mono)}
.metric-arrow{color:var(--muted)}
.metric-after{color:var(--green);font-weight:700}

/* ── Anomaly list ── */
.anomaly-list{display:flex;flex-direction:column;gap:8px}
.anomaly-item{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:10px 14px;display:flex;gap:12px;align-items:flex-start}
.anomaly-item.high  {border-color:#7f1d1d;background:#0f0808}
.anomaly-item.medium{border-color:#78350f;background:#0f0b06}
.anomaly-item.low   {border-color:#1e3a5f;background:#060d17}
.badge{display:inline-block;border-radius:4px;padding:2px 8px;font-size:10px;font-weight:700;text-transform:uppercase;flex-shrink:0;margin-top:2px}
.badge.high  {background:#7f1d1d;color:#fca5a5}
.badge.medium{background:#78350f;color:#fcd34d}
.badge.low   {background:#1e3a5f;color:#93c5fd}
.anomaly-content{}
.anomaly-type{font-size:12px;font-weight:700;color:var(--text);margin-bottom:2px}
.anomaly-detail{font-size:11px;color:var(--muted);line-height:1.4}

/* ── Line table ── */
.table-wrap{overflow-x:auto}
table{width:100%;border-collapse:collapse;font-size:11px}
th{background:#0f1826;color:var(--muted);font-weight:700;text-align:left;padding:8px 10px;border-bottom:1px solid var(--border);white-space:nowrap}
td{padding:7px 10px;border-bottom:1px solid #111827;vertical-align:middle}
tr.pass td{background:#030f08}
tr.fail td{background:#100505}
tr:hover td{filter:brightness(1.1)}
.num{font-family:var(--mono);text-align:right}
.pass-icon{color:var(--green)}
.fail-icon{color:var(--red)}
.bundle-tag{font-size:9px;color:#60a5fa;border:1px solid #1d4ed8;border-radius:3px;padding:1px 4px;margin-left:4px;vertical-align:middle}
.zero-price{color:var(--red);font-weight:700}

/* ── Screenshots ── */
.shots-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:8px}
.shot{border-radius:8px;overflow:hidden;border:1px solid var(--border);background:var(--surface);cursor:pointer;transition:border-color .2s}
.shot:hover{border-color:var(--accent)}
.shot img{width:100%;display:block}
.shot-label{font-size:10px;color:var(--muted);padding:6px 8px;border-top:1px solid var(--border)}

/* ── Right panel ── */
.right-col .card{border-radius:0;border-left:none;border-right:none;border-top:none}
.right-col .card:first-child{border-top:1px solid var(--border)}

/* ── Tabs ── */
.tabs{display:flex;gap:0;border-bottom:1px solid var(--border)}
.tab{flex:1;padding:10px;text-align:center;font-size:12px;font-weight:600;color:var(--muted);cursor:pointer;border-bottom:2px solid transparent;transition:all .2s}
.tab.active{color:var(--accent);border-bottom-color:var(--accent)}
.tab-pane{display:none;padding:14px}
.tab-pane.active{display:block}

/* ── Empty state ── */
.empty{text-align:center;padding:40px 20px;color:var(--muted)}
.empty-icon{font-size:36px;margin-bottom:12px}
.empty-text{font-size:13px}
.empty-sub{font-size:11px;margin-top:4px;color:#374151}

/* ── Run history ── */
.run-history-row{padding:10px 16px;border-bottom:1px solid var(--border);cursor:pointer;transition:background .15s}
.run-history-row:hover{background:#1a2236}
.run-history-row:last-child{border-bottom:none}

/* ── Lightbox ── */
.lightbox{display:none;position:fixed;inset:0;background:rgba(0,0,0,.85);z-index:1000;align-items:center;justify-content:center;cursor:pointer}
.lightbox.open{display:flex}
.lightbox img{max-width:90vw;max-height:90vh;border-radius:8px;box-shadow:0 0 60px rgba(0,0,0,.8)}

/* ── Scrollbars ── */
.left-col::-webkit-scrollbar,.right-col::-webkit-scrollbar{width:5px}
.left-col::-webkit-scrollbar-thumb,.right-col::-webkit-scrollbar-thumb{background:#1f2d45;border-radius:3px}
</style>
</head>
<body>
<div class="app">

  <!-- Top bar -->
  <header class="topbar">
    <div class="topbar-title">Agentic<span>QTC</span> · Test Dashboard</div>
    <div id="status-pill" class="status-pill idle">
      <span class="dot"></span>
      <span id="status-text">Idle</span>
    </div>
    <div id="last-run-label" style="font-size:11px;color:var(--muted)"></div>
    <div class="topbar-right">
      <button class="btn btn-ghost btn-sm" onclick="location.reload()">↺ Refresh</button>
      <button id="run-btn" class="btn btn-primary" onclick="runTests()">
        <span id="run-btn-icon">▶</span>
        <span id="run-btn-text">Run Tests</span>
      </button>
    </div>
  </header>

  <!-- Main -->
  <div class="main">

    <!-- Left column: terminal + results -->
    <div class="left-col">

      <!-- Terminal -->
      <div class="terminal">
        <div class="terminal-bar">
          <div class="term-dot" style="background:#ff5f57"></div>
          <div class="term-dot" style="background:#febc2e"></div>
          <div class="term-dot" style="background:#28c840"></div>
          <span class="terminal-label">playwright test › agenticQtcQuantityIncrease.spec.js</span>
          <button class="btn btn-ghost btn-sm" onclick="clearTerminal()" style="padding:2px 8px;font-size:10px">Clear</button>
          <button class="btn btn-ghost btn-sm" onclick="copyLogs()" style="padding:2px 8px;font-size:10px">Copy</button>
        </div>
        <div id="terminal-body" class="terminal-body">
          <div class="empty-terminal">No output yet — click <strong>Run Tests</strong> to start</div>
        </div>
      </div>

      <!-- Results (loaded from results.json after run) -->
      <div id="results-section" style="display:none;flex-direction:column;gap:16px">

        <!-- KPI row -->
        <div class="card">
          <div class="card-header">
            <span class="card-title">Last Run Summary</span>
            <span id="run-duration" style="font-size:11px;color:var(--muted)"></span>
          </div>
          <div class="card-body">
            <div class="kpi-grid" id="kpi-grid"></div>
          </div>
        </div>

        <!-- Anomalies -->
        <div class="card" id="anomaly-card">
          <div class="card-header">
            <span class="card-title">⚠ Bugs &amp; Anomalies</span>
            <span id="anomaly-count" style="font-size:11px;color:var(--muted)"></span>
          </div>
          <div class="card-body">
            <div id="anomaly-list" class="anomaly-list"></div>
          </div>
        </div>

        <!-- Metric changes -->
        <div class="card">
          <div class="card-header"><span class="card-title">Header Metrics (Pre → Post Save)</span></div>
          <div class="card-body" id="metrics-section"></div>
        </div>

        <!-- DB Line items table -->
        <div class="card">
          <div class="card-header">
            <span class="card-title">DB QuoteLine Records</span>
            <span id="db-totals" style="font-size:11px;color:var(--muted)"></span>
          </div>
          <div class="card-body" style="padding:0">
            <div class="table-wrap">
              <table id="db-table">
                <thead><tr>
                  <th>#</th><th>Product</th><th>Seg#</th>
                  <th class="num">Prior Qty</th><th class="num">DB Qty</th>
                  <th class="num">Cust Price</th><th class="num">List Price</th>
                  <th class="num">Discount</th><th class="num">Net Total</th>
                  <th>Method</th>
                </tr></thead>
                <tbody id="db-tbody"></tbody>
              </table>
            </div>
          </div>
        </div>

        <!-- UI line qty assertions -->
        <div class="card">
          <div class="card-header">
            <span class="card-title">UI Quantity Assertions</span>
            <span id="qty-pass-count" style="font-size:11px;color:var(--muted)"></span>
          </div>
          <div class="card-body" style="padding:0">
            <div class="table-wrap">
              <table id="qty-table">
                <thead><tr>
                  <th>#</th><th>Product / Segment</th>
                  <th class="num">Before</th><th class="num">Expected</th>
                  <th class="num">Actual</th><th class="num">Δ</th><th>Result</th>
                </tr></thead>
                <tbody id="qty-tbody"></tbody>
              </table>
            </div>
          </div>
        </div>

        <!-- Screenshots -->
        <div class="card">
          <div class="card-header">
            <span class="card-title">Screenshots</span>
            <span id="shots-run-label" style="font-size:11px;color:var(--muted)"></span>
          </div>
          <div class="card-body">
            <div id="shots-grid" class="shots-grid"></div>
          </div>
        </div>

        <!-- PDF Generation Results -->
        <div class="card" id="pdf-card">
          <div class="card-header">
            <span class="card-title">📄 PDF Generation — Preview &amp; Send OSA</span>
            <span id="pdf-status-label" style="font-size:11px;color:var(--muted)"></span>
          </div>
          <div class="card-body" id="pdf-body">
            <div class="empty" style="padding:12px 0">
              <div class="empty-text">No PDF data yet</div>
            </div>
          </div>
        </div>

        <!-- Run History -->
        <div class="card">
          <div class="card-header">
            <span class="card-title">📅 Run History</span>
            <span id="run-history-count" style="font-size:11px;color:var(--muted)"></span>
          </div>
          <div class="card-body" style="padding:0">
            <div id="run-history-list"></div>
          </div>
        </div>

      </div><!-- /results-section -->
    </div>

    <!-- Right column: report iframe + info -->
    <div class="right-col">
      <div class="tabs">
        <div class="tab active" onclick="switchTab('report')">Full Report</div>
        <div class="tab" onclick="switchTab('info')">Run Info</div>
      </div>

      <div id="tab-report" class="tab-pane active" style="padding:0;flex:1;display:flex;flex-direction:column">
        <div id="report-placeholder" class="empty" style="padding:60px 20px">
          <div class="empty-icon">📋</div>
          <div class="empty-text">Full report will appear here after a run</div>
          <div class="empty-sub">Click <strong>Run Tests</strong> to generate it</div>
        </div>
        <iframe id="report-frame" src="" style="flex:1;border:none;display:none;min-height:100%" allowfullscreen></iframe>
      </div>

      <div id="tab-info" class="tab-pane" style="padding:0">
        <div style="padding:16px;display:flex;flex-direction:column;gap:12px">

          <div class="card" style="border-radius:8px">
            <div class="card-header"><span class="card-title">Test Configuration</span></div>
            <div class="card-body" style="font-size:12px;display:flex;flex-direction:column;gap:8px">
              <div style="display:flex;justify-content:space-between">
                <span style="color:var(--muted)">Spec file</span>
                <span style="font-family:var(--mono);color:#93c5fd;font-size:10px">agenticQtcQuantityIncrease.spec.js</span>
              </div>
              <div style="display:flex;justify-content:space-between">
                <span style="color:var(--muted)">Account</span>
                <span>Baker McKenzie LLP</span>
              </div>
              <div style="display:flex;justify-content:space-between">
                <span style="color:var(--muted)">Quantity delta</span>
                <span style="color:var(--green);font-weight:700">+5 per line</span>
              </div>
              <div style="display:flex;justify-content:space-between">
                <span style="color:var(--muted)">Browser</span>
                <span>Chromium (headed)</span>
              </div>
              <div style="display:flex;justify-content:space-between">
                <span style="color:var(--muted)">Timeout</span>
                <span>5 min / test</span>
              </div>
            </div>
          </div>

          <div class="card" style="border-radius:8px">
            <div class="card-header"><span class="card-title">Anomaly Legend</span></div>
            <div class="card-body" style="display:flex;flex-direction:column;gap:8px;font-size:11px">
              <div style="display:flex;gap:8px;align-items:start">
                <span class="badge high" style="margin-top:0">HIGH</span>
                <span style="color:var(--muted)">Data integrity risk — qty/price/total mismatch between UI and DB</span>
              </div>
              <div style="display:flex;gap:8px;align-items:start">
                <span class="badge medium" style="margin-top:0">MEDIUM</span>
                <span style="color:var(--muted)">Pricing rule may not have fired — zero price on non-bundle line</span>
              </div>
              <div style="display:flex;gap:8px;align-items:start">
                <span class="badge low" style="margin-top:0">LOW</span>
                <span style="color:var(--muted)">Configuration anomaly — missing segment key on MDQ line</span>
              </div>
            </div>
          </div>

          <div class="card" style="border-radius:8px">
            <div class="card-header"><span class="card-title">Quick Links</span></div>
            <div class="card-body" style="display:flex;flex-direction:column;gap:8px">
              <a href="/results/quantity-increase-report.html" target="_blank" class="btn btn-ghost btn-sm" style="justify-content:center">📄 Open Report in New Tab</a>
              <a href="/results/results.json" target="_blank" class="btn btn-ghost btn-sm" style="justify-content:center">{ } Raw Results JSON</a>
            </div>
          </div>

          <div id="run-info-card" class="card" style="border-radius:8px;display:none">
            <div class="card-header"><span class="card-title">Last Run Details</span></div>
            <div class="card-body" style="font-size:12px;display:flex;flex-direction:column;gap:8px" id="run-info-body"></div>
          </div>
        </div>
      </div>

    </div>
  </div>
</div>

<!-- Lightbox for screenshots -->
<div class="lightbox" id="lightbox" onclick="closeLightbox()">
  <img id="lightbox-img" src="" alt="">
</div>

<script>
// ─── State ────────────────────────────────────────────────────────────────────
let autoScroll = true;
let evtSource  = null;
let lastData   = null;
let rawLogBuffer = '';

// ─── SSE connection ──────────────────────────────────────────────────────────
function connectSSE() {
  if (evtSource) evtSource.close();
  evtSource = new EventSource('/api/stream');

  evtSource.addEventListener('status', e => {
    const s = JSON.parse(e.data);
    updateStatusUI(s);
  });

  evtSource.addEventListener('log', e => {
    const { html, raw } = JSON.parse(e.data);
    appendLog(html);
    rawLogBuffer += raw;
  });

  evtSource.addEventListener('done', e => {
    const { exitCode, finishedAt } = JSON.parse(e.data);
    const pill = document.getElementById('status-pill');
    const txt  = document.getElementById('status-text');
    pill.className = 'status-pill ' + (exitCode === 0 ? 'passed' : 'failed');
    txt.textContent = exitCode === 0 ? 'Passed' : 'Failed';
    document.querySelector('.dot').classList.remove('pulse');

    const btn = document.getElementById('run-btn');
    btn.disabled = false;
    document.getElementById('run-btn-icon').textContent = '▶';
    document.getElementById('run-btn-text').textContent  = 'Run Tests';

    // Load results after a short delay (file write completes)
    setTimeout(() => {
      loadResults();
      loadRunHistory();
    }, 800);
    loadReportFrame();
  });

  evtSource.onerror = () => {
    setTimeout(connectSSE, 3000); // reconnect
  };
}

function updateStatusUI(s) {
  const pill = document.getElementById('status-pill');
  const txt  = document.getElementById('status-text');
  const dot  = document.querySelector('.dot');
  const btn  = document.getElementById('run-btn');

  if (s.running) {
    pill.className = 'status-pill running';
    txt.textContent = 'Running…';
    dot.classList.add('pulse');
    btn.disabled = true;
    document.getElementById('run-btn-icon').textContent = '⏳';
    document.getElementById('run-btn-text').textContent  = 'Running…';
  } else if (s.exitCode === 0) {
    pill.className = 'status-pill passed';
    txt.textContent = 'Passed';
  } else if (s.exitCode !== null) {
    pill.className = 'status-pill failed';
    txt.textContent = 'Failed';
  } else {
    pill.className = 'status-pill idle';
    txt.textContent = 'Idle';
  }

  if (s.finishedAt) {
    document.getElementById('last-run-label').textContent =
      'Last run: ' + new Date(s.finishedAt).toLocaleTimeString();
  }
}

// ─── Terminal helpers ────────────────────────────────────────────────────────
function appendLog(html) {
  const body = document.getElementById('terminal-body');
  // Remove placeholder
  const placeholder = body.querySelector('.empty-terminal');
  if (placeholder) placeholder.remove();

  const div = document.createElement('div');
  div.innerHTML = html;
  body.appendChild(div);

  if (autoScroll) body.scrollTop = body.scrollHeight;
}

function clearTerminal() {
  document.getElementById('terminal-body').innerHTML =
    '<div class="empty-terminal">Terminal cleared</div>';
  rawLogBuffer = '';
}

async function copyLogs() {
  try {
    await navigator.clipboard.writeText(rawLogBuffer);
    const btn = event.target;
    btn.textContent = 'Copied!';
    setTimeout(() => btn.textContent = 'Copy', 1500);
  } catch {}
}

// Pause auto-scroll when user scrolls up
document.addEventListener('DOMContentLoaded', () => {
  const tb = document.getElementById('terminal-body');
  tb.addEventListener('scroll', () => {
    autoScroll = tb.scrollTop + tb.clientHeight >= tb.scrollHeight - 20;
  });
});

// ─── Run tests ───────────────────────────────────────────────────────────────
async function runTests() {
  clearTerminal();
  rawLogBuffer = '';
  document.getElementById('results-section').style.display = 'none';

  const resp = await fetch('/api/run', { method: 'POST' });
  if (resp.status === 409) {
    alert('A test run is already in progress.');
  }
}

// ─── Load results JSON ───────────────────────────────────────────────────────
async function loadResults() {
  try {
    const resp = await fetch('/api/results');
    if (!resp.ok) return;
    const d = await resp.json();
    if (!d) return;
    lastData = d;
    renderResults(d);
    document.getElementById('results-section').style.display = 'flex';
  } catch {}
}

function fmt$(v) {
  if (v === null || v === undefined) return '<span style="color:#374151">—</span>';
  const n = Number(v);
  if (isNaN(n)) return v;
  return '$' + n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 4 });
}

function fmtDuration(ms) {
  if (!ms) return '';
  const s = Math.round(ms / 1000);
  return s >= 60 ? Math.floor(s/60) + 'm ' + (s%60) + 's' : s + 's';
}

function renderResults(d) {
  // Duration
  document.getElementById('run-duration').textContent = fmtDuration(d.durationMs);

  // KPI grid
  const allOk = d.allQtyPass && d.dbHighCount === 0;
  document.getElementById('kpi-grid').innerHTML = [
    { label: 'Quote', value: d.quoteName || 'N/A', cls: 'blue sm' },
    { label: 'Lines Updated', value: d.spinbuttonCount },
    { label: 'Qty Delta', value: '+' + d.deltaApplied, cls: 'green' },
    { label: 'UI Assertions', value: d.lineResults.filter(r => r.pass).length + ' / ' + d.lineResults.length, cls: d.allQtyPass ? 'green' : 'red' },
    { label: 'DB Anomalies', value: d.dbAnomalyCount === 0 ? '✅ 0' : '⚠ ' + d.dbAnomalyCount, cls: d.dbAnomalyCount === 0 ? 'green' : '' },
    { label: 'HIGH Severity', value: d.dbHighCount === 0 ? '✅ 0' : '❌ ' + d.dbHighCount, cls: d.dbHighCount === 0 ? 'green' : 'red' },
    { label: 'ACV Before', value: d.metricsBeforeSave?.acv || 'N/A', cls: 'sm' },
    { label: 'ACV After', value: d.metricsAfterSave?.acv || 'N/A', cls: 'green sm' },
    { label: 'Approval?', value: d.hasApproval ? '⚠ Yes' : '✅ No', cls: d.hasApproval ? '' : 'green' },
    { label: 'Send OSA', value: d.hasSendBtn ? '✅ Ready' : '—' },
    { label: 'PDF Generated', value: d.pdfSkipped ? '⏭ Skipped' : d.pdfGenerated ? '✅ Yes' : '❌ Failed', cls: d.pdfGenerated ? 'green' : d.pdfSkipped ? '' : 'red' },
    { label: 'OSA Sent', value: d.pdfSkipped ? '⏭ Skipped' : d.osaSent ? '✅ Sent' : '—', cls: d.osaSent ? 'green' : '' },
    { label: 'DB Lines', value: d.dbLineCount, cls: 'blue' },
    { label: 'Totals Match', value: Math.abs((d.uiQtyTotal||0) - (d.dbQtyTotal||0)) < 0.01 ? '✅ Yes' : '❌ No', cls: Math.abs((d.uiQtyTotal||0) - (d.dbQtyTotal||0)) < 0.01 ? 'green' : 'red' },
  ].map(k => \`<div class="kpi">
    <div class="kpi-label">\${k.label}</div>
    <div class="kpi-value \${k.cls||''}">\${k.value}</div>
  </div>\`).join('');

  // Anomalies
  const anomalies = d.dbAnomalies || [];
  document.getElementById('anomaly-count').textContent =
    anomalies.length + ' total · ' + d.dbHighCount + ' HIGH';
  if (anomalies.length === 0) {
    document.getElementById('anomaly-list').innerHTML =
      '<div style="color:var(--green);font-size:13px;padding:8px 0">✅ No anomalies detected — UI and DB are consistent</div>';
  } else {
    document.getElementById('anomaly-list').innerHTML = anomalies.map(a => \`
      <div class="anomaly-item \${a.severity.toLowerCase()}">
        <span class="badge \${a.severity.toLowerCase()}">\${a.severity}</span>
        <div class="anomaly-content">
          <div class="anomaly-type">\${a.type}</div>
          <div class="anomaly-detail">\${a.detail}</div>
        </div>
      </div>\`).join('');
  }

  // Metrics
  const mb = d.metricsBeforeSave, ma = d.metricsAfterSave;
  const metricKeys = [
    ['ACV','acv'],['ACV Change','acvChange'],['TCV','tcv'],
    ['YoY Uplift','yoyUplift'],['Deal Quality','dealQuality']
  ];
  document.getElementById('metrics-section').innerHTML = metricKeys.map(([label, key]) => \`
    <div class="metrics-row">
      <span class="metric-name">\${label}</span>
      <div class="metric-vals">
        <span style="color:var(--muted)">\${mb?.[key]||'N/A'}</span>
        <span class="metric-arrow">→</span>
        <span class="metric-after">\${ma?.[key]||'N/A'}</span>
      </div>
    </div>\`).join('');

  // DB table
  document.getElementById('db-totals').textContent =
    'UI total: ' + (d.uiQtyTotal||0).toLocaleString() +
    ' · DB total: ' + (d.dbQtyTotal||0).toLocaleString();
  const dbRows = (d.dbComparison || []).map(r => {
    const isBundle = r.isBundle;
    const hasAnomaly = (d.dbAnomalies||[]).some(a => a.detail && a.detail.includes('line ' + r.index + ' '));
    const priceClass = (!isBundle && r.dbPrice !== null && r.dbPrice == 0) ? 'zero-price' : '';
    const netClass   = (!isBundle && r.dbNetTotal !== null && r.dbNetTotal == 0 && r.dbPrice > 0) ? 'zero-price' : '';
    return \`<tr class="\${hasAnomaly ? 'fail' : ''}">
      <td>\${r.index}</td>
      <td>\${r.product}\${isBundle ? '<span class="bundle-tag">bundle</span>' : ''}</td>
      <td class="num">\${r.segIndex ?? '—'}</td>
      <td class="num">\${r.priorQty ?? '—'}</td>
      <td class="num" style="font-weight:700">\${r.dbQty}</td>
      <td class="num \${priceClass}">\${fmt$(r.dbPrice)}</td>
      <td class="num">\${fmt$(r.dbListPrice)}</td>
      <td class="num">\${r.dbDiscount != null ? r.dbDiscount + '%' : '—'}</td>
      <td class="num \${netClass}">\${fmt$(r.dbNetTotal)}</td>
      <td style="font-size:10px;color:var(--muted)">\${r.pricingMethod||'—'}</td>
    </tr>\`;
  }).join('');
  document.getElementById('db-tbody').innerHTML = dbRows;

  // UI qty assertions table
  const passCount = (d.lineResults||[]).filter(r => r.pass).length;
  document.getElementById('qty-pass-count').textContent =
    passCount + ' / ' + (d.lineResults||[]).length + ' passing';
  document.getElementById('qty-tbody').innerHTML = (d.lineResults||[]).map(r => \`
    <tr class="\${r.pass ? 'pass' : 'fail'}">
      <td>\${r.index}</td>
      <td style="font-size:10px;color:var(--muted);max-width:220px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">\${r.label}</td>
      <td class="num">\${r.before}</td>
      <td class="num">\${r.expected}</td>
      <td class="num \${r.pass ? 'pass-icon' : 'fail-icon'}">\${r.actual}</td>
      <td class="num" style="color:var(--green);font-weight:700">+\${d.deltaApplied}</td>
      <td class="\${r.pass ? 'pass-icon' : 'fail-icon'}">\${r.pass ? '✅' : '❌'}</td>
    </tr>\`).join('');

  // PDF Generation section
  const pdfBody   = document.getElementById('pdf-body');
  const pdfStatus = document.getElementById('pdf-status-label');
  if (d.pdfSkipped) {
    pdfStatus.textContent = 'skipped';
    pdfBody.innerHTML = \`<div style="color:var(--muted);font-size:12px">⏭ Approvals required — "Preview and Send OSA" was not available on this run.</div>\`;
  } else {
    pdfStatus.textContent = d.pdfGenerated ? (d.osaSent ? 'generated + sent' : 'generated') : 'failed';
    const rows = [
      ['PDF Generated',       d.pdfGenerated ? '<span style="color:var(--green)">✅ Yes</span>' : '<span style="color:var(--red)">❌ Failed</span>'],
      ['Document Title',      d.pdfDocTitle  ? \`<span style="font-family:var(--mono);font-size:11px">\${d.pdfDocTitle}</span>\` : '—'],
      ['ContentDocument ID',  d.pdfDocId     ? \`<a href="/lightning/r/ContentDocument/\${d.pdfDocId}/view" target="_blank" style="color:#60a5fa;font-family:var(--mono);font-size:11px">\${d.pdfDocId}</a>\` : '—'],
      ['Preview iframe src',  d.pdfPreviewSrc ? \`<span style="font-family:var(--mono);font-size:10px;word-break:break-all">\${d.pdfPreviewSrc}</span>\` : '—'],
      ['"Open in New Tab"',   d.pdfOpenTabVisible ? '✅ Visible' : '—'],
      ['Previously Gen Docs', d.hadExistingDocs ? '📂 Yes' : 'None'],
      ['DocuSign Send',       d.osaSent ? '<span style="color:var(--green)">✅ "OSA sent successfully via DocuSign!" confirmed</span>' : '—'],
    ];
    pdfBody.innerHTML = rows.map(([k, v]) => \`
      <div class="metrics-row" style="gap:8px">
        <span class="metric-name" style="min-width:160px">\${k}</span>
        <span style="font-size:12px;flex:1;text-align:right">\${v}</span>
      </div>\`).join('');
  }

  // Screenshots — stored under results/runs/{runTs}/
  const runTs = d.runTs || '';
  document.getElementById('shots-run-label').textContent = runTs ? runTs.replace('_',' ') : '';
  document.getElementById('shots-grid').innerHTML = (d.screenshots||[]).map(s => {
    // Support both old flat names and new run-folder names
    const imgPath = runTs ? \`/results/runs/\${runTs}/\${s}.png\` : \`/results/\${s}.png\`;
    const label   = s.replace(/^\d+-/,'').replace(/-/g,' ');
    return \`<div class="shot" onclick="openLightbox('\${imgPath}')">
      <img src="\${imgPath}" alt="\${s}" loading="lazy" onerror="this.parentElement.style.display='none'">
      <div class="shot-label">\${label}</div>
    </div>\`;
  }).join('');

  // Run info panel
  const ri = document.getElementById('run-info-card');
  ri.style.display = 'block';
  document.getElementById('run-info-body').innerHTML = [
    ['Run At', new Date(d.runAt).toLocaleString()],
    ['Duration', fmtDuration(d.durationMs)],
    ['Quote ID', d.quoteId || 'N/A'],
    ['Quote Status', d.quoteStatus || 'N/A'],
    ['Contract', (d.contract||'').split('\\t')[1] || d.contract || 'N/A'],
    ['Qty total UI', (d.uiQtyTotal||0).toLocaleString()],
    ['Qty total DB', (d.dbQtyTotal||0).toLocaleString()],
  ].map(([k,v]) => \`<div style="display:flex;justify-content:space-between;gap:8px">
    <span style="color:var(--muted)">\${k}</span>
    <span style="font-family:var(--mono);font-size:11px;text-align:right">\${v}</span>
  </div>\`).join('');
}

// ─── Report iframe ───────────────────────────────────────────────────────────
function loadReportFrame() {
  const frame = document.getElementById('report-frame');
  const ph    = document.getElementById('report-placeholder');
  frame.src = '/results/quantity-increase-report.html?' + Date.now();
  frame.style.display = 'block';
  ph.style.display    = 'none';
}

// ─── Tabs ─────────────────────────────────────────────────────────────────────
function switchTab(name) {
  document.querySelectorAll('.tab').forEach((t, i) => {
    const id = ['report','info'][i];
    t.classList.toggle('active', id === name);
  });
  document.getElementById('tab-report').classList.toggle('active', name === 'report');
  document.getElementById('tab-info').classList.toggle('active', name === 'info');
}

// ─── Lightbox ────────────────────────────────────────────────────────────────
function openLightbox(src) {
  document.getElementById('lightbox-img').src = src;
  document.getElementById('lightbox').classList.add('open');
}
function closeLightbox() {
  document.getElementById('lightbox').classList.remove('open');
}

// ─── Run history ─────────────────────────────────────────────────────────────
async function loadRunHistory() {
  try {
    const resp = await fetch('/api/runs');
    const runs = await resp.json();
    const el = document.getElementById('run-history-list');
    const cnt = document.getElementById('run-history-count');
    if (!runs || runs.length === 0) {
      el.innerHTML = '<div style="padding:14px;color:var(--muted);font-size:12px">No previous runs yet</div>';
      return;
    }
    cnt.textContent = runs.length + ' runs';
    el.innerHTML = runs.map((r, i) => {
      const dt       = r.runAt ? new Date(r.runAt).toLocaleString() : r.runTs;
      const dur      = r.durationMs ? Math.round(r.durationMs/1000) + 's' : '—';
      const status   = r.passed === true ? '✅' : r.passed === false ? '❌' : '—';
      const anomalies = r.dbHighCount > 0 ? \`<span style="color:#f87171">\${r.dbHighCount} HIGH</span>\`
                      : r.dbAnomalyCount > 0 ? \`<span style="color:#fbbf24">\${r.dbAnomalyCount} warn</span>\`
                      : '<span style="color:#4ade80">clean</span>';
      const isLatest = i === 0 ? ' style="border-left:2px solid var(--accent)"' : '';
      return \`<div class="run-history-row"\${isLatest} onclick="loadHistoryRun('\${r.runTs}')" title="Click to load this run">
        <div style="display:flex;justify-content:space-between;align-items:center">
          <span style="font-size:12px;font-weight:600">\${status} \${dt}</span>
          <span style="font-size:11px;color:var(--muted)">\${dur}</span>
        </div>
        <div style="display:flex;gap:12px;margin-top:3px;font-size:11px;color:var(--muted)">
          <span>\${(r.quoteName||'—')}</span>
          <span>anomalies: \${anomalies}</span>
        </div>
      </div>\`;
    }).join('');
  } catch {}
}

async function loadHistoryRun(runTs) {
  try {
    const resp = await fetch(\`/results/runs/\${runTs}/results.json\`);
    if (!resp.ok) return;
    const d = await resp.json();
    if (!d) return;
    lastData = d;
    renderResults(d);
    document.getElementById('results-section').style.display = 'flex';
    // Highlight selected row
    document.querySelectorAll('.run-history-row').forEach(r => r.style.background = '');
    event.currentTarget.style.background = '#1a2236';
  } catch {}
}

// ─── Init ─────────────────────────────────────────────────────────────────────
connectSSE();
// Load any existing results from a prior run
loadResults().then(() => {
  if (lastData) loadReportFrame();
});
// Sync state from server
fetch('/api/state').then(r => r.json()).then(s => updateStatusUI(s)).catch(() => {});
// Load run history
loadRunHistory();
</script>
</body>
</html>`;

// ─── Start server ────────────────────────────────────────────────────────────

fs.mkdirSync(RESULTS_DIR, { recursive: true });

const server = http.createServer(serve);
server.listen(PORT, '127.0.0.1', () => {
  const addr = `http://localhost:${PORT}`;
  console.log('\n╔══════════════════════════════════════════════════╗');
  console.log(`║  AgenticQTC Dashboard  →  ${addr}   ║`);
  console.log('╚══════════════════════════════════════════════════╝\n');
  console.log('  • Click "Run Tests" in the browser to launch Playwright');
  console.log('  • Live terminal output streams in real-time via SSE');
  console.log('  • Results & bug report appear automatically after each run');
  console.log('\n  Press Ctrl+C to stop the server\n');

  // Open browser
  try {
    spawn('open', [addr], { detached: true, stdio: 'ignore' }).unref();
  } catch {}
});

server.on('error', err => {
  if (err.code === 'EADDRINUSE') {
    console.error(`\n❌ Port ${PORT} is already in use. Kill the existing server or change PORT.\n`);
  } else {
    console.error(err);
  }
  process.exit(1);
});
