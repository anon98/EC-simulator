module ScenarioConfig

using Dates
using JSON

export Scenario, ScenarioTemplate
export get_template, save_scenario, load_scenario

struct Scenario
    name::String
    num_nodes::Int
    node_types::Dict{String, Int}  # "residential" => 5, "commercial" => 2, etc.
    pv_penetration::Float64  # 0.0 to 1.0
    battery_penetration::Float64  # 0.0 to 1.0
    start_time::DateTime
    end_time::DateTime
    time_step_minutes::Int
    latitude::Float64
    longitude::Float64
    season::String  # "winter", "spring", "summer", "fall"
    market_model::String
    cooperative_fraction::Float64  # Fraction of nodes in coop
end

# Predefined templates
const ScenarioTemplate = Dict{String, Scenario}(
    "small_residential" => Scenario(
        "Small Residential Community",
        8,
        Dict("residential" => 8),
        0.75,  # 75% have PV
        0.50,  # 50% have batteries
        DateTime(2024, 6, 1, 0, 0, 0),
        DateTime(2024, 6, 7, 23, 0, 0),
        60,  # 1 hour
        50.0,  # Central Europe
        10.0,
        "summer",
        "P2PNashBargaining",
        1.0
    ),
    
    "medium_mixed" => Scenario(
        "Medium Mixed Community",
        25,
        Dict("residential" => 18, "commercial" => 5, "industrial" => 2),
        0.60,
        0.40,
        DateTime(2024, 3, 1, 0, 0, 0),
        DateTime(2024, 3, 14, 23, 0, 0),  # 2 weeks
        60,
        48.0,
        11.0,
        "spring",
        "CommunitySelfConsumption",
        0.8
    ),
    
    "large_urban" => Scenario(
        "Large Urban Community",
        80,
        Dict("residential" => 50, "commercial" => 20, "industrial" => 10),
        0.50,
        0.30,
        DateTime(2024, 1, 1, 0, 0, 0),
        DateTime(2024, 1, 31, 23, 0, 0),  # 1 month
        60,
        52.5,  # Northern Europe
        13.4,
        "winter",
        "SDRPricing",
        0.6
    )
)

function get_template(name::String)
    if haskey(ScenarioTemplate, name)
        return ScenarioTemplate[name]
    else
        error("Template '$name' not found. Available: $(keys(ScenarioTemplate))")
    end
end

function save_scenario(scenario::Scenario, filepath::String)
    data = Dict(
        "name" => scenario.name,
        "num_nodes" => scenario.num_nodes,
        "node_types" => scenario.node_types,
        "pv_penetration" => scenario.pv_penetration,
        "battery_penetration" => scenario.battery_penetration,
        "start_time" => string(scenario.start_time),
        "end_time" => string(scenario.end_time),
        "time_step_minutes" => scenario.time_step_minutes,
        "latitude" => scenario.latitude,
        "longitude" => scenario.longitude,
        "season" => scenario.season,
        "market_model" => scenario.market_model,
        "cooperative_fraction" => scenario.cooperative_fraction
    )
    
    open(filepath, "w") do f
        JSON.print(f, data, 4)
    end
end

function load_scenario(filepath::String)
    data = JSON.parsefile(filepath)
    
    return Scenario(
        data["name"],
        data["num_nodes"],
        Dict{String, Int}(data["node_types"]),
        data["pv_penetration"],
        data["battery_penetration"],
        DateTime(data["start_time"], "yyyy-mm-dd HH:MM:SS"),
        DateTime(data["end_time"], "yyyy-mm-dd HH:MM:SS"),
        data["time_step_minutes"],
        data["latitude"],
        data["longitude"],
        data["season"],
        data["market_model"],
        data["cooperative_fraction"]
    )
end

end
