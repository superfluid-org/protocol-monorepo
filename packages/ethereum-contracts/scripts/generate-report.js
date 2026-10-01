#!/usr/bin/env node
/**
 * Consolidated Verification Report Generator
 *
 * Reads per-network bytecode-report.json and safe-pending-tx.json files
 * and generates a self-contained HTML report with:
 *   - Global overview tab with summary table (one row per network)
 *   - Per-network tabs with Safe tx details, verification summary, contract table
 *   - Expandable bytecode diff panels with hashes, similarity %, segment map, hex diff context
 *
 * Usage:
 *   node scripts/generate-report.js [options]
 *
 * Options:
 *   --input-dir <dir>    Base directory containing per-network subdirs (default: tmp/verification)
 *   --output <file>      Output HTML file path (default: <input-dir>/verification-report.html)
 *   --title <text>       Report title (default: "Governance Action Verification Report")
 *
 * Directory structure expected:
 *   <input-dir>/
 *     <network-name>/
 *       bytecode-report.json
 *       safe-pending-tx.json (optional)
 *
 * Single-network mode: if <input-dir> itself contains bytecode-report.json
 * (no subdirectories), it treats it as a single-network report.
 */

const fs = require("fs");
const path = require("path");

// --- Argument parsing ---
const args = process.argv.slice(2);
let inputDir = null;
let outputFile = null;
let reportTitle = "Governance Action Verification Report";

for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
        case "--input-dir":
            inputDir = args[++i];
            break;
        case "--output":
            outputFile = args[++i];
            break;
        case "--title":
            reportTitle = args[++i];
            break;
        case "--help":
            console.log("Usage: node scripts/generate-report.js [--input-dir <dir>] [--output <file>] [--title <text>]");
            process.exit(0);
    }
}

// Resolve paths relative to the ethereum-contracts package root
const contractsDir = path.resolve(__dirname, "..");
if (!inputDir) {
    inputDir = path.join(contractsDir, "tmp", "verification");
}
if (!path.isAbsolute(inputDir)) {
    inputDir = path.resolve(contractsDir, inputDir);
}
if (!outputFile) {
    outputFile = path.join(inputDir, "verification-report.html");
}
if (!path.isAbsolute(outputFile)) {
    outputFile = path.resolve(contractsDir, outputFile);
}

// --- Data loading ---

function tryReadJSON(filePath) {
    try {
        if (fs.existsSync(filePath)) {
            return JSON.parse(fs.readFileSync(filePath, "utf8"));
        }
    } catch (e) {
        console.error(`Warning: failed to parse ${filePath}: ${e.message}`);
    }
    return null;
}

function discoverNetworks(baseDir) {
    const networks = [];

    // Single-network mode: bytecode-report.json directly in baseDir
    const directReport = path.join(baseDir, "bytecode-report.json");
    if (fs.existsSync(directReport)) {
        const bytecodeReport = tryReadJSON(directReport);
        const safeTx = tryReadJSON(path.join(baseDir, "safe-pending-tx.json"));
        const networkName = path.basename(baseDir);
        networks.push({
            name: networkName,
            bytecodeReport,
            safeTx,
        });
        return networks;
    }

    // Multi-network mode: subdirectories
    if (!fs.existsSync(baseDir)) {
        console.error(`Error: input directory not found: ${baseDir}`);
        process.exit(1);
    }

    const entries = fs.readdirSync(baseDir, { withFileTypes: true });
    for (const entry of entries) {
        if (!entry.isDirectory()) continue;
        const subDir = path.join(baseDir, entry.name);
        const report = tryReadJSON(path.join(subDir, "bytecode-report.json"));
        if (!report) continue;
        const safeTx = tryReadJSON(path.join(subDir, "safe-pending-tx.json"));
        networks.push({
            name: entry.name,
            bytecodeReport: report,
            safeTx,
        });
    }

    // Sort alphabetically
    networks.sort((a, b) => a.name.localeCompare(b.name));
    return networks;
}

const networks = discoverNetworks(inputDir);

if (networks.length === 0) {
    console.error("Error: no verification data found in " + inputDir);
    process.exit(1);
}

console.error(`Found ${networks.length} network(s): ${networks.map(n => n.name).join(", ")}`);

