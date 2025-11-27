let currentScenarioId = null;
let latestResultsData = null;
let nodeSocChart = null;
let flowChart = null;
let batteryNodeIndices = [];

async function runSimulation() {
    const scenarioId = document.getElementById('scenarioIdInput').value.trim();

    if (!scenarioId) {
        showStatus('Please enter a scenario ID', 'error');
        return;
    }

    showStatus('Running simulation... This may take a minute.', 'info');

    try {
        const marketModel = document.getElementById('marketModelSelect').value;

        const response = await fetch('/api/simulation/run', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                scenario_id: scenarioId,
                market_model: marketModel
            })
        });

        const result = await response.json();

        if (result.status === 'success') {
            currentScenarioId = scenarioId;

            if (result.kpis) {
                displayKPIs(result.kpis);
            }

            showStatus('Loading charts...', 'info');
            await loadResultsFile(scenarioId);
        } else {
            showStatus(`Error: ${result.message}`, 'error');
        }
    } catch (error) {
        showStatus(`Error: ${error.message}`, 'error');
    }
}

async function loadResultsFile(scenarioId) {
    try {
        const url = `/scenarios/${scenarioId}/simulation_results.json`;
        console.log(`Fetching results from: ${url}`);
        const response = await fetch(url);

        if (response.ok) {
            const data = await response.json();
            console.log('Results data received:', data);
            try {
                displayCharts(data);
                showStatus('Results loaded successfully!', 'success');
            } catch (chartError) {
                console.error('Chart rendering error:', chartError);
                showStatus(`Chart error: ${chartError.message}`, 'error');
            }
        } else {
            const errorText = await response.text();
            console.error(`Fetch failed: ${response.status} ${response.statusText}`, errorText);
            showStatus(`Failed to load results: ${response.status} ${response.statusText} - ${errorText}`, 'error');
        }
    } catch (error) {
        console.error('Network error:', error);
        showStatus(`Network error: ${error.message}`, 'error');
    }
}

function displayKPIs(kpis) {
    const setText = (id, value) => {
        const el = document.getElementById(id);
        if (el) el.textContent = value;
    };

    const fmtCurrency = (val) => typeof val === 'number' ? `€${val.toFixed(2)}` : '--';
    const fmtNum = (val) => typeof val === 'number' ? val.toFixed(1) : '--';
    const fmtPct = (val) => typeof val === 'number' ? `${(val * 100).toFixed(1)}%` : '--';

    const savings = kpis.community_savings_eur ?? kpis.cooperative_profit;
    setText('kpi-profit', fmtCurrency(savings));
    setText('kpi-gen', fmtNum(kpis.total_generation_kwh));
    setText('kpi-load', fmtNum(kpis.total_load_kwh));
    setText('kpi-import', fmtNum(kpis.grid_import_kwh ?? kpis.total_import_kwh));
    setText('kpi-export', fmtNum(kpis.grid_export_kwh ?? kpis.total_export_kwh));
    setText('kpi-ssr', fmtPct(kpis.ssr));
    setText('kpi-scr', fmtPct(kpis.scr));
}

function displayCharts(data) {
    if (!data.results) return;
    const summary = data.results;
    latestResultsData = data;

    const maxPoints = 200;
    const sampleRate = Math.max(1, Math.ceil(summary.time.length / maxPoints));

    const sampledTime = summary.time.filter((_, i) => i % sampleRate === 0);
    const sampledGen = summary.total_generation.filter((_, i) => i % sampleRate === 0);
    const sampledLoad = summary.total_load.filter((_, i) => i % sampleRate === 0);
    const sampledSOC = summary.battery_soc_avg
        ? summary.battery_soc_avg.filter((_, i) => i % sampleRate === 0)
        : [];
    const sampledImport = summary.grid_import_series ? summary.grid_import_series.filter((_, i) => i % sampleRate === 0) : [];
    const sampledExport = summary.grid_export_series ? summary.grid_export_series.filter((_, i) => i % sampleRate === 0) : [];
    const sampledTrade = summary.internal_trade ? summary.internal_trade.filter((_, i) => i % sampleRate === 0) : [];

    const ctx1 = document.getElementById('communityChart').getContext('2d');
    if (window.communityChart instanceof Chart) {
        window.communityChart.destroy();
    } else if (window.communityChart) {
        window.communityChart = null;
    }

    window.communityChart = new Chart(ctx1, {
        type: 'line',
        data: {
            labels: sampledTime,
            datasets: [{
                label: 'Generation',
                data: sampledGen,
                borderColor: '#f59e0b',
                backgroundColor: 'rgba(245,158,11,0.1)',
                fill: true,
                tension: 0.4
            }, {
                label: 'Load',
                data: sampledLoad,
                borderColor: '#3b82f6',
                backgroundColor: 'rgba(59,130,246,0.1)',
                fill: true,
                tension: 0.4
            }]
        },
        options: {
            responsive: true,
            plugins: { title: { display: true, text: 'Community Energy' } }
        }
    });

    renderFlowChart(sampledTime, sampledImport, sampledExport, sampledTrade);
    setupNodeSocControls(data);
}

