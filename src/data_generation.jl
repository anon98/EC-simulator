module DataGeneration

using Dates
using Dates: dayofyear, hour, minute, dayofweek, Date, DateTime, Minute, Hour, year
using Random
using ..DataSchema

export generate_solar_profile, generate_load_profile, generate_price_profile

# ──────────────────────────────────────────────────────────────────────────────
# Solar generation
# ──────────────────────────────────────────────────────────────────────────────

"""
    generate_solar_profile(node_id, pv_capacity, start_time, end_time, interval;
                           latitude=50.0, season_offset=0)

Generate a simplified but physically motivated PV generation profile.

Assumptions:
  - Clear-sky irradiance is based on a basic solar position model using
    latitude and day-of-year.
  - Daily cloud cover is represented by a *per-day* multiplicative factor
    in [0.5, 1.0], constant within each day; this ensures coherent multi-day
    patterns for a given node.
  - A small intra-day jitter is added to avoid perfectly smooth curves.
  - PV conversion uses:
        generation = irradiance * pv_capacity / 1000 * η,
    with η ≈ 0.18 × 0.9 (efficiency × derating).

Units:
  - pv_capacity in kW.
  - irradiance in W/m² (capped at 0–1000).
  - generation in kW (AC).
"""
function generate_solar_profile(
    node_id::Int,
    pv_capacity::Float64,
    start_time::DateTime,
    end_time::DateTime,
    interval::Period;
    latitude::Float64=50.0,  # Default: Central Europe
    season_offset::Int=0
)
    times = collect(start_time:interval:end_time)
    data = SolarDataPoint[]

    # Node-specific RNG for reproducibility
    rng = MersenneTwister(hash((node_id, "solar")))

    # Precompute daily cloud factors
    daily_cloud = Dict{Date, Float64}()

    lat_rad = deg2rad(latitude)

    for t in times
        # Solar geometry
        day_of_year = dayofyear(t) + season_offset
        hour = Dates.hour(t) + Dates.minute(t) / 60.0

        # Solar declination (degrees) – standard approximation
        dec_deg = 23.45 * sin(2π * (284 + day_of_year) / 365)
        dec_rad = deg2rad(dec_deg)

        # Hour angle (degrees): 0 at solar noon, ±15° per hour
        hour_angle_deg = 15.0 * (hour - 12.0)
        H_rad = deg2rad(hour_angle_deg)

        # Solar elevation (radians), basic formula
        sin_elev = sin(lat_rad) * sin(dec_rad) + cos(lat_rad) * cos(dec_rad) * cos(H_rad)
        sin_elev = max(sin_elev, 0.0)  # below horizon → 0
        elevation_rad = asin(sin_elev)

        if sin_elev <= 0
            # Night time
            irradiance = 0.0
            generation = 0.0
        else
            # Clear-sky global irradiance [W/m²]
            # I0 scales with sin(elevation); simple cap at 1000 W/m²
            clear_sky_irradiance = 1000.0 * sin_elev

            # Daily cloud factor (persistent within the day)
            d = Date(t)
            if !haskey(daily_cloud, d)
                # 50–100% of clear sky; can be refined to weather states
                daily_cloud[d] = 0.5 + 0.5 * rand(rng)
            end

            # Small intra-day jitter around daily cloud factor
            jitter = 1.0 + 0.05 * (2rand(rng) - 1.0)  # ±5%

            cloud_factor = clamp(daily_cloud[d] * jitter, 0.2, 1.0)

            irradiance = max(0.0, clear_sky_irradiance * cloud_factor)
            irradiance = min(irradiance, 1000.0)

            # PV generation (capacity * performance ratio)
            performance_ratio = 0.18 * 0.9
            generation = irradiance * pv_capacity / 1000.0 * performance_ratio
        end

        push!(data, SolarDataPoint(t, irradiance, generation))
    end

    return TimeSeriesData(data, start_time, end_time, interval)
end

# ──────────────────────────────────────────────────────────────────────────────
# Load profiles
# ──────────────────────────────────────────────────────────────────────────────