// --- HTML generation ---

function esc(str) {
    if (str === null || str === undefined) return "";
    return String(str)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");
}

function statusBadge(status) {
    const colors = {
        verified: "#22c55e",
        mismatch: "#ef4444",
        not_deployed: "#f59e0b",
        no_artifact: "#8b5cf6",
        error: "#ef4444",
    };
    const labels = {
        verified: "Verified",
        mismatch: "Mismatch",
        not_deployed: "Not Deployed",
        no_artifact: "No Artifact",
        error: "Error",
    };
    const bg = colors[status] || "#6b7280";
    const label = labels[status] || status;
    return `<span class="badge" style="background:${bg}">${esc(label)}</span>`;
}

function networkOverallStatus(report) {
    if (!report) return "no-data";
    const s = report.summary;
    if (s.mismatch > 0 || s.errors > 0) return "fail";
    if (s.verified > 0 && s.mismatch === 0 && s.errors === 0) return "pass";
    return "warn";
}

function renderSegmentMap(segmentMap) {
    if (!segmentMap) return "";
    // Render as a color bar: = is green, X is red
    let html = '<div class="segment-map" title="Each block = 32 bytes. Green = match, Red = different">';
    for (const ch of segmentMap) {
        const cls = ch === "=" ? "seg-match" : "seg-diff";
        html += `<span class="${cls}"></span>`;
    }
    html += "</div>";
    return html;
}

function renderDiffContext(diffContext) {
    if (!diffContext) return "<em>No diff context</em>";
    return `<div class="diff-context">
        <div><strong>Deployed:</strong> <code>${esc(diffContext.deployed)}</code></div>
        <div><strong>Expected:</strong> <code>${esc(diffContext.expected)}</code></div>
    </div>`;
}

function renderBytecodePanel(contract) {
    const bc = contract.bytecodeComparison;
    if (!bc) return '<div class="bc-panel-empty">No bytecode comparison data available</div>';

    return `<div class="bc-panel">
        <table class="bc-table">
            <tr><td>Match Method</td><td><strong>${esc(bc.matchMethod)}</strong></td></tr>
            <tr><td>Similarity</td><td><strong>${bc.similarityPercent}%</strong></td></tr>
            <tr><td>Deployed Size</td><td>${bc.deployedLength.toLocaleString()} bytes</td></tr>
            <tr><td>Expected Size</td><td>${bc.expectedLength.toLocaleString()} bytes</td></tr>
            <tr><td>Deployed SHA-256</td><td><code class="hash">${esc(bc.deployedHash)}</code></td></tr>
            <tr><td>Expected SHA-256</td><td><code class="hash">${esc(bc.expectedHash)}</code></td></tr>
            <tr><td>Immutables</td><td>${(bc.immutables && bc.immutables.length) || 0} variables extracted</td></tr>
            <tr><td>Metadata</td><td>${bc.metadata ? (bc.metadata.solcMatch ? 'Solc <code>' + esc(bc.metadata.deployedSolcVersion) + '</code> verified' : '<span style="color:var(--red)">Solc mismatch: deployed=' + esc(bc.metadata.deployedSolcVersion) + ' expected=' + esc(bc.metadata.expectedSolcVersion) + '</span>') : 'N/A'}</td></tr>
            <tr><td>First Diff Offset</td><td>${bc.firstDiffOffset !== null ? bc.firstDiffOffset + " bytes" : "N/A (identical)"}</td></tr>
        </table>
        ${bc.immutables && bc.immutables.length > 0 ? `<div class="bc-section">
            <strong>Extracted Immutable Values</strong> <span class="hint">(from deployed bytecode — verify these independently)</span>
            <table class="imm-table">
                <thead><tr><th>Variable</th><th>Value</th><th>Positions (byte offset)</th></tr></thead>
                <tbody>${bc.immutables.map(imm =>
                    `<tr><td>${esc(imm.name)}</td><td><code class="hash">${esc(imm.value)}</code></td><td>${imm.positions.join(", ")}</td></tr>`
                ).join("")}</tbody>
            </table>
        </div>` : ""}
        ${bc.metadata ? `<div class="bc-section">
            <strong>Compiler Metadata</strong> <span class="hint">(IPFS hash differs between compilations — expected; solc version must match)</span>
            <table class="imm-table">
                <thead><tr><th></th><th>Deployed</th><th>Expected</th><th>Status</th></tr></thead>
                <tbody>
                    <tr>
                        <td>Solc Version</td>
                        <td><code>${esc(bc.metadata.deployedSolcVersion)}</code></td>
                        <td><code>${esc(bc.metadata.expectedSolcVersion)}</code></td>
                        <td>${bc.metadata.solcMatch ? '<span class="badge" style="background:#22c55e">Match</span>' : '<span class="badge" style="background:#ef4444">MISMATCH</span>'}</td>
                    </tr>
                    <tr>
                        <td>IPFS Hash</td>
                        <td><code class="hash">${esc(bc.metadata.deployedIpfsHash)}</code></td>
                        <td><code class="hash">${esc(bc.metadata.expectedIpfsHash)}</code></td>
                        <td>${bc.metadata.ipfsMatch ? '<span class="badge" style="background:#22c55e">Match</span>' : '<span class="badge" style="background:#6366f1">Differs</span>'}</td>
                    </tr>
                </tbody>
            </table>
        </div>` : ""}
        <div class="bc-section">
            <strong>Segment Map</strong> <span class="hint">(each block = 32 bytes; green = match, red = diff)</span>
            ${renderSegmentMap(bc.segmentMap)}
        </div>
        ${bc.diffContext ? `<div class="bc-section">
            <strong>Hex Context Around First Divergence</strong>
            ${renderDiffContext(bc.diffContext)}
        </div>` : ""}
    </div>`;
}

