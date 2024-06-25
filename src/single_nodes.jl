using Random
using Plots

# Constants
const DT = 1.0  # Time step in hours
const SIMULATION_HOURS = 24  # Total simulation time in hours

# Solar PV generation (in kW)
function solar_generation(t)
    amplitude = 50.0  # kW
    mean_generation = 100.0  # kW (average)
    return mean_generation + amplitude * sin(2π * t / 24)
end

# Battery parameters
const BATTERY_CAPACITY = 200.0  # kWh
const BATTERY_MAX_CHARGE_RATE = 50.0  # kW
const BATTERY_MAX_DISCHARGE_RATE = 50.0  # kW
const BATTERY_INITIAL_SOC = 0.5  # Initial state of charge (percentage)

# Load profile (in kW)
function load_profile(t)
    return 50.0 + 20.0 * randn()  # Average load of 50 kW with some random variation
end

# Simulation loop
function simulate_microgrid()
    times = collect(0:DT:SIMULATION_HOURS)
    num_steps = length(times)
    
    battery_soc = zeros(num_steps)
    battery_soc[1] = BATTERY_INITIAL_SOC * BATTERY_CAPACITY  # Initial SOC in kWh
    
    solar_generation_data = [solar_generation(t) for t in times]
    load_profile_data = [load_profile(t) for t in times]
    
    for i = 1:num_steps-1
        net_power_available = solar_generation_data[i] - load_profile_data[i]
        
        if net_power_available > 0  # Excess power to charge battery
            charge_power = min(net_power_available, BATTERY_MAX_CHARGE_RATE)
            battery_soc[i+1] = battery_soc[i] + charge_power * DT
        else  # Need power, discharge battery
            discharge_power = max(net_power_available, -BATTERY_MAX_DISCHARGE_RATE)
            battery_soc[i+1] = battery_soc[i] + discharge_power * DT
        end
        
        # Ensure SOC stays within bounds
        battery_soc[i+1] = clamp(battery_soc[i+1], 0, BATTERY_CAPACITY)
    end
    
    return times, solar_generation_data, load_profile_data, battery_soc
end

# Main function to run simulation and visualize results
function main()
    times, solar_generation_data, load_profile_data, battery_soc = simulate_microgrid()
    
    # Plotting
    plot(times, [solar_generation_data, load_profile_data, battery_soc ./ BATTERY_CAPACITY * 100],
         label=["Solar PV Generation (kW)" "Load Profile (kW)" "Battery SOC (%)"],
         xlabel="Time (hours)", ylabel="Power (kW) / SOC (%)",
         title="Microgrid Simulation", lw=2)
    
    # Save plot as PNG
    savefig("microgrid_simulation.png")
end

# Run the main function
main()
