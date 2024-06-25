using Random
using Plots

# Constants
const DT = 1.0  # Time step in hours
const SIMULATION_HOURS = 24  # Total simulation time in hours
const NUM_NODES = 3  # Number of nodes in the microgrid network

function solar_generation(t, node, amplitude_factor)
    amplitude = 50.0 + 10.0 * amplitude_factor  # Adjusted by node factor
    if t >= 7 && t <= 19
        return amplitude * max(0, cos(π * (t - 7) / 12))
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

# Battery parameters
const BATTERY_CAPACITY = 200.0  # kWh
const BATTERY_MAX_CHARGE_RATE = 50.0  # kW
const BATTERY_MAX_DISCHARGE_RATE = 50.0  # kW
const BATTERY_INITIAL_SOC = 0.5  # Initial state of charge (percentage)

function load_profile(t, node)
    base_load = 50.0 + 10.0 * node  # Base load for each node
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

function simulate_microgrid(num_nodes, simulation_hours, dt, pv_nodes, battery_nodes)
    times = collect(0:dt:simulation_hours)
    num_steps = length(times)
    
    battery_soc = zeros(num_nodes, num_steps)
    grid_interactions = zeros(num_nodes, num_steps)
    net_profit = 0.0

    solar_generation_data = [if node in pv_nodes solar_generation(t, node, 10.0 * node) else 0 end for t in times, node in 1:num_nodes]
    load_profile_data = [load_profile(t, node) for t in times, node in 1:num_nodes]
    
    for i in 1:num_steps-1
        current_grid_price = grid_price(times[i])

        for n in 1:num_nodes
            net_power_available = solar_generation_data[i, n] - load_profile_data[i, n]
            
            if net_power_available > 0
                if n in battery_nodes
                    charge_power = min(net_power_available, BATTERY_MAX_CHARGE_RATE)
                    excess_power = net_power_available - charge_power
                    if excess_power > 0
                        grid_interactions[n, i] = -excess_power
                        net_profit += excess_power * current_grid_price * dt
                    end
                    battery_soc[n, i+1] = min(battery_soc[n, i] + charge_power * dt, BATTERY_CAPACITY)
                else
                    grid_interactions[n, i] = -net_power_available
                    net_profit += net_power_available * current_grid_price * dt
                end
            else
                deficit_power = -net_power_available
                if n in battery_nodes
                    if battery_soc[n, i] >= deficit_power * dt
                        battery_soc[n, i+1] = battery_soc[n, i] - deficit_power * dt
                    else
                        needed_power = deficit_power - battery_soc[n, i] / dt
                        grid_interactions[n, i] = needed_power
                        net_profit -= needed_power * current_grid_price * dt
                        battery_soc[n, i+1] = 0
                    end
                else
                    grid_interactions[n, i] = deficit_power
                    net_profit -= deficit_power * current_grid_price * dt
                end
            end
            
            battery_soc[n, i+1] = clamp(battery_soc[n, i+1], 0, BATTERY_CAPACITY)
        end
    end
    
    return times, solar_generation_data, load_profile_data, battery_soc, grid_interactions, net_profit
end

function main(num_nodes, pv_nodes, battery_nodes)
    dt = 1.0
    simulation_hours = 24

    times, solar_generation_data, load_profile_data, battery_soc, grid_interactions, net_profit = simulate_microgrid(num_nodes, simulation_hours, dt, pv_nodes, battery_nodes)
    
    println("Total Net Profit for $num_nodes nodes: $net_profit dollars")

    for n in 1:num_nodes
        p = plot()
        if n in pv_nodes
            plot!(p, times, solar_generation_data[:, n], label="Solar PV Generation (kW)", linewidth=2, color="blue")
        end
        plot!(p, times, load_profile_data[:, n], label="Load Profile (kW)", linewidth=2, color="red")
        if n in battery_nodes
            plot!(p, times, battery_soc[n, :] ./ BATTERY_CAPACITY * 100, label="Battery SOC (%)", linewidth=2, color="green")
        end
        plot!(p, times, grid_interactions[n, :], label="Grid Interactions (kW)", linewidth=2, color="black")

        xlabel!(p, "Time (hours)")
        ylabel!(p, "Power (kW) / SOC (%) / Grid (kW)")
        title!(p, "Microgrid Simulation - Node $n")
        savefig(p, "microgrid_simulation_node_$n.png")
    end
end




num_nodes = 5
pv_nodes = [1, 3, 4]  # Nodes with PV systems
battery_nodes = [2, 3, 5]  # Nodes with batteries

main(num_nodes, pv_nodes, battery_nodes)