function renderContractTable(contracts) {
    if (!contracts || contracts.length === 0) {
        return "<p>No contracts verified.</p>";
    }

    let html = `<table class="contracts-table">
        <thead><tr>
            <th>Contract</th>
            <th>Address</th>
            <th>Status</th>
            <th>Message</th>
            <th>Details</th>
        </tr></thead><tbody>`;

    for (const c of contracts) {
        const hasComparison = !!c.bytecodeComparison;
        const rowId = `bc-${c.key}-${c.address}`.replace(/[^a-zA-Z0-9-]/g, "_");
        html += `<tr>
            <td><strong>${esc(c.key)}</strong><br><small>${esc(c.contractName)}</small></td>
            <td><code class="addr">${esc(c.address)}</code></td>
            <td>${statusBadge(c.status)}</td>
            <td>${esc(c.message)}</td>
            <td>${hasComparison ? `<button class="expand-btn" onclick="togglePanel('${rowId}')">Inspect</button>` : "-"}</td>
        </tr>`;
        if (hasComparison) {
            html += `<tr id="${rowId}" class="bc-row" style="display:none">
                <td colspan="5">${renderBytecodePanel(c)}</td>
            </tr>`;
        }
    }

    html += "</tbody></table>";
    return html;
}

function renderSafeTx(safeTx) {
    if (!safeTx) return "";

    const tx = safeTx.transaction || {};
    const decoded = safeTx.decodedAction || {};
    const extracted = safeTx.extractedAddresses || {};

    let html = `<div class="safe-tx-card">
        <h3>Pending Safe Transaction</h3>
        <table class="info-table">
            <tr><td>Safe</td><td><code>${esc(safeTx.safe)}</code></td></tr>
            <tr><td>Nonce</td><td>${tx.nonce !== undefined ? tx.nonce : "N/A"}</td></tr>
            <tr><td>To</td><td><code>${esc(tx.to)}</code></td></tr>
            <tr><td>Confirmations</td><td>${tx.confirmations || 0} / ${tx.confirmationsRequired || "?"}</td></tr>
            <tr><td>Function</td><td><strong>${esc(decoded.functionName || "unknown")}</strong></td></tr>
            <tr><td>Submitted</td><td>${esc(tx.submissionDate)}</td></tr>
        </table>`;

    const addrEntries = Object.entries(extracted);
    if (addrEntries.length > 0) {
        html += `<h4>Extracted Addresses</h4><table class="info-table">`;
        for (const [key, val] of addrEntries) {
            html += `<tr><td>${esc(key)}</td><td><code>${esc(val)}</code></td></tr>`;
        }
        html += `</table>`;
    }

    html += `</div>`;
    return html;
}

