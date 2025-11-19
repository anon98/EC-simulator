# main.jl
# Entry point for running the LEC Simulation

# Ensure the current directory is in the load path
push!(LOAD_PATH, @__DIR__)

using LECSimulator
using JSON

function main()
    println("Starting LEC Simulation...")
    
    # 1. Load Configuration
    config_path = joinpath(@__DIR__, "..", "settings", "config.json")
    if !isfile(config_path)
        println("Error: Config file not found at $config_path")
        return
    end
    
    println("Loading configuration from $config_path")
    params, community = load_config(config_path)
    
    println("Simulation Parameters:")
    println("  DT: $(params.dt) hours")
    println("  Duration: $(params.simulation_hours) hours")
    println("  Nodes: $(length(community.nodes))")
    println("  Cooperative: $(community.is_cooperative)")
    
    # 2. Run Simulation
    println("Running simulation...")
    results = run_simulation(params, community)
    
    # 3. Process Results
    total_profit = sum(results["node_profits"])
    println("Simulation complete.")
    println("Total Community Profit: $(round(total_profit, digits=2))")
    
    # 4. Visualization
    println("Generating plots...")
    cleanup_images()
    plot_results(params, community, results)
    println("Plots saved to outputs/images_EC")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
