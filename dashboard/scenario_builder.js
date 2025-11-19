let currentTemplate = null;

// Load templates on page load
window.addEventListener('load', loadTemplates);

async function loadTemplates() {
    try {
        const response = await fetch('/api/templates');
        const templates = await response.json();

        const grid = document.getElementById('templateGrid');
        grid.innerHTML = '';

        for (const [key, template] of Object.entries(templates)) {
            const card = document.createElement('div');
            card.className = 'template-card';
            card.onclick = () => selectTemplate(key, template);

            card.innerHTML = `
                <h3>${template.name}</h3>
                <p><strong>${template.num_nodes}</strong> nodes</p>
                <p>PV: ${(template.pv_penetration * 100).toFixed(0)}%</p>
                <p>Battery: ${(template.battery_penetration * 100).toFixed(0)}%</p>
                <p>Duration: ${template.duration_days.toFixed(0)} days</p>
                <p>Market: ${template.market_model}</p>
            `;

            grid.appendChild(card);
        }
    } catch (error) {
        console.error('Failed to load templates:', error);
    }
}

function selectTemplate(key, template) {
    currentTemplate = template;

    // Populate form with template values
    document.getElementById('scenarioName').value = template.name;
    document.getElementById('nodeCount').value = template.num_nodes;
    document.getElementById('pvPenetration').value = template.pv_penetration * 100;
    document.getElementById('batteryPenetration').value = template.battery_penetration * 100;
    document.getElementById('marketModel').value = template.market_model;

    updateNodeCount();
    updateSliders();

    // Show config panel
    document.getElementById('configPanel').style.display = 'block';
    document.getElementById('configPanel').scrollIntoView({ behavior: 'smooth' });
}

function loadCustom() {
    currentTemplate = null;
    document.getElementById('configPanel').style.display = 'block';
    document.getElementById('configPanel').scrollIntoView({ behavior: 'smooth' });
}

function updateNodeCount() {
    const value = document.getElementById('nodeCount').value;
    document.getElementById('nodeCountValue').textContent = value;
}

function updateNodeTypes() {
    const res = parseInt(document.getElementById('residentialSlider').value);
    const com = parseInt(document.getElementById('commercialSlider').value);
    const ind = parseInt(document.getElementById('industrialSlider').value);

    const total = res + com + ind;
    if (total > 0) {
        const normRes = Math.round(res / total * 100);
        const normCom = Math.round(com / total * 100);
        const normInd = 100 - normRes - normCom;

        document.getElementById('residentialValue').textContent = normRes;
        document.getElementById('commercialValue').textContent = normCom;
        document.getElementById('industrialValue').textContent = normInd;
    }
}

function updateSliders() {
    document.getElementById('pvPenValue').textContent = document.getElementById('pvPenetration').value;
    document.getElementById('battPenValue').textContent = document.getElementById('batteryPenetration').value;
    document.getElementById('coopValue').textContent = document.getElementById('cooperativeFraction').value;
}

async function generateScenario() {
    const statusSection = document.getElementById('statusSection');
    const statusMessage = document.getElementById('statusMessage');
    const progressBar = document.getElementById('progressBar');

    statusSection.style.display = 'block';
    progressBar.style.display = 'block';
    statusMessage.className = 'status-message status-info';
    statusMessage.textContent = 'Generating scenario...';

    try {
        const nodeCount = parseInt(document.getElementById('nodeCount').value);
        const resPercent = parseInt(document.getElementById('residentialValue').textContent);
        const comPercent = parseInt(document.getElementById('commercialValue').textContent);
        const indPercent = parseInt(document.getElementById('industrialValue').textContent);

        const scenario = {
            name: document.getElementById('scenarioName').value || 'Custom Scenario',
            num_nodes: nodeCount,
            node_types: {
                residential: Math.round(nodeCount * resPercent / 100),
                commercial: Math.round(nodeCount * comPercent / 100),
                industrial: Math.round(nodeCount * indPercent / 100)
            },
            pv_penetration: parseFloat(document.getElementById('pvPenetration').value) / 100,
            battery_penetration: parseFloat(document.getElementById('batteryPenetration').value) / 100,
            start_time: document.getElementById('startTime').value.replace('T', ' ') + ':00',
            end_time: document.getElementById('endTime').value.replace('T', ' ') + ':00',
            time_step_minutes: parseInt(document.getElementById('timeStep').value),
            latitude: 50.0,
            longitude: 10.0,
            season: 'summer',
            market_model: document.getElementById('marketModel').value,
            cooperative_fraction: parseFloat(document.getElementById('cooperativeFraction').value) / 100
        };

        const response = await fetch('/api/scenarios/generate', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(scenario)
        });

        const result = await response.json();

        progressBar.style.display = 'none';

        if (result.status === 'success') {
            statusMessage.className = 'status-message status-success';
            statusMessage.innerHTML = `
                <strong>Success!</strong> Scenario generated successfully.<br>
                <strong>Scenario ID:</strong> ${result.scenario_id}<br>
                <strong>Output Directory:</strong> ${result.output_dir}<br>
                <small>You can now run simulations with this scenario.</small>
            `;
        } else {
            throw new Error(result.message);
        }
    } catch (error) {
        progressBar.style.display = 'none';
        statusMessage.className = 'status-message status-error';
        statusMessage.innerHTML = `<strong>Error:</strong> ${error.message}`;
    }
}

function resetForm() {
    document.getElementById('scenarioName').value = '';
    document.getElementById('nodeCount').value = 10;
    document.getElementById('pvPenetration').value = 60;
    document.getElementById('batteryPenetration').value = 40;
    document.getElementById('cooperativeFraction').value = 80;
    updateNodeCount();
    updateSliders();
}