"""
    generate_load_profile(node_id, node_type, start_time, end_time, interval)

Generate a realistic load profile with:
  - Base level by node_type ("residential", "commercial", "industrial").
  - Time-of-day pattern.
  - Weekend vs. weekday effects.
  - Daily random scaling (per node, per day).
  - Small intra-day variation around the deterministic pattern.
"""
function generate_load_profile(
    node_id::Int,
    node_type::String,
    start_time::DateTime,
    end_time::DateTime,
    interval::Period
)
    times = collect(start_time:interval:end_time)
    data = LoadDataPoint[]

    rng = MersenneTwister(hash((node_id, "load")))
    daily_scale = Dict{Date, Float64}()

    for t in times
        hour = Dates.hour(t) + Dates.minute(t) / 60.0
        d = Date(t)
        day_of_week = dayofweek(d)
        is_weekend = day_of_week >= 6

        # Base load by type [kW]
        base_load = if node_type == "residential"
            5.0
        elseif node_type == "commercial"
            20.0
        else  # industrial / other
            50.0
        end

        # Deterministic time-of-day shape
        time_factor = if node_type == "residential"
            if 6 <= hour < 9
                1.5 + 0.3 * sin(π * (hour - 6) / 3)
            elseif 17 <= hour < 23
                1.8 + 0.4 * sin(π * (hour - 17) / 6)
            elseif 0 <= hour < 6
                0.4
            else
                0.8
            end
        elseif node_type == "commercial"
            if 8 <= hour < 18
                1.5
            elseif 18 <= hour < 22
                0.8
            else
                0.3
            end
        else
            # industrial: relatively flat with small off-peak reduction
            if 22 <= hour || hour < 6
                0.7
            else
                1.0
            end
        end

        # Weekend reduction for non-residential
        if is_weekend && node_type != "residential"
            time_factor *= 0.5
        end

        # Daily scaling by type and weekend
        if !haskey(daily_scale, d)
            if node_type == "residential"
                μ = is_weekend ? 1.10 : 1.00
                σ = 0.15
            elseif node_type == "commercial"
                μ = is_weekend ? 0.60 : 1.00
                σ = 0.10
            else
                μ = is_weekend ? 0.90 : 1.00
                σ = 0.08
            end
            # approximate lognormal-like via multiplicative noise
            ξ = σ * (2rand(rng) - 1.0)
            daily_scale[d] = clamp(μ * exp(ξ), 0.3, 2.0)
        end
        daily_factor = daily_scale[d]

        # Intra-day random variability (zero-mean, small)
        σ_intra = node_type == "residential" ? 0.05 :
                  node_type == "commercial"  ? 0.04 :
                                                0.03
        intra = 1.0 + σ_intra * (2rand(rng) - 1.0)
        intra = clamp(intra, 0.7, 1.3)

        total_factor = time_factor * daily_factor * intra

        consumption = base_load * total_factor
        consumption = max(consumption, 0.0)

        push!(data, LoadDataPoint(t, node_id, consumption))
    end

    return TimeSeriesData(data, start_time, end_time, interval)
end

# ──────────────────────────────────────────────────────────────────────────────
# Price profiles
# ──────────────────────────────────────────────────────────────────────────────

"""
    generate_price_profile(start_time, end_time, interval;
                           base_price=0.10, feed_in_tariff=0.05)

Generate a stylized electricity price profile with:
  - Time-of-use structure (peak, mid-peak, off-peak).
  - Weekend vs. weekday differences.
  - Daily volatility factor (common to all hours of a day).
"""
function generate_price_profile(
    start_time::DateTime,
    end_time::DateTime,
    interval::Period;
    base_price::Float64=0.10,  # €/kWh
    feed_in_tariff::Float64=0.05
)
    times = collect(start_time:interval:end_time)
    data = PriceDataPoint[]

    rng = MersenneTwister(hash(("price", year(start_time))))
    daily_vol = Dict{Date, Float64}()

    for t in times
        hour = Dates.hour(t)
        d = Date(t)
        day_of_week = dayofweek(d)
        is_weekend = day_of_week >= 6

        # Time-of-use pricing multipliers
        price_multiplier = if 7 <= hour < 10 || 17 <= hour < 21
            # Peak hours
            is_weekend ? 1.2 : 1.5
        elseif 22 <= hour || hour < 6
            # Off-peak
            0.7
        else
            # Mid-peak
            1.0
        end

        # Daily volatility factor (same for all hours of the day)
        if !haskey(daily_vol, d)
            daily_vol[d] = 0.9 + 0.2 * rand(rng)  # ±10%
        end
        volatility = daily_vol[d]

        # Slight weekend discount overall
        weekend_factor = is_weekend ? 0.95 : 1.0

        grid_price = base_price * price_multiplier * volatility * weekend_factor

        push!(data, PriceDataPoint(t, grid_price, feed_in_tariff))
    end

    return TimeSeriesData(data, start_time, end_time, interval)
end

end
