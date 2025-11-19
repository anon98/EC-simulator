# benchmark.jl
push!(LOAD_PATH, @__DIR__)

using LECSimulator
using JSON
using Plots

function run_benchmark()
    println("Starting Market Benchmark...")
    
    # Load base config
    config_path = joinpath(@__DIR__, "..", "settings", "config.json")
    base_config = JSON.parsefile(config_path)
    
    market_models = ["P2PNashBargaining", "CommunitySelfConsumption", "SDRPricing", "PayAsClear"]
    results_summary = Dict()
    
    for model_name in market_models
        println("\nRunning simulation for: $model_name")
        
        # Modify config for this model
        current_config = deepcopy(base_config)
        current_config["grid_parameters"]["market_model"] = model_name
        
        # Write temp config
        temp_config_path = joinpath(@__DIR__, "..", "settings", "temp_config.json")
        open(temp_config_path, "w") do f
            JSON.print(f, current_config)
        end
        
        # Load and Run
        params, community = load_config(temp_config_path)
        results = run_simulation(params, community)
        kpis = calculate_kpis(results, params)
        
        results_summary[model_name] = kpis
        
        println("  SSR: $(round(kpis["SSR"], digits=3))")
        println("  SCR: $(round(kpis["SCR"], digits=3))")
        println("  Profit: $(round(kpis["Total Profit"], digits=2))")
        
        # Export for dashboard (overwriting for now, or could save separate files)
        export_to_json(results, kpis, "dashboard/data_$model_name.json")
    end
    
    # Clean up
    rm(joinpath(@__DIR__, "..", "settings", "temp_config.json"))
    
    # Compare Profits Plot
    model_names = collect(keys(results_summary))
    profits = [results_summary[m]["Total Profit"] for m in model_names]
    
    p = bar(model_names, profits, title="Total Community Profit by Market Model", legend=false, ylabel="Profit (Currency)")
    mkpath("outputs")
    savefig(p, "outputs/benchmark_profits.png")
    
    println("\nBenchmark complete. Comparison plot saved to outputs/benchmark_profits.png")
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_benchmark()
end
