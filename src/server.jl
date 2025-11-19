module Server

using HTTP
using JSON
using Dates

include("scenario_config.jl")
include("data_schema.jl")
include("data_generation.jl")
include("scenario_generator.jl")

# Include main simulator components
include("types.jl")
include("market.jl")
include("utils.jl")
include("simulation.jl")

using .ScenarioConfig
using .DataSchema
using .DataGeneration
using .ScenarioGenerator
using .Types
using .Market
using .Utils
using .Simulation

export start_server, stop_server

# Global state
# Global state
const active_scenarios = Dict{String, Any}()
const server_ref = Ref{Union{HTTP.Server, Nothing}}(nothing)
const PROJECT_ROOT = dirname(@__DIR__)

function start_server(;port::Int=8080, host::String="127.0.0.1")
    println("Starting LEC Scenario Server on http://$host:$port")
    println("Project Root: $PROJECT_ROOT")
    
    router = HTTP.Router()
    
    # API Routes
    HTTP.register!(router, "GET", "/api/templates", handle_get_templates)
    HTTP.register!(router, "POST", "/api/scenarios/generate", handle_generate_scenario)
    HTTP.register!(router, "GET", "/api/scenarios", handle_list_scenarios)
    HTTP.register!(router, "GET", "/api/scenarios/*", handle_get_scenario)
    HTTP.register!(router, "POST", "/api/simulation/run", handle_run_simulation)
    
    # Static files - Handled by middleware manual dispatch
    # HTTP.register!(router, "GET", "/*", handle_static)
    
    # Middleware for logging and manual dispatch
    function logger_middleware(handler)
        return function(req)
            println("RAW REQUEST: $(req.method) $(req.target)")
            
            # Check if it matches an API route first
            # Simple heuristic: if it starts with /api, let the router handle it
            if startswith(req.target, "/api")
                resp = handler(req)
                println("RESPONSE STATUS: $(resp.status)")
                return resp
            end
            
            # Otherwise, treat as static file
            println("Manual dispatch to handle_static")
            resp = handle_static(req)
            println("RESPONSE STATUS: $(resp.status)")
            return resp
        end
    end
    
    server_ref[] = HTTP.serve!(logger_middleware(router), host, port; verbose=false)
    
    println("Server started successfully!")
    println("Open http://$host:$port/scenario_builder.html in your browser")
    
    return server_ref[]
end

function stop_server()
    if server_ref[] !== nothing
        close(server_ref[])
        println("Server stopped")
    end
end

# API Handlers

function handle_get_templates(req::HTTP.Request)
    templates = Dict(
        name => Dict(
            "name" => tmpl.name,
            "num_nodes" => tmpl.num_nodes,
            "node_types" => tmpl.node_types,
            "pv_penetration" => tmpl.pv_penetration,
            "battery_penetration" => tmpl.battery_penetration,
            "duration_days" => Dates.value(tmpl.end_time - tmpl.start_time) / (1000 * 3600 * 24),
            "market_model" => tmpl.market_model
        )
        for (name, tmpl) in ScenarioTemplate
    )
    
    return HTTP.Response(200, JSON.json(templates))
end

function handle_generate_scenario(req::HTTP.Request)
    try
        body = JSON.parse(String(req.body))
        
        # Build scenario from request
        scenario = Scenario(
            get(body, "name", "Custom Scenario"),
            get(body, "num_nodes", 10),
            Dict{String, Int}(body["node_types"]),
            get(body, "pv_penetration", 0.5),
            get(body, "battery_penetration", 0.3),
            DateTime(body["start_time"], "yyyy-mm-dd HH:MM:SS"),
            DateTime(body["end_time"], "yyyy-mm-dd HH:MM:SS"),
            get(body, "time_step_minutes", 60),
            get(body, "latitude", 50.0),
            get(body, "longitude", 10.0),
            get(body, "season", "summer"),
            get(body, "market_model", "P2PNashBargaining"),
            get(body, "cooperative_fraction", 0.8)
        )
        
        # Generate scenario
        # Use absolute path for output
        output_dir = joinpath(PROJECT_ROOT, "scenarios", replace(scenario.name, " " => "_"))
        generate_scenario(scenario, output_dir=output_dir)
        
        # Store in active scenarios
        scenario_id = replace(scenario.name, " " => "_")
        active_scenarios[scenario_id] = Dict(
            "scenario" => scenario,
            "output_dir" => output_dir,
            "generated_at" => now()
        )
        
        response = Dict(
            "status" => "success",
            "scenario_id" => scenario_id,
            "output_dir" => output_dir
        )
        
        return HTTP.Response(200, JSON.json(response))
    catch e
        error_response = Dict(
            "status" => "error",
            "message" => string(e)
        )
        return HTTP.Response(500, JSON.json(error_response))
    end
end

function handle_list_scenarios(req::HTTP.Request)
    scenarios_list = [
        Dict(
            "id" => id,
            "name" => info["scenario"].name,
            "generated_at" => string(info["generated_at"])
        )
        for (id, info) in active_scenarios
    ]
    
    return HTTP.Response(200, JSON.json(scenarios_list))
end

function handle_get_scenario(req::HTTP.Request)
    # Extract scenario ID from path
    path_parts = split(req.target, "/")
    if length(path_parts) >= 4
        scenario_id = path_parts[4]
        
        if haskey(active_scenarios, scenario_id)
            info = active_scenarios[scenario_id]
            response = Dict(
                "scenario" => info["scenario"],
                "output_dir" => info["output_dir"]
            )
            return HTTP.Response(200, JSON.json(response))
        end
    end
    
    return HTTP.Response(404, JSON.json(Dict("error" => "Scenario not found")))
end

