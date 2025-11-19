# generate_sample_data.jl
# Script to generate sample CSV files for the LEC simulator

push!(LOAD_PATH, joinpath(@__DIR__, "src"))

using Dates
using CSV
using DataFrames
using LECSimulator

include("src/data_schema.jl")
include("src/data_generation.jl")

using .DataSchema
using .DataGeneration

function main()
    println("Generating sample data...")
    
    # Simulation parameters
    start_time = DateTime(2024, 1, 1, 0, 0, 0)
    end_time = DateTime(2024, 1, 7, 23, 0, 0)  # 1 week
    interval = Hour(1)
    
    # Create data directory
    mkpath("data")
    
    # Generate price data (common for all nodes)
    println("Generating price data...")
    price_ts = generate_price_profile(start_time, end_time, interval)
    price_df = DataFrame(
        timestamp = [p.timestamp for p in price_ts.data],
        grid_price = [p.grid_price for p in price_ts.data],
        feed_in_tariff = [p.feed_in_tariff for p in price_ts.data]
    )
    CSV.write("data/prices.csv", price_df)
    
    # Node configurations
    nodes_config = [
        (id=1, type="residential", pv_capacity=5.0),
        (id=2, type="residential", pv_capacity=7.0),
        (id=3, type="commercial", pv_capacity=15.0),
        (id=4, type="residential", pv_capacity=6.0),
    ]
    
    # Generate data for each node
    for node in nodes_config
        println("Generating data for node $(node.id) ($(node.type))...")
        
        # Solar data
        if node.pv_capacity > 0
            solar_ts = generate_solar_profile(node.id, node.pv_capacity, start_time, end_time, interval)
            solar_df = DataFrame(
                timestamp = [s.timestamp for s in solar_ts.data],
                irradiance = [s.irradiance for s in solar_ts.data],
                generation = [s.generation for s in solar_ts.data]
            )
            CSV.write("data/solar_node_$(node.id).csv", solar_df)
        end
        
        # Load data
        load_ts = generate_load_profile(node.id, node.type, start_time, end_time, interval)
        load_df = DataFrame(
            timestamp = [l.timestamp for l in load_ts.data],
            consumption = [l.consumption for l in load_ts.data]
        )
        CSV.write("data/load_node_$(node.id).csv", load_df)
    end
    
    println("\nSample data generation complete!")
    println("Files created in 'data/' directory")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
