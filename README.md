# LEC Simulator

A modular Julia package for simulating Local Energy Communities (LECs) and benchmarking different Local Energy Market (LEM) models.

## Features
- **Modular Architecture**: Easily extensible components for PV, Battery, and Load.
- **Realistic Data Models**: Physics-based solar generation, time-of-day load profiles, and dynamic pricing.
- **Flexible Data Loading**: Load from CSV files or databases, or use built-in generation.
- **Market Benchmarking**: Compare different market mechanisms:
    - P2P Nash Bargaining
    - Community Self-Consumption
    - SDR Pricing
    - Pay-as-Clear Auction
- **Visualization**: Built-in plotting and a web-based dashboard.

## Installation
```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
```

## Usage

### Interactive Scenario Generator (Recommended)
Launch the interactive web application to create and manage scenarios:
```bash
julia scenario_app.jl
```

This will:
1. Start an HTTP server on port 8080
2. Automatically open your browser to the scenario builder
3. Allow you to configure custom scenarios or use templates
4. Generate complete datasets with one click

**Features:**
- Choose from predefined templates (small/medium/large communities)
- Configure all parameters via interactive sliders and controls
- Real-time validation
- One-click scenario generation
- Auto-opens in your default browser

### Generating Sample Data
First, generate realistic sample data in CSV format:
```bash
julia generate_sample_data.jl
```

This creates CSV files in the `data/` directory with realistic solar, load, and price profiles.

### Running a Single Simulation
```bash
julia src/main.jl
```

### Running the Benchmark
```bash
julia src/benchmark.jl
```
This will run all market models defined in the script and generate a comparison plot. It also exports JSON data for the dashboard.

### Using the Dashboard
1. Run the benchmark script first to generate data.
2. Open `dashboard/index.html` in a web browser.
   *Note: Due to CORS restrictions, you may need to run a local server (e.g., `python -m http.server` inside the `dashboard` directory).*

## Data Sources

The simulator supports multiple data sources:

### 1. Generated Data (Built-in)
Use the realistic data generation functions for quick testing:
```julia
using LECSimulator
solar_data = generate_solar_profile(node_id, pv_capacity, start_time, end_time, interval)
```

### 2. CSV Files
Load from CSV files (see `data/schema.md` for format):
```julia
loader = CSVDataLoader("data/")
solar_data = load_solar_data(loader, node_id, start_time, end_time)
```

### 3. Database (Future)
Database loader interface is defined but not yet implemented.

## Adding New Market Models
1. Define a new struct in `src/types.jl` inheriting from `AbstractMarketModel`.
2. Implement a method `solve_market(model::YourNewModel, ...)` in `src/market.jl`.
3. Update `src/utils.jl` to parse the new model name from config.