function renderNetworkTab(network) {
    const report = network.bytecodeReport;
    const s = report.summary;
    const status = networkOverallStatus(report);
    const statusLabel = status === "pass" ? "PASSED" : status === "fail" ? "FAILED" : "WARNING";
    const statusColor = status === "pass" ? "#22c55e" : status === "fail" ? "#ef4444" : "#f59e0b";

    let html = `<div class="network-content" id="net-${esc(network.name)}">
        <div class="network-header">
            <h2>${esc(network.name)} <span class="overall-badge" style="background:${statusColor}">${statusLabel}</span></h2>
            <div class="meta">Chain ID: ${report.network} | Verified at: ${esc(report.timestamp)}</div>
        </div>
        <div class="summary-cards">
            <div class="card card-total"><div class="card-value">${s.total}</div><div class="card-label">Total</div></div>
            <div class="card card-verified"><div class="card-value">${s.verified}</div><div class="card-label">Verified</div></div>
            <div class="card card-mismatch"><div class="card-value">${s.mismatch}</div><div class="card-label">Mismatch</div></div>
            <div class="card card-errors"><div class="card-value">${s.errors}</div><div class="card-label">Errors</div></div>
            <div class="card card-other"><div class="card-value">${s.notDeployed}</div><div class="card-label">Not Deployed</div></div>
            <div class="card card-other"><div class="card-value">${s.noArtifact}</div><div class="card-label">No Artifact</div></div>
        </div>
        ${renderSafeTx(network.safeTx)}
        <h3>Contract Verification</h3>
        ${renderContractTable(report.contracts)}
    </div>`;
    return html;
}

function renderOverviewTable(networks) {
    let html = `<table class="overview-table">
        <thead><tr>
            <th>Network</th>
            <th>Chain ID</th>
            <th>Status</th>
            <th>Verified</th>
            <th>Mismatch</th>
            <th>Errors</th>
            <th>Total</th>
            <th>Safe TX</th>
        </tr></thead><tbody>`;

    for (const n of networks) {
        const report = n.bytecodeReport;
        const s = report.summary;
        const status = networkOverallStatus(report);
        const statusLabel = status === "pass" ? "PASS" : status === "fail" ? "FAIL" : "WARN";
        const statusColor = status === "pass" ? "#22c55e" : status === "fail" ? "#ef4444" : "#f59e0b";
        const hasSafe = n.safeTx ? "Yes" : "No";

        html += `<tr class="overview-row" onclick="showTab('${esc(n.name)}')">
            <td><strong>${esc(n.name)}</strong></td>
            <td>${report.network}</td>
            <td><span class="badge" style="background:${statusColor}">${statusLabel}</span></td>
            <td>${s.verified}</td>
            <td class="${s.mismatch > 0 ? "text-red" : ""}">${s.mismatch}</td>
            <td class="${s.errors > 0 ? "text-red" : ""}">${s.errors}</td>
            <td>${s.total}</td>
            <td>${hasSafe}</td>
        </tr>`;
    }

    html += `</tbody></table>`;
    return html;
}

