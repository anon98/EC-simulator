module Utils

using JSON
using Plots
using Statistics
using Dates
using CSV
using ..Types

export load_config, cleanup_images, plot_results, calculate_kpis, export_to_json

const TS_FORMAT = DateFormat("yyyy-mm-dd HH:MM:SS")

function load_config(file_path::String)
    config = JSON.parsefile(file_path)
    
    sim_params = config["simulation_parameters"]
    grid_params = config["grid_parameters"]
    
    dt = Float64(sim_params["dt"])
    simulation_hours = Float64(sim_params["simulation_hours"])
    
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

    data_dir = get(grid_params, "data_dir", nothing)
    scenario_dir = dirname(file_path)
    if data_dir === nothing
        default_dir = joinpath(scenario_dir, "data")
        if isdir(default_dir)
            data_dir = default_dir
        end
    elseif !isabspath(data_dir)
        data_dir = joinpath(scenario_dir, data_dir)
    end

    profile_data = nothing
    if data_dir !== nothing && isdir(data_dir)
        raw_profiles = load_scenario_profiles(data_dir, num_nodes)
        if raw_profiles.steps > 0
            if raw_profiles.dt !== nothing
                dt = raw_profiles.dt
            end
            simulation_hours = raw_profiles.steps * dt
            loads = raw_profiles.loads
            solars = raw_profiles.solars
            profile_data = (loads=loads, solars=solars, steps=raw_profiles.steps)
        end
    end
    
    params = SimulationParams(dt, simulation_hours)
    
    nodes = Vector{Node}()
    for i in 1:num_nodes
        pv = i in pv_nodes ? PVSystem(10.0 * i) : nothing
        battery = i in battery_nodes ? Battery() : nothing
        load = Load(40.0 + 10.0 * i, 20.0)
        
        push!(nodes, Node(i, pv, battery, load, 0.0, 0.0, 0.0, nothing, nothing))
    end

    if profile_data !== nothing
        for node in nodes
            if haskey(profile_data.loads, node.id)
                node.load_profile = profile_data.loads[node.id]
            end
            if haskey(profile_data.solars, node.id)
                node.solar_profile = profile_data.solars[node.id]
            end
        end
    end
    
    community = Community(nodes, market_model, cooperative_nodes)
    
    return params, community
end

function pad_or_truncate(series::Vector{Float64}, target_len::Int)
    if length(series) >= target_len
        return series[1:target_len]
    else
        return vcat(series, zeros(target_len - length(series)))
    end
end

function parse_timestamp(value)
    if value isa DateTime
        return value
    elseif value isa AbstractString
        return DateTime(value, TS_FORMAT)
    else
        return DateTime(string(value), TS_FORMAT)
    end
end

function read_profile_series(filepath::String, column::Symbol)
    timestamps = DateTime[]
    values = Float64[]
    for row in CSV.File(filepath)
        ts_raw = row[:timestamp]
        push!(timestamps, parse_timestamp(ts_raw))
        push!(values, Float64(row[column]))
    end
    
    if isempty(timestamps)
        return Float64[], nothing
    end
    
    order = sortperm(timestamps)
    timestamps = timestamps[order]
    values = values[order]
    
    dt_hours = length(timestamps) >= 2 ? Dates.value(timestamps[2] - timestamps[1]) / 3_600_000.0 : nothing
    return values, dt_hours
end

