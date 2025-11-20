let currentScenarioId = null;

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

function displayKPIs(data) {
    const kpis = data; // data IS the kpis object in the new structure

    // Helper to safely set text content
    const setText = (id, value) => {
        const el = document.getElementById(id);
        if (el) el.textContent = value;
    };

    // Helper formatters
    const fmtCurrency = (val) => val !== undefined ? `€${val.toFixed(2)}` : '--';
    const fmtNum = (val) => val !== undefined ? val.toFixed(1) : '--';

    setText('kpi-profit', fmtCurrency(kpis.cooperative_profit));
    setText('kpi-traded', fmtNum(kpis.total_energy_traded));
    setText('kpi-price', fmtCurrency(kpis.average_price));

    setText('kpi-gen', fmtNum(kpis.total_generation));
    setText('kpi-load', fmtNum(kpis.total_load));
    setText('kpi-export', fmtNum(kpis.total_export));
}

function displayCharts(data) {
    if (!data.results) return;

    const maxPoints = 100;
    const sampleRate = Math.ceil(data.results.time.length / maxPoints);

    const sampledTime = data.results.time.filter((_, i) => i % sampleRate === 0);
    const sampledGen = data.results.total_generation.filter((_, i) => i % sampleRate === 0);
    const sampledLoad = data.results.total_load.filter((_, i) => i % sampleRate === 0);
    const sampledSOC = data.results.battery_soc ? data.results.battery_soc.filter((_, i) => i % sampleRate === 0) : [];

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

    if (sampledSOC.length > 0) {
        const ctx2 = document.getElementById('socChart').getContext('2d');
        if (window.socChart instanceof Chart) {
            window.socChart.destroy();
        } else if (window.socChart) {
            window.socChart = null;
        }

        window.socChart = new Chart(ctx2, {
            type: 'line',
            data: {
                labels: sampledTime,
                datasets: [{
                    label: 'Battery SOC (%)',
                    data: sampledSOC,
                    borderColor: '#10b981',
                    backgroundColor: 'rgba(16,185,129,0.1)',
                    fill: true,
                    tension: 0.4
                }]
            },
            options: {
                responsive: true,
                plugins: { title: { display: true, text: 'Battery SOC' } },
                scales: { y: { beginAtZero: true, max: 100 } }
            }
        });
    }
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
