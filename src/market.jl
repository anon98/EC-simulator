module Market

using ..Types

export solve_market

# --- Helper Functions ---

function negotiate_price(excess_power, deficit_power, grid_price)
    # Nash Bargaining Solution
    total_power = excess_power + deficit_power
    if total_power == 0
        return grid_price / 2
    else
        surplus_ratio = excess_power / total_power
        deficit_ratio = deficit_power / total_power
        
        # Weighted price based on surplus and deficit ratios
        negotiated_price = grid_price * surplus_ratio + (grid_price / 2) * deficit_ratio
        return negotiated_price
    end
end

# --- Market Solver Interface ---

function solve_market(community::Community, grid_price::Float64, dt::Float64)
    return solve_market(community.market_model, community, grid_price, dt)
end

# --- Concrete Implementations ---

# 1. P2P Nash Bargaining
function solve_market(model::P2PNashBargaining, community::Community, grid_price::Float64, dt::Float64)
    # println("  [P2P Nash Bargaining] Optimizing market...")
    
    coop_indices = community.cooperative_nodes
    transactions = zeros(length(community.nodes))
    transaction_matrix = zeros(length(community.nodes), length(community.nodes))
    total_cooperative_profit = 0.0

    remaining_net_power = [node.net_power for node in community.nodes]

    trade_count = 0
    for seller_idx in coop_indices
        if remaining_net_power[seller_idx] > 0
            for buyer_idx in coop_indices
                if remaining_net_power[buyer_idx] < 0
                    
                    amount = min(remaining_net_power[seller_idx], -remaining_net_power[buyer_idx])
                    
                    if amount > 1e-6
                        price = negotiate_price(remaining_net_power[seller_idx], -remaining_net_power[buyer_idx], grid_price)
                        
                        transaction_profit = amount * (grid_price - price) * dt
                        total_cooperative_profit += transaction_profit

                        remaining_net_power[seller_idx] -= amount
                        remaining_net_power[buyer_idx] += amount
                        
                        transactions[seller_idx] -= amount
                        transactions[buyer_idx] += amount
                        transaction_matrix[seller_idx, buyer_idx] += amount
                        trade_count += 1
                    end
                end
            end
        end
    end
    
    # println("    Trades: $trade_count | Profit: €$(round(total_cooperative_profit, digits=2))")

    return transactions, transaction_matrix, total_cooperative_profit
end

# 2. Community Self-Consumption (Pro-rata)
function solve_market(model::CommunitySelfConsumption, community::Community, grid_price::Float64, dt::Float64)
    # println("  [Community Self-Consumption] Optimizing market...")
    
    coop_indices = community.cooperative_nodes
    transactions = zeros(length(community.nodes))
    transaction_matrix = zeros(length(community.nodes), length(community.nodes))
    
    total_excess = sum(max(0, community.nodes[i].net_power) for i in coop_indices)
    total_deficit = sum(max(0, -community.nodes[i].net_power) for i in coop_indices)
    
    if total_excess > 0 && total_deficit > 0
        # Distribute excess proportionally to deficit
        shared_energy = min(total_excess, total_deficit)
        
        for seller_idx in coop_indices
            if community.nodes[seller_idx].net_power > 0
                share_contribution = community.nodes[seller_idx].net_power / total_excess
                sold_amount = share_contribution * shared_energy
                
                transactions[seller_idx] -= sold_amount
                
                # Distribute this sold amount to buyers
                for buyer_idx in coop_indices
                    if community.nodes[buyer_idx].net_power < 0
                        share_consumption = -community.nodes[buyer_idx].net_power / total_deficit
                        bought_amount = sold_amount * share_consumption
                        
                        transactions[buyer_idx] += bought_amount
                        transaction_matrix[seller_idx, buyer_idx] += bought_amount
                    end
                end
            end
        end
    end
    
    # Profit is simply the shared energy * grid price (savings)
    # In this model, we assume a unified community bill or internal price = 0 (virtual sharing)
    total_cooperative_profit = sum((transactions[i] for i in coop_indices if transactions[i] > 0), init=0.0) * grid_price * dt
    
    # println("    Shared energy: $(round(min(total_excess, total_deficit), digits=2)) kW | Profit: €$(round(total_cooperative_profit, digits=2))")
    
    return transactions, transaction_matrix, total_cooperative_profit
end

