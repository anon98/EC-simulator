# Data Schema Documentation

## Overview
This document describes the CSV file formats for loading data into the LEC Simulator.

## File Formats

### 1. Solar Generation Data
**Filename**: `solar_node_{node_id}.csv`

**Columns**:
- `timestamp` (string): ISO 8601 format "YYYY-MM-DD HH:MM:SS"
- `irradiance` (float): Solar irradiance in W/m²
- `generation` (float): PV generation in kW

**Example**:
```csv
timestamp,irradiance,generation
2024-01-01 00:00:00,0.0,0.0
2024-01-01 01:00:00,0.0,0.0
2024-01-01 08:00:00,245.3,12.26
2024-01-01 12:00:00,856.7,42.84
```

### 2. Load Profile Data
**Filename**: `load_node_{node_id}.csv`

**Columns**:
- `timestamp` (string): ISO 8601 format "YYYY-MM-DD HH:MM:SS"
- `consumption` (float): Electricity consumption in kW

**Example**:
```csv
timestamp,consumption
2024-01-01 00:00:00,2.5
2024-01-01 01:00:00,2.1
2024-01-01 08:00:00,8.3
2024-01-01 18:00:00,12.5
```

### 3. Price Data
**Filename**: `prices.csv`

**Columns**:
- `timestamp` (string): ISO 8601 format "YYYY-MM-DD HH:MM:SS"
- `grid_price` (float): Grid purchase price in €/kWh
- `feed_in_tariff` (float): Feed-in tariff in €/kWh

**Example**:
```csv
timestamp,grid_price,feed_in_tariff
2024-01-01 00:00:00,0.07,0.05
2024-01-01 08:00:00,0.15,0.05
2024-01-01 18:00:00,0.20,0.05
```

## Database Schema (Future)

### Tables

#### `solar_data`
- `id` (INTEGER PRIMARY KEY)
- `node_id` (INTEGER)
- `timestamp` (DATETIME)
- `irradiance` (REAL)
- `generation` (REAL)

#### `load_data`
- `id` (INTEGER PRIMARY KEY)
- `node_id` (INTEGER)
- `timestamp` (DATETIME)
- `consumption` (REAL)

#### `price_data`
- `id` (INTEGER PRIMARY KEY)
- `timestamp` (DATETIME)
- `grid_price` (REAL)
- `feed_in_tariff` (REAL)
