module DataSchema

export SolarDataPoint, LoadDataPoint, PriceDataPoint, NodeMetadata
export TimeSeriesData

using Dates

# Data point structures
struct SolarDataPoint
    timestamp::DateTime
    irradiance::Float64  # W/m²
    generation::Float64  # kW
end

struct LoadDataPoint
    timestamp::DateTime
    node_id::Int
    consumption::Float64  # kW
end

struct PriceDataPoint
    timestamp::DateTime
    grid_price::Float64  # €/kWh
    feed_in_tariff::Float64  # €/kWh
end

struct NodeMetadata
    node_id::Int
    node_type::String  # "residential", "commercial", "industrial"
    pv_capacity::Float64  # kW_peak
    battery_capacity::Float64  # kWh
    has_pv::Bool
    has_battery::Bool
end

# Time series container
struct TimeSeriesData{T}
    data::Vector{T}
    start_time::DateTime
    end_time::DateTime
    interval::Period
end

end
