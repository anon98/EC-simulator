module DataLoaders

using Dates
using CSV
using DataFrames
using ..DataSchema

export AbstractDataLoader, CSVDataLoader, DatabaseLoader
export load_solar_data, load_load_data, load_price_data

# Abstract interface
abstract type AbstractDataLoader end

# CSV Data Loader
struct CSVDataLoader <: AbstractDataLoader
    data_dir::String
end

function load_solar_data(loader::CSVDataLoader, node_id::Int, start_time::DateTime, end_time::DateTime)
    filepath = joinpath(loader.data_dir, "solar_node_$(node_id).csv")
    
    if !isfile(filepath)
        error("Solar data file not found: $filepath")
    end
    
    df = CSV.read(filepath, DataFrame)
    
    # Parse timestamps
    df.timestamp = DateTime.(df.timestamp, "yyyy-mm-dd HH:MM:SS")
    
    # Filter by time range
    df_filtered = filter(row -> start_time <= row.timestamp <= end_time, df)
    
    # Convert to SolarDataPoint
    data = [SolarDataPoint(row.timestamp, row.irradiance, row.generation) for row in eachrow(df_filtered)]
    
    interval = if length(data) > 1
        data[2].timestamp - data[1].timestamp
    else
        Hour(1)
    end
    
    return TimeSeriesData(data, start_time, end_time, interval)
end

function load_load_data(loader::CSVDataLoader, node_id::Int, start_time::DateTime, end_time::DateTime)
    filepath = joinpath(loader.data_dir, "load_node_$(node_id).csv")
    
    if !isfile(filepath)
        error("Load data file not found: $filepath")
    end
    
    df = CSV.read(filepath, DataFrame)
    df.timestamp = DateTime.(df.timestamp, "yyyy-mm-dd HH:MM:SS")
    df_filtered = filter(row -> start_time <= row.timestamp <= end_time, df)
    
    data = [LoadDataPoint(row.timestamp, node_id, row.consumption) for row in eachrow(df_filtered)]
    
    interval = if length(data) > 1
        data[2].timestamp - data[1].timestamp
    else
        Hour(1)
    end
    
    return TimeSeriesData(data, start_time, end_time, interval)
end

function load_price_data(loader::CSVDataLoader, start_time::DateTime, end_time::DateTime)
    filepath = joinpath(loader.data_dir, "prices.csv")
    
    if !isfile(filepath)
        error("Price data file not found: $filepath")
    end
    
    df = CSV.read(filepath, DataFrame)
    df.timestamp = DateTime.(df.timestamp, "yyyy-mm-dd HH:MM:SS")
    df_filtered = filter(row -> start_time <= row.timestamp <= end_time, df)
    
    data = [PriceDataPoint(row.timestamp, row.grid_price, row.feed_in_tariff) for row in eachrow(df_filtered)]
    
    interval = if length(data) > 1
        data[2].timestamp - data[1].timestamp
    else
        Hour(1)
    end
    
    return TimeSeriesData(data, start_time, end_time, interval)
end

# Database Loader (SQLite stub)
struct DatabaseLoader <: AbstractDataLoader
    db_path::String
end

function load_solar_data(loader::DatabaseLoader, node_id::Int, start_time::DateTime, end_time::DateTime)
    # TODO: Implement SQLite/PostgreSQL connection
    # For now, throw informative error
    error("DatabaseLoader not yet implemented. Use CSVDataLoader or implement database connection.")
end

function load_load_data(loader::DatabaseLoader, node_id::Int, start_time::DateTime, end_time::DateTime)
    error("DatabaseLoader not yet implemented. Use CSVDataLoader or implement database connection.")
end

function load_price_data(loader::DatabaseLoader, start_time::DateTime, end_time::DateTime)
    error("DatabaseLoader not yet implemented. Use CSVDataLoader or implement database connection.")
end

end