function generateHTML(networks, title) {
    const now = new Date().toISOString();
    const hasMultiple = networks.length > 1;

    // Build tab buttons
    let tabButtons = "";
    if (hasMultiple) {
        tabButtons = `<button class="tab-btn active" onclick="showTab('overview')">Overview</button>`;
    }
    for (const n of networks) {
        const status = networkOverallStatus(n.bytecodeReport);
        const dot = status === "pass" ? "&#x2705;" : status === "fail" ? "&#x274C;" : "&#x26A0;&#xFE0F;";
        const activeClass = !hasMultiple ? " active" : "";
        tabButtons += `<button class="tab-btn${activeClass}" onclick="showTab('${esc(n.name)}')">${dot} ${esc(n.name)}</button>`;
    }

    // Build tab contents
    let tabContents = "";
    if (hasMultiple) {
        tabContents += `<div class="tab-content active" id="tab-overview">
            <h2>All Networks Overview</h2>
            ${renderOverviewTable(networks)}
        </div>`;
    }
    for (const n of networks) {
        const activeClass = !hasMultiple ? " active" : "";
        tabContents += `<div class="tab-content${activeClass}" id="tab-${esc(n.name)}">
            ${renderNetworkTab(n)}
        </div>`;
    }

    // Embed all data as JSON for programmatic access
    const jsonData = JSON.stringify(networks.map(n => ({
        name: n.name,
        bytecodeReport: n.bytecodeReport,
        safeTx: n.safeTx,
    })));

    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${esc(title)}</title>
<style>
:root {
    --bg: #0f1117;
    --surface: #1a1d27;
    --surface2: #252836;
    --border: #2e3142;
    --text: #e2e4ed;
    --text-dim: #8b8fa3;
    --accent: #6366f1;
    --green: #22c55e;
    --red: #ef4444;
    --yellow: #f59e0b;
    --purple: #8b5cf6;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background: var(--bg);
    color: var(--text);
    line-height: 1.5;
    padding: 0;
}
.header {
    background: var(--surface);
    border-bottom: 1px solid var(--border);
    padding: 20px 32px;
}
.header h1 { font-size: 1.4rem; font-weight: 600; }
.header .meta { color: var(--text-dim); font-size: 0.85rem; margin-top: 4px; }
.tabs {
    display: flex;
    gap: 2px;
    background: var(--surface);
    padding: 0 32px;
    border-bottom: 1px solid var(--border);
    overflow-x: auto;
    flex-wrap: nowrap;
}
.tab-btn {
    background: transparent;
    border: none;
    color: var(--text-dim);
    padding: 10px 16px;
    cursor: pointer;
    font-size: 0.875rem;
    white-space: nowrap;
    border-bottom: 2px solid transparent;
    transition: all 0.15s;
}
.tab-btn:hover { color: var(--text); background: var(--surface2); }
.tab-btn.active { color: var(--accent); border-bottom-color: var(--accent); }
.tab-content { display: none; padding: 24px 32px; }
.tab-content.active { display: block; }
.network-header { margin-bottom: 20px; }
.network-header h2 { font-size: 1.2rem; display: flex; align-items: center; gap: 10px; }
.network-header .meta { color: var(--text-dim); font-size: 0.8rem; margin-top: 4px; }
.overall-badge {
    font-size: 0.7rem;
    font-weight: 700;
    padding: 2px 10px;
    border-radius: 4px;
    color: #fff;
    letter-spacing: 0.05em;
}
.summary-cards {
    display: flex;
    gap: 12px;
    margin-bottom: 24px;
    flex-wrap: wrap;
}
.card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 16px 20px;
    min-width: 100px;
    text-align: center;
}
.card-value { font-size: 1.8rem; font-weight: 700; }
.card-label { font-size: 0.75rem; color: var(--text-dim); text-transform: uppercase; letter-spacing: 0.05em; }
.card-verified .card-value { color: var(--green); }
.card-mismatch .card-value { color: var(--red); }
.card-errors .card-value { color: var(--red); }
.card-total .card-value { color: var(--accent); }
.card-other .card-value { color: var(--text-dim); }

table { width: 100%; border-collapse: collapse; }
th, td { text-align: left; padding: 10px 12px; border-bottom: 1px solid var(--border); }
th { background: var(--surface); color: var(--text-dim); font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.05em; font-weight: 600; }
td { font-size: 0.875rem; }
.overview-table { background: var(--surface); border-radius: 8px; overflow: hidden; }
.overview-row { cursor: pointer; transition: background 0.1s; }
.overview-row:hover { background: var(--surface2); }
.contracts-table { background: var(--surface); border-radius: 8px; overflow: hidden; }