function showStatus(message, type) {
    const bar = document.getElementById('statusBar');
    if (!bar) return;

    bar.textContent = message;
    bar.style.display = 'block';

    const colors = {
        success: { bg: '#d1fae5', color: '#065f46', border: '#10b981' },
        error: { bg: '#fee2e2', color: '#991b1b', border: '#ef4444' },
        info: { bg: '#dbeafe', color: '#1e40af', border: '#3b82f6' }
    };

    const c = colors[type] || colors.info;
    bar.style.background = c.bg;
    bar.style.color = c.color;
    bar.style.border = `2px solid ${c.border}`;

    if (type !== 'info') setTimeout(() => bar.style.display = 'none', 5000);
}

function renderFlowChart(labels, imports, exports, trade) {
    const ctx = document.getElementById('flowChart').getContext('2d');
    if (flowChart) {
        flowChart.destroy();
    }

    flowChart = new Chart(ctx, {
        type: 'line',
        data: {
            labels,
            datasets: [{
                label: 'Grid Import (kW)',
                data: imports,
                borderColor: '#ef4444',
                backgroundColor: 'rgba(239,68,68,0.1)',
                fill: true,
                tension: 0.3
            }, {
                label: 'Grid Export (kW)',
                data: exports,
                borderColor: '#3b82f6',
                backgroundColor: 'rgba(59,130,246,0.1)',
                fill: true,
                tension: 0.3
            }, {
                label: 'Internal Trade (kW)',
                data: trade,
                borderColor: '#f59e0b',
                backgroundColor: 'rgba(245,158,11,0.1)',
                fill: true,
                tension: 0.3
            }]
        },
        options: {
            responsive: true,
            plugins: { title: { display: true, text: 'Grid vs P2P Exchanges' } },
            scales: {
                x: { title: { display: true, text: 'Time (hours)' } },
                y: { title: { display: true, text: 'Power (kW)' } }
            }
        }
    });
}

function setupNodeSocControls(data) {
    const select = document.getElementById('nodeSocSelect');
    if (!select || !data.per_node) return;
    const socMatrix = data.per_node.battery_soc_pct;
    const mask = data.per_node.has_battery || [];
    if (!socMatrix || socMatrix.length === 0 || !socMatrix[0]) {
        select.innerHTML = '<option>No battery data</option>';
        batteryNodeIndices = [];
        renderNodeSocChart();
        return;
    }
    batteryNodeIndices = mask
        .map((has, idx) => has ? idx : -1)
        .filter(idx => idx >= 0);
    if (batteryNodeIndices.length === 0) {
        select.innerHTML = '<option>No battery data</option>';
        renderNodeSocChart();
        return;
    }
    select.innerHTML = '';
    batteryNodeIndices.forEach(idx => {
        const option = document.createElement('option');
        option.value = idx;
        option.textContent = `Node ${idx + 1}`;
        select.appendChild(option);
    });
    select.onchange = () => renderNodeSocChart(parseInt(select.value, 10));
    select.value = batteryNodeIndices[0];
    renderNodeSocChart(batteryNodeIndices[0]);
}

function renderNodeSocChart(nodeIndex) {
    if (!latestResultsData || !latestResultsData.per_node) return;
    if (!batteryNodeIndices || batteryNodeIndices.length === 0) {
        if (nodeSocChart) {
            nodeSocChart.destroy();
            nodeSocChart = null;
        }
        return;
    }
    const socMatrix = latestResultsData.per_node.battery_soc_pct;
    if (!socMatrix || socMatrix.length === 0 || !socMatrix[0]) return;
    const idx = batteryNodeIndices.includes(nodeIndex) ? nodeIndex : batteryNodeIndices[0];

    const labels = latestResultsData.results.time;
    const series = socMatrix.map(row => row[idx]);

    const ctx = document.getElementById('nodeSocChart').getContext('2d');
    if (nodeSocChart) {
        nodeSocChart.destroy();
    }

    nodeSocChart = new Chart(ctx, {
        type: 'line',
        data: {
            labels,
            datasets: [{
                label: `Node ${idx + 1} SOC (%)`,
                data: series,
                borderColor: '#10b981',
                backgroundColor: 'rgba(16,185,129,0.1)',
                fill: true,
                tension: 0.3
            }]
        },
        options: {
            responsive: true,
            plugins: { title: { display: true, text: 'Battery State of Charge' } },
            scales: { y: { min: 0, max: 100 } }
        }
    });
}