function load_scenario_profiles(data_dir::String, num_nodes::Int)
    load_profiles = Dict{Int, Vector{Float64}}()
    solar_profiles = Dict{Int, Vector{Float64}}()
    dt_hours = nothing
    load_lengths = Int[]
    
    for i in 1:num_nodes
        load_file = joinpath(data_dir, "load_node_$i.csv")
        if isfile(load_file)
            series, dt_candidate = read_profile_series(load_file, :consumption)
            if !isempty(series)
                load_profiles[i] = series
                push!(load_lengths, length(series))
                if dt_hours === nothing && dt_candidate !== nothing
                    dt_hours = dt_candidate
                end
            end
        end
        
        solar_file = joinpath(data_dir, "solar_node_$i.csv")
        if isfile(solar_file)
            series, _ = read_profile_series(solar_file, :generation)
            if !isempty(series)
                solar_profiles[i] = series
            end
        end
    end
    
    steps = isempty(load_lengths) ? 0 : minimum(load_lengths)
    if steps > 0
        for (node_id, series) in solar_profiles
            if length(series) < steps
                solar_profiles[node_id] = pad_or_truncate(series, steps)
            end
        end
    end
    
    return (loads=load_profiles, solars=solar_profiles, steps=steps, dt=dt_hours)
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
    dt = params.dt
    
    total_load = sum(results["load_profile"]) * dt
    total_gen = sum(results["solar_generation"]) * dt
    
    grid_interactions = results["grid_interactions"]
    total_import = sum(grid_interactions[grid_interactions .> 0]) * dt
    total_export = sum(abs.(grid_interactions[grid_interactions .< 0])) * dt
    
    ssr = total_load > 0 ? (total_load - total_import) / total_load : 0.0
    scr = total_gen > 0 ? (total_gen - total_export) / total_gen : 0.0
    
    grid_prices = get(results, "grid_prices", Float64[])
    avg_price = !isempty(grid_prices) ? mean(grid_prices) : 0.0
    
    node_profits = get(results, "node_profits", Float64[])
    cooperative_profit = !isempty(node_profits) ? sum(node_profits) : 0.0
    internal_trade_series = get(results, "internal_trade", Float64[])
    total_internal_trade = !isempty(internal_trade_series) ? sum(internal_trade_series) * dt : 0.0
    load_matrix = results["load_profile"]
    total_load_step = vec(dropdims(sum(load_matrix, dims=2), dims=2))
    import_step = vec(dropdims(sum(max.(grid_interactions, 0.0), dims=2), dims=2))
    if isempty(grid_prices)
        grid_prices = fill(avg_price, length(total_load_step))
    end
    load_energy_step = total_load_step .* dt
    import_energy_step = import_step .* dt
    baseline_cost = sum(load_energy_step .* grid_prices)
    actual_grid_cost = sum(import_energy_step .* grid_prices)
    community_savings = max(baseline_cost - actual_grid_cost, 0.0)
    
    return Dict(
        "ssr" => ssr,
        "scr" => scr,
        "community_savings_eur" => community_savings,
        "cooperative_profit" => cooperative_profit,
        "total_generation_kwh" => total_gen,
        "total_load_kwh" => total_load,
        "grid_import_kwh" => total_import,
        "grid_export_kwh" => total_export,
        "internal_trade_kwh" => total_internal_trade,
        "net_energy_balance_kwh" => total_gen - total_load,
        "average_grid_price_eur_per_kwh" => avg_price
    )
end

function summarize_results(results::Dict)
    times = results["times"]
    solar = results["solar_generation"]
    load = results["load_profile"]
    grid = results["grid_interactions"]
    net_grid_flow = vec(dropdims(sum(grid, dims=2), dims=2))
    total_generation = vec(dropdims(sum(solar, dims=2), dims=2))
    total_load = vec(dropdims(sum(load, dims=2), dims=2))
    grid_import = vec(dropdims(sum(max.(grid, 0.0), dims=2), dims=2))
    grid_export = vec(dropdims(sum(max.(-grid, 0.0), dims=2), dims=2))
    internal_trade = vec(get(results, "internal_trade", zeros(length(times))))
    
    battery_soc_pct = get(results, "battery_soc_pct", zeros(length(times), size(grid, 2)))
    battery_mask = get(results, "battery_mask", falses(size(grid, 2)))
    if any(battery_mask)
        indices = findall(battery_mask)
        avg_battery_soc = vec(dropdims(sum(battery_soc_pct[:, indices], dims=2), dims=2)) ./ length(indices)
    else
        avg_battery_soc = zeros(length(times))
    end
    
    grid_prices = get(results, "grid_prices", zeros(length(times)))
    
    return Dict(
        "time" => times,
        "total_generation" => total_generation,
        "total_load" => total_load,
        "net_grid_flow" => net_grid_flow,
        "grid_import_series" => grid_import,
        "grid_export_series" => grid_export,
        "internal_trade" => internal_trade,
        "battery_soc_avg" => avg_battery_soc,
        "grid_price" => grid_prices
    )
end

function export_to_json(results::Dict, kpis::Dict, filename::String)
    summary = summarize_results(results)
    per_node = Dict(
        "solar_generation" => results["solar_generation"],
        "load_profile" => results["load_profile"],
        "battery_soc" => results["battery_soc"],
        "grid_interactions" => results["grid_interactions"],
        "battery_soc_pct" => get(results, "battery_soc_pct", results["battery_soc"]),
        "p2p_flows" => get(results, "p2p_flows", zeros(size(results["solar_generation"]))),
        "has_battery" => results["battery_mask"]
    )
    
    output_data = Dict(
        "kpis" => kpis,
        "results" => summary,
        "per_node" => per_node
    )
    
    open(filename, "w") do f
        JSON.print(f, output_data, 4)
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
