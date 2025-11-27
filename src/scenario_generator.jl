module ScenarioGenerator

using Dates
using Dates: Date, DateTime, Minute, Hour, dayofweek, hour, minute
using Random
using CSV
using DataFrames
using JSON
using Logging

# Note: Assumes ScenarioConfig, DataSchema, DataGeneration are already loaded
using ..ScenarioConfig
using ..DataSchema
using ..DataGeneration
using ..Utils
using ..Simulation

export generate_scenario, export_scenario

# ──────────────────────────────────────────────────────────────────────────────
# Internal helper types
# ──────────────────────────────────────────────────────────────────────────────

struct NodeAssignment
    node_type::String
    has_pv::Bool
    has_battery::Bool
    pv_capacity::Float64
    in_cooperative::Bool
end

const PV_CAPACITY_BANDS = Dict(
    "residential" => (3.0, 10.0),     # kW_peak
    "commercial"  => (30.0, 120.0),
    "industrial"  => (150.0, 600.0)
)

function sample_pv_capacity(node_type::String)
    band = get(PV_CAPACITY_BANDS, node_type, (20.0, 80.0))
    low, high = band
    return low + (high - low) * rand()
end

# ──────────────────────────────────────────────────────────────────────────────
# Weather / PV realism helpers
# ──────────────────────────────────────────────────────────────────────────────

"""
    generate_weather_scaling(start_time, end_time, interval; scenario_name)

Generate a time series of multiplicative weather scaling factors ∈ [0.1, 1.1]
for the solar generation:

  - Each *day* is assigned a weather type:
      :clear          → high irradiance (≈1.0)
      :partly_cloudy  → medium irradiance (≈0.6–0.8)
      :overcast       → low irradiance (≈0.3–0.5)
  - Within each day, we apply a low-frequency AR(1) noise process so that
    intra-day cloudiness is temporally correlated.
  - Night hours are unaffected; clear-sky profiles should already go to zero.

The returned vector is aligned with the grid `start_time:interval:end_time`
and is intended to be applied multiplicatively to the *baseline* PV generation
from `generate_solar_profile`.
"""
function generate_weather_scaling(start_time::DateTime,
                                  end_time::DateTime,
                                  interval::Period;
                                  scenario_name::String)

    timestamps = collect(start_time:interval:end_time)
    n = length(timestamps)
    scaling = Vector{Float64}(undef, n)

    rng = MersenneTwister(hash((scenario_name, "weather")))

    # Probabilities for daily weather states
    weather_states = (:clear, :partly_cloudy, :overcast)
    probs          = (0.5, 0.3, 0.2)  # can be scenario-dependent if desired

    daily_base = Dict{Date, Float64}()

    # Small AR(1) noise for intra-day fluctuations
    ρ   = 0.7      # persistence
    σn  = 0.10     # noise std
    ηᵗ₋₁ = 0.0

    for (k, t) in enumerate(timestamps)
        d = Date(t)
        if !haskey(daily_base, d)
            # Draw daily weather state using cumulative probabilities
            r = rand(rng)
            state = if r < probs[1]
                weather_states[1]  # :clear
            elseif r < probs[1] + probs[2]
                weather_states[2]  # :partly_cloudy
            else
                weather_states[3]  # :overcast
            end

            base = if state === :clear
                rand(rng, 0.95:0.005:1.05)  # mostly around 1.0
            elseif state === :partly_cloudy
                rand(rng, 0.6:0.01:0.8)
            else # :overcast
                rand(rng, 0.3:0.01:0.5)
            end

            daily_base[d] = base
            ηᵗ₋₁ = 0.0  # reset intra-day noise at day boundary
        end

        # AR(1) noise (low-frequency cloud variations)
        η = ρ * ηᵗ₋₁ + (1 - ρ) * σn * randn(rng)
        ηᵗ₋₁ = η

        val = daily_base[d] * (1.0 + η)
        scaling[k] = clamp(val, 0.1, 1.1)
    end

    return scaling
end

# ──────────────────────────────────────────────────────────────────────────────
# Load variability helpers
# ──────────────────────────────────────────────────────────────────────────────