# 3. SDR Pricing (Supply/Demand Ratio)
function solve_market(model::SDRPricing, community::Community, grid_price::Float64, dt::Float64)
    # println("  [SDR Pricing] Optimizing market...")
    
    coop_indices = community.cooperative_nodes
    transactions = zeros(length(community.nodes))
    transaction_matrix = zeros(length(community.nodes), length(community.nodes))
    
    total_excess = sum(max(0, community.nodes[i].net_power) for i in coop_indices)
    total_deficit = sum(max(0, -community.nodes[i].net_power) for i in coop_indices)
    
    # Calculate SDR Price
    # Heuristic: Price varies linearly between Feed-in Tariff (assumed 0.05) and Grid Price
    feed_in_tariff = 0.05
    
    if total_deficit == 0
        internal_price = feed_in_tariff
    elseif total_excess == 0
        internal_price = grid_price
    else
        sdr = total_excess / total_deficit
        # If excess >= deficit, price drops towards feed-in
        # If excess < deficit, price rises towards grid price
        if sdr >= 1.0
            internal_price = feed_in_tariff + (grid_price - feed_in_tariff) * exp(-(sdr-1)) # Decay
        else
            internal_price = grid_price - (grid_price - feed_in_tariff) * sdr
        end
    end
    
    # println("    SDR: $(round(total_excess/max(total_deficit,1e-6), digits=2)) | Price: €$(round(internal_price, digits=3))/kWh")
    
    # Match energy (Pro-rata like Community Self-Consumption but with explicit price)
    shared_energy = min(total_excess, total_deficit)
    
    if shared_energy > 0
        for seller_idx in coop_indices
            if community.nodes[seller_idx].net_power > 0
                share_contribution = community.nodes[seller_idx].net_power / total_excess
                sold_amount = share_contribution * shared_energy
                transactions[seller_idx] -= sold_amount
                
                for buyer_idx in coop_indices
                    if community.nodes[buyer_idx].net_power < 0
                        share_consumption = -community.nodes[buyer_idx].net_power / total_deficit
                        bought_amount = sold_amount * share_consumption
                        transactions[buyer_idx] += bought_amount
                        transaction_matrix[seller_idx, buyer_idx] += bought_amount
                    end
                end
            end
        end
    end
    
    # Profit calculation
    # Sellers gain: sold_amount * (internal_price - feed_in_tariff)
    # Buyers gain: bought_amount * (grid_price - internal_price)
    # Total community gain = shared_energy * (grid_price - feed_in_tariff)
    total_cooperative_profit = shared_energy * (grid_price - feed_in_tariff) * dt
    
    return transactions, transaction_matrix, total_cooperative_profit
end

# 4. Pay-as-Clear (Double Auction)
function solve_market(model::PayAsClear, community::Community, grid_price::Float64, dt::Float64)
    # println("  [Pay-as-Clear] Optimizing market...")
    
    # Simplified Double Auction
    # Bids: Buyers bid grid_price (willing to pay up to grid)
    # Offers: Sellers offer feed_in_tariff (willing to sell down to feed-in)
    # Clearing price is the intersection.
    
    # In this simplified setup with homogeneous preferences, the clearing price 
    # is usually determined by the marginal unit.
    # If Demand > Supply -> Price = Grid Price
    # If Supply > Demand -> Price = Feed-in Tariff
    # If Supply == Demand -> Price = (Grid + Feed-in) / 2
    
    feed_in_tariff = 0.05
    
    coop_indices = community.cooperative_nodes
    total_excess = sum(max(0, community.nodes[i].net_power) for i in coop_indices)
    total_deficit = sum(max(0, -community.nodes[i].net_power) for i in coop_indices)
    
    if total_excess > total_deficit
        clearing_price = feed_in_tariff
    elseif total_deficit > total_excess
        clearing_price = grid_price
    else
        clearing_price = (grid_price + feed_in_tariff) / 2
    end
    
    # println("    Clearing price: €$(round(clearing_price, digits=3))/kWh")
    
    # Match energy
    transactions = zeros(length(community.nodes))
    transaction_matrix = zeros(length(community.nodes), length(community.nodes))
    
    shared_energy = min(total_excess, total_deficit)
    
    if shared_energy > 0
        # Pro-rata matching for simplicity in this implementation
        for seller_idx in coop_indices
            if community.nodes[seller_idx].net_power > 0
                share_contribution = community.nodes[seller_idx].net_power / total_excess
                sold_amount = share_contribution * shared_energy
                transactions[seller_idx] -= sold_amount
                
                for buyer_idx in coop_indices
                    if community.nodes[buyer_idx].net_power < 0
                        share_consumption = -community.nodes[buyer_idx].net_power / total_deficit
                        bought_amount = sold_amount * share_consumption
                        transactions[buyer_idx] += bought_amount
                        transaction_matrix[seller_idx, buyer_idx] += bought_amount
                    end
                end
            end
        end
    end
    
    total_cooperative_profit = shared_energy * (grid_price - feed_in_tariff) * dt
    
    return transactions, transaction_matrix, total_cooperative_profit
end

end
