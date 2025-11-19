module ScenarioGenerator

using Dates
using Random
using CSV
using DataFrames
using JSON

# Note: Assumes ScenarioConfig, DataSchema, DataGeneration are already loaded
using ..ScenarioConfig
using ..DataSchema
using ..DataGeneration

export generate_scenario, export_scenario

function generate_scenario(scenario::Scenario; output_dir::String="scenarios/$(scenario.name)")
    println("Generating scenario: $(scenario.name)")
    mkpath(output_dir)
    mkpath(joinpath(output_dir, "data"))
    
    # Calculate time parameters
    interval = Minute(scenario.time_step_minutes)
    
    # Determine node distribution
    node_assignments = assign_nodes(scenario)
    
    # Generate price data (common for all)
    println("  Generating price data...")
    price_ts = generate_price_profile(scenario.start_time, scenario.end_time, interval)
    price_df = DataFrame(
        timestamp = [p.timestamp for p in price_ts.data],
        grid_price = [p.grid_price for p in price_ts.data],
        feed_in_tariff = [p.feed_in_tariff for p in price_ts.data]
    )
    CSV.write(joinpath(output_dir, "data", "prices.csv"), price_df)
    
    # Generate per-node data
    pv_nodes = Int[]
    battery_nodes = Int[]
    cooperative_nodes = Int[]
    
    for (i, assignment) in enumerate(node_assignments)
        println("  Generating data for node $i ($(assignment.node_type))...")
        
        # Solar data
        if assignment.has_pv
            push!(pv_nodes, i)
            solar_ts = generate_solar_profile(
                i, assignment.pv_capacity, 
                scenario.start_time, scenario.end_time, interval,
                latitude=scenario.latitude
            )
            solar_df = DataFrame(
                timestamp = [s.timestamp for s in solar_ts.data],
                irradiance = [s.irradiance for s in solar_ts.data],
                generation = [s.generation for s in solar_ts.data]
            )
            CSV.write(joinpath(output_dir, "data", "solar_node_$i.csv"), solar_df)
        end
        
        # Battery
        if assignment.has_battery
            push!(battery_nodes, i)
        end
        
        # Cooperative
        if assignment.in_cooperative
            push!(cooperative_nodes, i)
        end
        
        # Load data
        load_ts = generate_load_profile(
            i, assignment.node_type,
            scenario.start_time, scenario.end_time, interval
        )
        load_df = DataFrame(
            timestamp = [l.timestamp for l in load_ts.data],
            consumption = [l.consumption for l in load_ts.data]
        )
        CSV.write(joinpath(output_dir, "data", "load_node_$i.csv"), load_df)
    end
    
    # Generate config.json
    config = Dict(
        "simulation_parameters" => Dict(
            "dt" => scenario.time_step_minutes / 60.0,
            "simulation_hours" => (scenario.end_time - scenario.start_time).value / (1000 * 3600)
        ),
        "grid_parameters" => Dict(
            "num_nodes" => length(node_assignments),  # Use actual number of nodes created
            "pv_nodes" => pv_nodes,
            "battery_nodes" => battery_nodes,
            "market_model" => scenario.market_model,
            "cooperative_nodes" => cooperative_nodes
        )
    )
    
    open(joinpath(output_dir, "config.json"), "w") do f
        JSON.print(f, config, 4)
    end
    
    # Save scenario metadata
    save_scenario(scenario, joinpath(output_dir, "scenario.json"))
    
    println("Scenario generation complete: $output_dir")
    return output_dir
end

struct NodeAssignment
    node_type::String
    has_pv::Bool
    has_battery::Bool
    pv_capacity::Float64
    in_cooperative::Bool
end

function assign_nodes(scenario::Scenario)
    assignments = NodeAssignment[]
    node_id = 1
    
    # Distribute nodes by type
    for (node_type, count) in scenario.node_types
        for _ in 1:count
            # Randomly assign PV and battery based on penetration
            Random.seed!(hash((scenario.name, node_id, "pv")))
            has_pv = rand() < scenario.pv_penetration
            
            Random.seed!(hash((scenario.name, node_id, "battery")))
            has_battery = rand() < scenario.battery_penetration
            
            # PV capacity based on type
            pv_capacity = if has_pv
                if node_type == "residential"
                    5.0 + 3.0 * rand()  # 5-8 kW
                elseif node_type == "commercial"
                    15.0 + 10.0 * rand()  # 15-25 kW
                else  # industrial
                    50.0 + 50.0 * rand()  # 50-100 kW
                end
            else
                0.0
            end
            
            # Cooperative membership
            Random.seed!(hash((scenario.name, node_id, "coop")))
            in_cooperative = rand() < scenario.cooperative_fraction
            
            push!(assignments, NodeAssignment(node_type, has_pv, has_battery, pv_capacity, in_cooperative))
            node_id += 1
        end
    end
    
    return assignments
end

end
