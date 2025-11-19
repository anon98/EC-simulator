module LECSimulator

include("types.jl")
include("data_schema.jl")
include("data_generation.jl")
include("data_loaders.jl")
include("market.jl")
include("utils.jl")
include("simulation.jl")

# Re-exporting for convenience
using .Types
using .DataSchema
using .DataGeneration
using .DataLoaders
using .Market
using .Utils
using .Simulation

export SimulationParams, Battery, PVSystem, Load, Node, Community
export AbstractMarketModel, P2PNashBargaining, CommunitySelfConsumption, SDRPricing, PayAsClear
export SolarDataPoint, LoadDataPoint, PriceDataPoint, NodeMetadata, TimeSeriesData
export generate_solar_profile, generate_load_profile, generate_price_profile
export AbstractDataLoader, CSVDataLoader, DatabaseLoader
export load_solar_data, load_load_data, load_price_data
export solve_market
export load_config, cleanup_images, plot_results, calculate_kpis, export_to_json
export run_simulation

end