.badge {
    display: inline-block;
    font-size: 0.7rem;
    font-weight: 700;
    padding: 2px 8px;
    border-radius: 4px;
    color: #fff;
    letter-spacing: 0.03em;
}
.text-red { color: var(--red); font-weight: 600; }
code { font-family: "JetBrains Mono", "Fira Code", monospace; font-size: 0.8rem; }
.addr { word-break: break-all; }
.hash { word-break: break-all; font-size: 0.7rem; color: var(--text-dim); }
.expand-btn {
    background: var(--surface2);
    border: 1px solid var(--border);
    color: var(--accent);
    padding: 4px 12px;
    border-radius: 4px;
    cursor: pointer;
    font-size: 0.8rem;
    transition: all 0.15s;
}
.expand-btn:hover { background: var(--accent); color: #fff; }
.bc-row td { padding: 0; background: var(--bg); }
.bc-panel { padding: 16px 20px; }
.bc-panel-empty { padding: 12px; color: var(--text-dim); font-style: italic; }
.bc-table { width: auto; margin-bottom: 12px; }
.bc-table td { padding: 4px 12px 4px 0; border: none; font-size: 0.85rem; }
.bc-table td:first-child { color: var(--text-dim); white-space: nowrap; }
.bc-section { margin-top: 12px; }
.bc-section strong { font-size: 0.85rem; }
.hint { color: var(--text-dim); font-size: 0.75rem; }
.segment-map {
    display: flex;
    flex-wrap: wrap;
    gap: 1px;
    margin-top: 6px;
    max-height: 80px;
    overflow-y: auto;
    padding: 4px;
    background: var(--surface);
    border-radius: 4px;
}
.segment-map span {
    width: 6px;
    height: 12px;
    display: inline-block;
    border-radius: 1px;
}
.seg-match { background: var(--green); opacity: 0.7; }
.seg-diff { background: var(--red); opacity: 0.9; }
.diff-context {
    margin-top: 8px;
    background: var(--surface);
    border-radius: 4px;
    padding: 10px 12px;
    font-size: 0.8rem;
    overflow-x: auto;
}
.diff-context div { margin-bottom: 4px; }
.imm-table { margin-top: 6px; }
.imm-table th { font-size: 0.7rem; padding: 4px 8px; }
.imm-table td { font-size: 0.8rem; padding: 4px 8px; }
.diff-context code { color: var(--text); }

.safe-tx-card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 16px 20px;
    margin-bottom: 24px;
}
.safe-tx-card h3 { font-size: 1rem; margin-bottom: 10px; }
.safe-tx-card h4 { font-size: 0.85rem; margin: 12px 0 6px; color: var(--text-dim); }
.info-table { width: auto; }
.info-table td { padding: 3px 12px 3px 0; border: none; font-size: 0.85rem; }
.info-table td:first-child { color: var(--text-dim); white-space: nowrap; }

@media (max-width: 768px) {
    .tabs { padding: 0 12px; }
    .tab-content { padding: 16px 12px; }
    .header { padding: 16px 12px; }
    .summary-cards { gap: 8px; }
    .card { min-width: 70px; padding: 10px 8px; }
    .card-value { font-size: 1.3rem; }
}
</style>
</head>
<body>
<div class="header">
    <h1>${esc(title)}</h1>
    <div class="meta">Generated: ${esc(now)} | Networks: ${networks.length}</div>
</div>
<div class="tabs">${tabButtons}</div>
${tabContents}
<script>
var DATA = ${jsonData};

function showTab(name) {
    document.querySelectorAll('.tab-content').forEach(function(el) { el.classList.remove('active'); });
    document.querySelectorAll('.tab-btn').forEach(function(el) { el.classList.remove('active'); });

    var tabId = name === 'overview' ? 'tab-overview' : 'tab-' + name;
    var tab = document.getElementById(tabId);
    if (tab) tab.classList.add('active');

    // Activate corresponding button
    document.querySelectorAll('.tab-btn').forEach(function(btn) {
        if (btn.textContent.indexOf(name) !== -1 || (name === 'overview' && btn.textContent === 'Overview')) {
            btn.classList.add('active');
        }
    });
}

function togglePanel(id) {
    var row = document.getElementById(id);
    if (!row) return;
    if (row.style.display === 'none') {
        row.style.display = 'table-row';
    } else {
        row.style.display = 'none';
    }
}
</script>
</body>
</html>`;
}

// --- Main ---
const html = generateHTML(networks, reportTitle);
fs.mkdirSync(path.dirname(outputFile), { recursive: true });
fs.writeFileSync(outputFile, html, "utf8");
console.error(`Report generated: ${outputFile}`);
