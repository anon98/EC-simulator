module Simulation

using Random
using ..Types
using ..Market

export run_simulation

# --- Physics Functions ---

function calculate_solar_generation(t, pv::PVSystem)
    amplitude = 50.0 + 10.0 * pv.amplitude_factor
    if t >= 7 && t <= 19
        return amplitude * max(0, sin(π * (t - 7) / 12))
    else
        return 0.0
    end
end

function calculate_load(t, load::Load)
    # Re-implementing the logic from original load_profile
    # Note: The random variability should ideally be pre-generated or seeded for reproducibility
    # For now, we keep it simple as per original code
    
    variability = load.variability * randn()
    time_dependent_load = 0.0

    if t >= 6 && t < 9
        time_dependent_load = 30.0
    elseif t >= 18 && t <= 22
        time_dependent_load = 40.0
    elseif t >= 0 && t < 5
        time_dependent_load = -20.0
    end

    return load.base_load + variability + time_dependent_load
end

function get_grid_price(t)
    if t >= 7 && t <= 10
        return 0.15
    elseif t >= 18 && t <= 21
        return 0.20
    else
        return 0.10
    end
end

# --- Simulation Loop ---

function run_simulation(params::SimulationParams, community::Community)
    times = collect(0:params.dt:params.simulation_hours)
    num_steps = length(times)
    num_nodes = length(community.nodes)
    
    # Result arrays
    solar_gen_res = zeros(num_steps, num_nodes)
    load_res = zeros(num_steps, num_nodes)
    battery_soc_res = zeros(num_steps, num_nodes)
    grid_interactions_res = zeros(num_steps, num_nodes)
    node_profits = zeros(num_nodes)
    
    # Initialize SOC
    for (i, node) in enumerate(community.nodes)
        if node.battery !== nothing
            battery_soc_res[1, i] = node.battery.soc
        end
    end
    
    for t_idx in 1:num_steps-1
        t = times[t_idx]
        current_grid_price = get_grid_price(t)
        
        # 1. Calculate Generation and Load for all nodes
        for (i, node) in enumerate(community.nodes)
            gen = node.pv !== nothing ? calculate_solar_generation(t, node.pv) : 0.0
            load = calculate_load(t, node.load)
            
            node.current_generation = gen
            node.current_load = load
            node.net_power = gen - load
            
            solar_gen_res[t_idx, i] = gen
            load_res[t_idx, i] = load
        end
        
        # 2. Market / Cooperative Logic
        # Distribute excess power among cooperative nodes
        p2p_transactions, _, _ = solve_market(community, current_grid_price, params.dt)
        
        # 3. Battery and Grid Interaction
        for (i, node) in enumerate(community.nodes)
            # Apply P2P transactions first
            # If p2p_transactions[i] > 0, node BOUGHT power (received)
            # If p2p_transactions[i] < 0, node SOLD power (gave away)
            
            # Adjust net power by P2P transaction
            # If I sold power (negative transaction), I have less power available.
            # If I bought power (positive transaction), I have more power available.
            # Wait, let's check the sign convention in market.jl
            # market.jl: transactions[buyer] += amount. So positive means receiving power.
            
            # Effective net power after P2P
            effective_net_power = node.net_power + p2p_transactions[i]
            
            # Update profits from P2P (simplified, assuming price difference handled in market or here)
            # The market.jl calculated 'total_cooperative_profit'. 
            # Here we just track grid interactions.
            
            if effective_net_power > 0
                # Excess power
                if node.battery !== nothing
                    charge_power = min(effective_net_power, node.battery.max_charge_rate)
                    
                    # Check capacity constraints
                    max_energy_can_add = node.battery.max_soc * node.battery.capacity - node.battery.soc
                    charge_power = min(charge_power, max_energy_can_add / params.dt)
                    
                    node.battery.soc += charge_power * params.dt
                    
                    excess_to_grid = effective_net_power - charge_power
                    grid_interactions_res[t_idx, i] = -excess_to_grid # Negative means export
                    node_profits[i] += excess_to_grid * current_grid_price * params.dt
                else
                    grid_interactions_res[t_idx, i] = -effective_net_power
                    node_profits[i] += effective_net_power * current_grid_price * params.dt
                end
            else
                # Deficit power
                deficit = -effective_net_power
                if node.battery !== nothing
                    discharge_power = min(deficit, node.battery.max_discharge_rate)
                    
                    # Check energy constraints
                    max_energy_can_draw = node.battery.soc - node.battery.min_soc * node.battery.capacity
                    discharge_power = min(discharge_power, max_energy_can_draw / params.dt)
                    
                    node.battery.soc -= discharge_power * params.dt
                    
                    deficit_from_grid = deficit - discharge_power
                    grid_interactions_res[t_idx, i] = deficit_from_grid # Positive means import
                    node_profits[i] -= deficit_from_grid * current_grid_price * params.dt
                else
                    grid_interactions_res[t_idx, i] = deficit
                    node_profits[i] -= deficit * current_grid_price * params.dt
                end
            end
            
            # Record SOC for next step
            battery_soc_res[t_idx+1, i] = node.battery !== nothing ? node.battery.soc : 0.0
        end
    end
    
    results = Dict(
        "times" => times,
        "solar_generation" => solar_gen_res,
        "load_profile" => load_res,
        "battery_soc" => battery_soc_res,
        "grid_interactions" => grid_interactions_res,
        "node_profits" => node_profits
    )
    
    return results
end

end