"""
    draw_daily_load_scale(node_type, is_weekend, rng)

Draw a multiplicative daily scaling factor for the base load profile.

The distribution parameters are chosen heuristically by customer type:

  - Residential: higher weekend use, moderate variability.
  - Commercial: strong weekday loads, low weekend activity.
  - Industrial: relatively flat with low variability, mild weekend reduction.
"""
function draw_daily_load_scale(node_type::String,
                               is_weekend::Bool,
                               rng::AbstractRNG)::Float64
    if node_type == "residential"
        μ = is_weekend ? 1.10 : 1.00
        σ = 0.12
    elseif node_type == "commercial"
        μ = is_weekend ? 0.60 : 1.00
        σ = 0.10
    else
        # industrial and others
        μ = is_weekend ? 0.90 : 1.00
        σ = 0.06
    end
    # Log-normal like behavior via exp of normal:
    ξ = σ * randn(rng)
    return max(0.2, μ * exp(ξ))
end

"""
    draw_intraday_noise(node_type, rng)

Small zero-mean multiplicative noise term (ε) per time step, so that the
effective scaling is ≈ (1 + ε). This introduces high-frequency stochastic
variability around the base diurnal shape.
"""
function draw_intraday_noise(node_type::String,
                             rng::AbstractRNG)::Float64
    σ = node_type == "residential" ? 0.04 :
        node_type == "commercial"  ? 0.03 :
                                     0.02
    return σ * randn(rng)
end

"""
    apply_load_variability!(load_df, node_type, scenario_name, node_id)

Apply realistic, type-dependent variability to an already generated load
time series:

  - Daily level effect: draw one multiplicative factor per day per node.
  - Intra-day effect: small, zero-mean noise per time step.
  - Weekday/weekend patterns are encoded in the daily factor.

Consumption is kept non-negative by clamping the scaling factor to ≥ 0.1.
"""
function apply_load_variability!(load_df::DataFrame,
                                 node_type::String,
                                 scenario_name::String,
                                 node_id::Int)

    timestamps = load_df.timestamp
    n          = length(timestamps)
    rng        = MersenneTwister(hash((scenario_name, node_id, "load_var")))

    daily_scale = Dict{Date, Float64}()
    factors     = Vector{Float64}(undef, n)

    for (k, t) in enumerate(timestamps)
        d = Date(t)
        if !haskey(daily_scale, d)
            is_weekend = dayofweek(d) in (6, 7) # 6=Sat, 7=Sun
            daily_scale[d] = draw_daily_load_scale(node_type, is_weekend, rng)
        end

        ε = draw_intraday_noise(node_type, rng)
        factor = daily_scale[d] * (1.0 + ε)
        factors[k] = max(0.1, factor)
    end

    load_df.consumption .= load_df.consumption .* factors
    return load_df
end

# ──────────────────────────────────────────────────────────────────────────────
# Node assignment
# ──────────────────────────────────────────────────────────────────────────────

function assign_nodes(scenario::Scenario)
    assignments = NodeAssignment[]
    node_id = 1

    # Distribute nodes by type
    for (node_type, count) in scenario.node_types
        for _ in 1:count
            # Randomly assign PV and battery based on penetration
            Random.seed!(hash((scenario.name, node_id, "pv")))
            has_pv = rand() < scenario.pv_penetration

            Random.seed!(hash((scenario.name, node_id, "battery")))
            has_battery = rand() < scenario.battery_penetration

            pv_capacity = has_pv ? sample_pv_capacity(node_type) : 0.0

            # Cooperative membership
            Random.seed!(hash((scenario.name, node_id, "coop")))
            in_cooperative = rand() < scenario.cooperative_fraction

            push!(assignments, NodeAssignment(node_type, has_pv,
                                              has_battery, pv_capacity,
                                              in_cooperative))
            node_id += 1
        end
    end

    return assignments
end

# ──────────────────────────────────────────────────────────────────────────────
# Main scenario generation
# ──────────────────────────────────────────────────────────────────────────────

