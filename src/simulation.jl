using Random
using Plots
include("local_market.jl")

# Constants
const DT = 0.2  # Time step in hours
const SIMULATION_HOURS = 24  # Total simulation time in hours
const BATTERY_CAPACITY = 200.0  # kWh
const BATTERY_MAX_CHARGE_RATE = 50.0  # kW
const BATTERY_MAX_DISCHARGE_RATE = 50.0  # kW
const BATTERY_INITIAL_SOC = 0.5  # Initial state of charge (percentage)
const BATTERY_MIN_SOC = 0.2  # Minimum state of charge (percentage)
const BATTERY_MAX_SOC = 0.8  # Maximum state of charge (percentage)

# Functions for solar generation and grid price
function solar_generation(t, node, amplitude_factor)
    amplitude = 50.0 + 10.0 * amplitude_factor  # Adjusted to match the peak generation in watts
    if t >= 7 && t <= 19
        return amplitude * max(0, sin(π * (t - 7) / 12))
    else
        return 0
    end
end

function grid_price(t)
    if t >= 7 && t <= 10  # Morning peak hours
        return 0.15  # Higher price in dollars per kWh
    elseif t >= 18 && t <= 21  # Evening peak hours
        return 0.20  # Highest price in dollars per kWh
    else
        return 0.10  # Off-peak hours cheaper price
    end
end

# Load profile function
function load_profile(t, node)
    base_load = 40.0 + 10.0 * node  # Base load for each node
    variability = 20.0 * randn()  # Random daily variability
    time_dependent_load = 0

    if t >= 6 && t < 9  # Early morning peak
        time_dependent_load = 30.0
    elseif t >= 18 && t <= 22  # Evening peak
        time_dependent_load = 40.0
    elseif t >= 0 && t < 5  # Late night
        time_dependent_load = -20.0  # Reduce load during typical off-peak hours
    end

    return base_load + variability + time_dependent_load
end

# Simulation function for the energy community
function simulate_energy_community(num_nodes, simulation_hours, dt, pv_nodes, battery_nodes, cooperative, cooperative_nodes)
    times = collect(0:dt:simulation_hours)
    num_steps = length(times)
    
    battery_soc = zeros(num_nodes, num_steps)
    grid_interactions = zeros(num_nodes, num_steps)
    net_profit = 0.0
    node_profits = zeros(num_nodes)

    # Initialize battery SOC
    for n in battery_nodes
        battery_soc[n, 1] = BATTERY_CAPACITY * BATTERY_INITIAL_SOC
    end

    solar_generation_data = [if node in pv_nodes solar_generation(t, node, 10.0 * node) else 0 end for t in times, node in 1:num_nodes]
    load_profile_data = [load_profile(t, node) for t in times, node in 1:num_nodes]
    transaction_matrix = zeros(length(cooperative_nodes), length(cooperative_nodes), num_steps)

    for i in 1:num_steps-1
        current_grid_price = grid_price(times[i])

        # Calculate net power available for each node
        net_power_available = [solar_generation_data[i, n] - load_profile_data[i, n] for n in 1:num_nodes]
        
        total_cooperative_profit = 0.0  # Reset total cooperative profit for this time step

        if cooperative
            # Distribute excess power cooperatively among cooperative nodes
            net_power_available, transactions, current_transactions, total_cooperative_profit = local_market(cooperative_nodes, net_power_available, current_grid_price, dt)
            transaction_matrix[:, :, i] = current_transactions

            for (idx, node) in enumerate(cooperative_nodes)
                node_profits[node] += transactions[idx] * current_grid_price * dt
                grid_interactions[node, i] += transactions[idx]
            end
        end
        
        for n in 1:num_nodes
            if net_power_available[n] > 0
                if n in battery_nodes
                    charge_power = min(net_power_available[n], BATTERY_MAX_CHARGE_RATE)
                    excess_power = net_power_available[n] - charge_power
                    if excess_power > 0
                        grid_interactions[n, i] += -excess_power
                        node_profits[n] += excess_power * current_grid_price * dt
                    end
                    battery_soc[n, i+1] = min(battery_soc[n, i] + charge_power * dt, BATTERY_CAPACITY * BATTERY_MAX_SOC)
                else
                    grid_interactions[n, i] += -net_power_available[n]
                    node_profits[n] += net_power_available[n] * current_grid_price * dt
                end
            else
                deficit_power = -net_power_available[n]
                if n in battery_nodes
                    if battery_soc[n, i] > BATTERY_MIN_SOC * BATTERY_CAPACITY
                        discharge_power = min(deficit_power, BATTERY_MAX_DISCHARGE_RATE, (battery_soc[n, i] - BATTERY_MIN_SOC * BATTERY_CAPACITY) / dt)
                        battery_soc[n, i+1] = battery_soc[n, i] - discharge_power * dt
                        deficit_power -= discharge_power
                    end
                    if deficit_power > 0
                        grid_interactions[n, i] += deficit_power
                        node_profits[n] -= deficit_power * current_grid_price * dt
                    end
                else
                    grid_interactions[n, i] += deficit_power
                    node_profits[n] -= deficit_power * current_grid_price * dt
                end
            end
            
            battery_soc[n, i+1] = clamp(battery_soc[n, i+1], BATTERY_MIN_SOC * BATTERY_CAPACITY, BATTERY_CAPACITY * BATTERY_MAX_SOC)
        end
    end

    return times, solar_generation_data, load_profile_data, battery_soc, grid_interactions, node_profits, transaction_matrix
end
