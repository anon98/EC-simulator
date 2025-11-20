module Utils

using JSON
using Plots
using Statistics
using ..Types

export load_config, cleanup_images, plot_results, calculate_kpis, export_to_json

function load_config(file_path::String)
    config = JSON.parsefile(file_path)
    
    sim_params = config["simulation_parameters"]
    grid_params = config["grid_parameters"]
    
    dt = Float64(sim_params["dt"])
    simulation_hours = Int(sim_params["simulation_hours"])
    
    params = SimulationParams(dt, simulation_hours)
    
    num_nodes = grid_params["num_nodes"]
    pv_nodes = Set(grid_params["pv_nodes"])
    battery_nodes = Set(grid_params["battery_nodes"])
    cooperative_nodes = grid_params["cooperative_nodes"]
    
    # Determine market model
    market_type_str = get(grid_params, "market_model", "P2PNashBargaining")
    market_model = if market_type_str == "CommunitySelfConsumption"
        CommunitySelfConsumption()
    elseif market_type_str == "SDRPricing"
        SDRPricing()
    elseif market_type_str == "PayAsClear"
        PayAsClear()
    else
        P2PNashBargaining()
    end
    
    nodes = Vector{Node}()
    for i in 1:num_nodes
        pv = i in pv_nodes ? PVSystem(10.0 * i) : nothing
        battery = i in battery_nodes ? Battery() : nothing
        load = Load(40.0 + 10.0 * i, 20.0)
        
        push!(nodes, Node(i, pv, battery, load, 0.0, 0.0, 0.0))
    end
    
    community = Community(nodes, market_model, cooperative_nodes)
    
    return params, community
end

function cleanup_images(output_dir::String="outputs/images_EC")
    if isdir(output_dir)
        rm(output_dir; recursive=true)
    end
    mkpath(output_dir)
end

function calculate_kpis(results::Dict, params::SimulationParams)
    # SSR: Self-Sufficiency Ratio = (Load - Grid Import) / Load
    # SCR: Self-Consumption Ratio = (Generation - Grid Export) / Generation
    
    total_load = sum(results["load_profile"]) * params.dt
    total_gen = sum(results["solar_generation"]) * params.dt
    
    grid_interactions = results["grid_interactions"]
    total_import = sum(grid_interactions[grid_interactions .> 0]) * params.dt
    total_export = sum(abs.(grid_interactions[grid_interactions .< 0])) * params.dt
    
    ssr = total_load > 0 ? (total_load - total_import) / total_load : 0.0
    scr = total_gen > 0 ? (total_gen - total_export) / total_gen : 0.0
    
    return Dict(
        "SSR" => ssr,
        "SCR" => scr,
        "cooperative_profit" => sum(results["node_profits"]),
        "total_energy_traded" => sum(results["grid_interactions"] .!= 0) * params.dt, # Approximation or placeholder?
        # Better approximation for traded energy if we had it, but for now let's stick to what we have or 0
        # Actually, let's use the passed in results if available, or calculate from grid interactions
        "average_price" => 0.0, # Placeholder
        "total_generation" => total_gen,
        "total_load" => total_load,
        "total_export" => total_export,
        "total_import" => total_import
    )
end

function export_to_json(results::Dict, kpis::Dict, filename::String)
    # Combine results and kpis into the expected format
    output_data = Dict(
        "results" => results,
        "kpis" => kpis
    )
    
    open(filename, "w") do f
        JSON.print(f, output_data, 4)  # Pretty print with 4-space indent
    end
end

function plot_results(params::SimulationParams, community::Community, results::Dict, output_dir::String="outputs/images_EC")
    times = results["times"]
    num_nodes = length(community.nodes)
    
    for n in 1:num_nodes
        p = plot()
        node = community.nodes[n]
        
        if node.pv !== nothing
            plot!(p, times, results["solar_generation"][:, n], label="Solar PV (kW)", linewidth=2, color="blue")
        end
        
        plot!(p, times, results["load_profile"][:, n], label="Load (kW)", linewidth=2, color="red")
        
        if node.battery !== nothing
            plot!(p, times, results["battery_soc"][:, n] ./ node.battery.capacity * 100, label="SOC (%)", linewidth=2, color="green")
        end
        
        plot!(p, times, results["grid_interactions"][:, n], label="Grid (kW)", linewidth=2, color="black")

        xlabel!(p, "Time (hours)")
        ylabel!(p, "Power (kW) / SOC (%)")
        title!(p, "Node $n Simulation")
        savefig(p, joinpath(output_dir, "node_$(n).png"))
    end
    
    net_transactions = sum(results["grid_interactions"], dims=2)
    p_net = plot(times, net_transactions, label="Net Transactions (kW)", linewidth=2, color="purple")
    xlabel!(p_net, "Time (hours)")
    ylabel!(p_net, "Power (kW)")
    title!(p_net, "Community Net Transactions")
    savefig(p_net, joinpath(output_dir, "community_net_transactions.png"))
end

end
