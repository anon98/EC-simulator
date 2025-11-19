let communityChart = null;
let socChart = null;

async function loadData() {
    const model = document.getElementById('modelSelect').value;
    const filename = `data_${model}.json`;

    try {
        const response = await fetch(filename);
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        const data = await response.json();
        updateDashboard(data);
    } catch (e) {
        console.error("Could not load data:", e);
        alert("Could not load data for " + model + ". Make sure you have run the benchmark script first.");
    }
}

function updateDashboard(data) {
    // Update KPIs
    document.getElementById('ssrValue').textContent = (data.kpis["SSR"] * 100).toFixed(1) + "%";
    document.getElementById('scrValue').textContent = (data.kpis["SCR"] * 100).toFixed(1) + "%";
    document.getElementById('profitValue').textContent = data.kpis["Total Profit"].toFixed(2);
    document.getElementById('importValue').textContent = data.kpis["Total Import (kWh)"].toFixed(1);

    const times = data.results.times;
    const netTransactions = data.results.grid_interactions.map(row => row.reduce((a, b) => a + b, 0));

    // Prepare Chart Data
    updateCommunityChart(times, netTransactions);
    updateSocChart(times, data.results.battery_soc);
}

function updateCommunityChart(labels, data) {
    const ctx = document.getElementById('communityChart').getContext('2d');

    if (communityChart) {
        communityChart.destroy();
    }

    communityChart = new Chart(ctx, {
        type: 'line',
        data: {
            labels: labels,
            datasets: [{
                label: 'Net Community Transactions (kW)',
                data: data,
                borderColor: '#4a90e2',
                backgroundColor: 'rgba(74, 144, 226, 0.1)',
                fill: true,
                tension: 0.4
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                title: {
                    display: true,
                    text: 'Community Grid Interaction'
                }
            },
            scales: {
                x: { title: { display: true, text: 'Time (h)' } },
                y: { title: { display: true, text: 'Power (kW)' } }
            }
        }
    });
}

function updateSocChart(labels, socData) {
    const ctx = document.getElementById('socChart').getContext('2d');

    // socData is [steps][nodes], need to transpose or pick a few nodes
    // Let's plot average SOC
    const numNodes = socData[0].length;
    const avgSoc = socData.map(row => row.reduce((a, b) => a + b, 0) / numNodes);

    if (socChart) {
        socChart.destroy();
    }

    socChart = new Chart(ctx, {
        type: 'line',
        data: {
            labels: labels,
            datasets: [{
                label: 'Average Battery Energy (kWh)',
                data: avgSoc,
                borderColor: '#50e3c2',
                backgroundColor: 'rgba(80, 227, 194, 0.1)',
                fill: true,
                tension: 0.4
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                title: {
                    display: true,
                    text: 'Average Battery State of Charge'
                }
            },
            scales: {
                x: { title: { display: true, text: 'Time (h)' } },
                y: { title: { display: true, text: 'Energy (kWh)' } }
            }
        }
    });
}

// Load default on start
window.onload = loadData;
