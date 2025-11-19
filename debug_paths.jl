# debug_paths.jl
using Dates

# Mock global state
const active_scenarios = Dict{String, Any}()
const PROJECT_ROOT = "c:\\Users\\USER\\Desktop\\PhD\\EC-simulator"

function resolve_path(target)
    println("Target: $target")
    
    if startswith(target, "/scenarios/")
        path_parts = split(target, "/")
        println("Parts: $path_parts")
        
        if length(path_parts) >= 4
            scenario_id = path_parts[3]
            rest_parts = path_parts[4:end]
            println("ID: $scenario_id")
            println("Rest: $rest_parts")
            
            # 1. Try active scenarios
            if haskey(active_scenarios, scenario_id)
                return joinpath(active_scenarios[scenario_id]["output_dir"], rest_parts...)
            # 2. Try replacing underscores with spaces in ID
            elseif isdir(joinpath(PROJECT_ROOT, "scenarios", replace(scenario_id, "_" => " ")))
                return joinpath(PROJECT_ROOT, "scenarios", replace(scenario_id, "_" => " "), rest_parts...)
            # 3. Try exact match
            elseif isdir(joinpath(PROJECT_ROOT, "scenarios", scenario_id))
                return joinpath(PROJECT_ROOT, "scenarios", scenario_id, rest_parts...)
            else
                return "FALLBACK_LOGIC_WOULD_GO_HERE"
            end
        end
    end
    return "NO_MATCH"
end

# Test case
target = "/scenarios/Test/simulation_results.json"
resolved = resolve_path(target)
println("Resolved: $resolved")
println("Exists: $(isfile(resolved))")

# Check directory listing
scenarios_dir = joinpath(PROJECT_ROOT, "scenarios")
println("\nScenarios dir: $scenarios_dir")
if isdir(scenarios_dir)
    println("Contents: ", readdir(scenarios_dir))
else
    println("Scenarios dir does not exist!")
end

test_dir = joinpath(scenarios_dir, "Test")
println("\nTest dir: $test_dir")
if isdir(test_dir)
    println("Contents: ", readdir(test_dir))
else
    println("Test dir does not exist!")
end