function handle_run_simulation(req::HTTP.Request)
    try
        body = JSON.parse(String(req.body))
        scenario_id = body["scenario_id"]
        
        # Find the scenario directory
        scenario_dir = if haskey(active_scenarios, scenario_id)
            active_scenarios[scenario_id]["output_dir"]
        else
            joinpath(PROJECT_ROOT, "scenarios", scenario_id)
        end
        
        if !isdir(scenario_dir)
            # Fallback: try replacing underscores with spaces
            scenario_dir_spaces = joinpath(PROJECT_ROOT, "scenarios", replace(scenario_id, "_" => " "))
            if isdir(scenario_dir_spaces)
                scenario_dir = scenario_dir_spaces
            else
                return HTTP.Response(404, JSON.json(Dict("error" => "Scenario directory not found: $scenario_dir")))
            end
        end
        
        # Load the config
        config_path = joinpath(scenario_dir, "config.json")
        if !isfile(config_path)
            return HTTP.Response(404, JSON.json(Dict("error" => "Config file not found at $config_path")))
        end
        
        # Run simulation using LECSimulator
        params, community = load_config(config_path)
        
        # Override market model if specified in request
        if haskey(body, "market_model")
            market_type_str = body["market_model"]
            println("Running simulation with market model: $market_type_str")
            
            new_market_model = if market_type_str == "CommunitySelfConsumption"
                CommunitySelfConsumption()
            elseif market_type_str == "SDRPricing"
                SDRPricing()
            elseif market_type_str == "PayAsClear"
                PayAsClear()
            else
                P2PNashBargaining()
            end

            community = Community(community.nodes, new_market_model, community.cooperative_nodes)
        end
        
        println("Starting simulation for scenario: $scenario_id")
        results = run_simulation(params, community)
        kpis =calculate_kpis(results, params)
        
        # Export results
        output_file = joinpath(scenario_dir, "simulation_results.json")
        export_to_json(results, kpis, output_file)
        println("Simulation complete. Results saved to: $output_file")
        
        response = Dict(
            "status" => "success",
            "scenario_id" => scenario_id,
            "results_file" => output_file,
            "kpis" => kpis
        )
        
        return HTTP.Response(200, JSON.json(response))
    catch e
        error_response = Dict(
            "status" => "error",
            "message" => string(e)
        )
        return HTTP.Response(500, JSON.json(error_response))
    end
end

function handle_static(req::HTTP.Request)
    # Decode URL to handle spaces and special characters
    target = HTTP.unescapeuri(req.target)
    println("DEBUG: Incoming request for $target")

    # Serve static files from dashboard/ or scenarios/
    filepath = if target == "/"
        joinpath(PROJECT_ROOT, "dashboard", "index.html")
    elseif startswith(target, "/scenarios/")
        # Try to resolve scenario path
        path_parts = split(target, "/")
        println("DEBUG: Path parts: $path_parts")
        
        if length(path_parts) >= 4
            scenario_id = path_parts[3]
            # Use joinpath for the rest of the path to handle separators correctly
            rest_parts = path_parts[4:end]
            println("DEBUG: Scenario ID: $scenario_id, Rest: $rest_parts")
            
            # 1. Try active scenarios
            if haskey(active_scenarios, scenario_id)
                p = joinpath(active_scenarios[scenario_id]["output_dir"], rest_parts...)
                println("DEBUG: Found in active_scenarios: $p")
                p
            # 2. Try replacing underscores with spaces in ID
            elseif isdir(joinpath(PROJECT_ROOT, "scenarios", replace(scenario_id, "_" => " ")))
                p = joinpath(PROJECT_ROOT, "scenarios", replace(scenario_id, "_" => " "), rest_parts...)
                println("DEBUG: Found via underscore replacement: $p")
                p
            # 3. Try exact match
            elseif isdir(joinpath(PROJECT_ROOT, "scenarios", scenario_id))
                p = joinpath(PROJECT_ROOT, "scenarios", scenario_id, rest_parts...)
                println("DEBUG: Found via exact match: $p")
                p
            else
                # Fallback: try to find any directory that matches case-insensitive
                found_dir = ""
                scenarios_root = joinpath(PROJECT_ROOT, "scenarios")
                if isdir(scenarios_root)
                    for d in readdir(scenarios_root)
                        if lowercase(d) == lowercase(replace(scenario_id, "_" => " ")) || lowercase(d) == lowercase(scenario_id)
                            found_dir = d
                            break
                        end
                    end
                end
                
                if !isempty(found_dir)
                    joinpath(scenarios_root, found_dir, rest_parts...)
                else
                    joinpath(PROJECT_ROOT, target[2:end])
                end
            end
        else
            joinpath(PROJECT_ROOT, target[2:end])
        end
    else
        joinpath(PROJECT_ROOT, "dashboard", target[2:end]) # Remove leading /
    end
    
    println("Resolved to: $filepath")
    
    if isfile(filepath)
        content = read(filepath, String)
        content_type = get_content_type(filepath)
        return HTTP.Response(200, [("Content-Type", content_type), ("Cache-Control", "no-store")], content)
    else
        # Debug info for 404
        parent_dir = dirname(filepath)
        dir_contents = isdir(parent_dir) ? readdir(parent_dir) : "Directory not found"
        return HTTP.Response(404, "File not found: $filepath (Exists: $(isfile(filepath)), Parent: $parent_dir, Contents: $dir_contents)")
    end
end

function get_content_type(filepath::String)
    ext = lowercase(splitext(filepath)[2])
    types = Dict(
        ".html" => "text/html",
        ".css" => "text/css",
        ".js" => "application/javascript",
        ".json" => "application/json",
        ".png" => "image/png",
        ".jpg" => "image/jpeg"
    )
    return get(types, ext, "text/plain")
end

end
