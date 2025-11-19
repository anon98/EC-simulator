module DataGeneration

using Dates
using Random
using ..DataSchema

export generate_solar_profile, generate_load_profile, generate_price_profile

"""
Generate realistic solar generation profile using clear-sky model with cloud cover
"""
function generate_solar_profile(
    node_id::Int,
    pv_capacity::Float64,
    start_time::DateTime,
    end_time::DateTime,
    interval::Period;
    latitude::Float64=50.0,  # Default: Central Europe
    season_offset::Int=0  # Days from summer solstice
)
    times = collect(start_time:interval:end_time)
    data = SolarDataPoint[]
    
    for t in times
        hour = Dates.hour(t) + Dates.minute(t) / 60.0
        day_of_year = Dates.dayofyear(t)
        
        # Sun elevation model (simplified)
        solar_noon = 12.0
        max_elevation = 90 - abs(latitude - 23.5 * sin(2π * (day_of_year - 81) / 365))
        
        # Hour angle
        hour_angle = abs(hour - solar_noon)
        
        # Solar elevation
        if hour_angle > 6  # Night time
            elevation = 0.0
        else
            elevation = max_elevation * cos(π * hour_angle / 12)
        end
        
        # Clear sky irradiance
        clear_sky_irradiance = max(0, 1000 * sin(deg2rad(elevation)))
        
        # Cloud cover factor (random daily variation)
        Random.seed!(hash((node_id, day_of_year)))
        cloud_factor = 0.5 + 0.5 * rand()  # 50-100% of clear sky
        
        # Actual irradiance
        irradiance = clear_sky_irradiance * cloud_factor
        
        # PV generation (assume 18% efficiency, temperature derating 10%)
        generation = irradiance * pv_capacity / 1000 * 0.18 * 0.9
        
        push!(data, SolarDataPoint(t, irradiance, generation))
    end
    
    return TimeSeriesData(data, start_time, end_time, interval)
end

"""
Generate realistic load profile based on node type
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
    
    for t in times
        hour = Dates.hour(t) + Dates.minute(t) / 60.0
        day_of_week = Dates.dayofweek(t)
        is_weekend = day_of_week >= 6
        
        # Base load by type
        base_load = if node_type == "residential"
            5.0  # kW average
        elseif node_type == "commercial"
            20.0
        else  # industrial
            50.0
        end
        
        # Time-of-day pattern
        if node_type == "residential"
            # Morning and evening peaks
            if 6 <= hour < 9
                time_factor = 1.5 + 0.3 * sin(π * (hour - 6) / 3)
            elseif 17 <= hour < 23
                time_factor = 1.8 + 0.4 * sin(π * (hour - 17) / 6)
            elseif 0 <= hour < 6
                time_factor = 0.4
            else
                time_factor = 0.8
            end
        elseif node_type == "commercial"
            # Daytime usage
            if 8 <= hour < 18
                time_factor = 1.5
            elseif 18 <= hour < 22
                time_factor = 0.8
            else
                time_factor = 0.3
            end
        else  # industrial
            # Relatively constant with slight off-peak reduction
            if 22 <= hour || hour < 6
                time_factor = 0.7
            else
                time_factor = 1.0
            end
        end
        
        # Weekend reduction for non-residential
        if is_weekend && node_type != "residential"
            time_factor *= 0.5
        end
        
        # Random variability
        Random.seed!(hash((node_id, t)))
        random_factor = 0.9 + 0.2 * rand()
        
        consumption = base_load * time_factor * random_factor
        
        push!(data, LoadDataPoint(t, node_id, consumption))
    end
    
    return TimeSeriesData(data, start_time, end_time, interval)
end

"""
Generate realistic electricity price profile
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
    
    for t in times
        hour = Dates.hour(t)
        day_of_week = Dates.dayofweek(t)
        is_weekend = day_of_week >= 6
        
        # Time-of-use pricing
        if 7 <= hour < 10 || 17 <= hour < 21  # Peak hours
            price_multiplier = is_weekend ? 1.2 : 1.5
        elseif 22 <= hour || hour < 6  # Off-peak
            price_multiplier = 0.7
        else  # Mid-peak
            price_multiplier = 1.0
        end
        
        # Daily price volatility (±10%)
        Random.seed!(hash((Dates.day(t), Dates.month(t))))
        volatility = 0.9 + 0.2 * rand()
        
        grid_price = base_price * price_multiplier * volatility
        
        push!(data, PriceDataPoint(t, grid_price, feed_in_tariff))
    end
    
    return TimeSeriesData(data, start_time, end_time, interval)
end

end