function generate_scenario(scenario::Scenario; output_dir::String="scenarios/$(scenario.name)",
                           run_simulation_after::Bool=true)
    println("Generating scenario: $(scenario.name)")
    mkpath(output_dir)
    mkpath(joinpath(output_dir, "data"))

    # Time grid
    interval = Minute(scenario.time_step_minutes)
    timestamps = collect(scenario.start_time:interval:scenario.end_time)

    # Node distribution
    node_assignments = assign_nodes(scenario)

    # Global weather process for all PV nodes (correlated across nodes)
    println("  Generating weather / PV scaling...")
    weather_scaling = generate_weather_scaling(
        scenario.start_time, scenario.end_time, interval;
        scenario_name = scenario.name
    )

    # Price data (common for all)
    println("  Generating price data...")
    price_ts = generate_price_profile(scenario.start_time,
                                      scenario.end_time,
                                      interval)
    price_df = DataFrame(
        timestamp      = [p.timestamp for p in price_ts.data],
        grid_price     = [p.grid_price for p in price_ts.data],
        feed_in_tariff = [p.feed_in_tariff for p in price_ts.data]
    )
    CSV.write(joinpath(output_dir, "data", "prices.csv"), price_df)

    # Per-node data
    pv_nodes         = Int[]
    battery_nodes    = Int[]
    cooperative_nodes = Int[]

    for (i, assignment) in enumerate(node_assignments)
        println("  Generating data for node $i ($(assignment.node_type))...")

        # PV / solar data
        if assignment.has_pv
            push!(pv_nodes, i)
            solar_ts = generate_solar_profile(
                i, assignment.pv_capacity,
                scenario.start_time, scenario.end_time, interval;
                latitude = scenario.latitude
            )

            solar_df = DataFrame(
                timestamp  = [s.timestamp for s in solar_ts.data],
                irradiance = [s.irradiance for s in solar_ts.data],
                generation = [s.generation for s in solar_ts.data]
            )

            # Apply correlated weather scaling across all PV nodes
            # Assumes identical time grid as `timestamps`
            @assert length(solar_df.timestamp) == length(weather_scaling)
            solar_df.generation .= solar_df.generation .* weather_scaling

            CSV.write(joinpath(output_dir, "data", "solar_node_$i.csv"), solar_df)
        end

        # Battery presence
        if assignment.has_battery
            push!(battery_nodes, i)
        end

        # Cooperative membership
        if assignment.in_cooperative
            push!(cooperative_nodes, i)
        end

        # Load data (base shape from DataGeneration)
        load_ts = generate_load_profile(
            i, assignment.node_type,
            scenario.start_time, scenario.end_time, interval
        )
        load_df = DataFrame(
            timestamp   = [l.timestamp for l in load_ts.data],
            consumption = [l.consumption for l in load_ts.data]
        )

        # Apply type-dependent variability
        apply_load_variability!(load_df, assignment.node_type,
                                scenario.name, i)

        CSV.write(joinpath(output_dir, "data", "load_node_$i.csv"), load_df)
    end

    # Config
    sim_hours = (scenario.end_time - scenario.start_time) / Hour(1)

    config = Dict(
        "simulation_parameters" => Dict(
            "dt"               => scenario.time_step_minutes / 60.0,
            "simulation_hours" => sim_hours
        ),
        "grid_parameters" => Dict(
            "num_nodes"        => length(node_assignments),
            "pv_nodes"         => pv_nodes,
            "battery_nodes"    => battery_nodes,
            "market_model"     => scenario.market_model,
            "cooperative_nodes"=> cooperative_nodes
        )
    )

    open(joinpath(output_dir, "config.json"), "w") do f
        JSON.print(f, config, 4)
    end

    # Scenario metadata
    save_scenario(scenario, joinpath(output_dir, "scenario.json"))

    println("Scenario generation complete: $output_dir")
    
    if run_simulation_after
        config_path = joinpath(output_dir, "config.json")
        results_path = joinpath(output_dir, "simulation_results.json")
        try
            params, community = load_config(config_path)
            sim_results = run_simulation(params, community)
            kpis = calculate_kpis(sim_results, params)
            export_to_json(sim_results, kpis, results_path)
            println("  Simulation results saved to: $results_path")
        catch e
            @warn "Failed to run simulation for generated scenario" exception=(e, catch_backtrace())
        end
    end
    
    return output_dir
end

end
