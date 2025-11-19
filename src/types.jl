module Types

export SimulationParams, Battery, PVSystem, Load, Node, Community
export AbstractMarketModel, P2PNashBargaining, CommunitySelfConsumption, SDRPricing, PayAsClear

struct SimulationParams
    dt::Float64
    simulation_hours::Int
    num_steps::Int
    
    function SimulationParams(dt::Float64, simulation_hours::Int)
        num_steps = Int(simulation_hours / dt) + 1
        new(dt, simulation_hours, num_steps)
    end
end

mutable struct Battery
    capacity::Float64
    max_charge_rate::Float64
    max_discharge_rate::Float64
    soc::Float64 # Current SOC in kWh
    min_soc::Float64
    max_soc::Float64
    
    function Battery(;capacity=200.0, max_charge_rate=50.0, max_discharge_rate=50.0, initial_soc=0.5, min_soc=0.2, max_soc=0.8)
        new(capacity, max_charge_rate, max_discharge_rate, initial_soc * capacity, min_soc, max_soc)
    end
end

struct PVSystem
    amplitude_factor::Float64
end

struct Load
    base_load::Float64
    variability::Float64
end

mutable struct Node
    id::Int
    pv::Union{PVSystem, Nothing}
    battery::Union{Battery, Nothing}
    load::Load
    
    # State tracking
    current_generation::Float64
    current_load::Float64
    net_power::Float64 # generation - load
end

# --- Market Models ---

abstract type AbstractMarketModel end

struct P2PNashBargaining <: AbstractMarketModel end

struct CommunitySelfConsumption <: AbstractMarketModel end

struct SDRPricing <: AbstractMarketModel end

struct PayAsClear <: AbstractMarketModel end

struct Community
    nodes::Vector{Node}
    market_model::AbstractMarketModel
    cooperative_nodes::Vector{Int}
end

end
