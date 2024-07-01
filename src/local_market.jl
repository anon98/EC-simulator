function local_market(cooperative_nodes, net_power_available, current_grid_price, dt)
    total_excess_power = sum(max(0, net_power_available[n]) for n in cooperative_nodes)
    total_deficit_power = sum(-min(0, net_power_available[n]) for n in cooperative_nodes)
    transactions = zeros(length(cooperative_nodes))
    total_cooperative_profit = 0.0  # Track total profit made from cooperative transactions

    transaction_matrix = zeros(length(cooperative_nodes), length(cooperative_nodes))  # To track transactions between nodes

    for n in cooperative_nodes
        if net_power_available[n] > 0  # Node n has excess power
            for m in cooperative_nodes
                if net_power_available[m] < 0  # Node m needs power
                    transfer_power = min(net_power_available[n], -net_power_available[m], BATTERY_MAX_CHARGE_RATE)
                    negotiated_price = negotiate_price(net_power_available[n], -net_power_available[m], current_grid_price)
                    
                    # Calculate profit from this transaction
                    transaction_profit = transfer_power * (current_grid_price - negotiated_price) * dt
                    total_cooperative_profit += transaction_profit
                    
                    net_power_available[n] -= transfer_power
                    net_power_available[m] += transfer_power
                    transactions[findfirst(isequal(n), cooperative_nodes)] -= transfer_power
                    transactions[findfirst(isequal(m), cooperative_nodes)] += transfer_power
                    transaction_matrix[findfirst(isequal(n), cooperative_nodes), findfirst(isequal(m), cooperative_nodes)] += transfer_power
                    total_excess_power -= transfer_power
                    total_deficit_power -= transfer_power
                end
            end
        end
    end
    
    return net_power_available, transactions, transaction_matrix, total_cooperative_profit
end

function negotiate_price(excess_power, deficit_power, grid_price)
    # Nash Bargaining Solution
    total_power = excess_power + deficit_power
    if total_power == 0
        return grid_price / 2  # If no power to negotiate, split the grid price
    else
        
        # This simple approach uses proportional bargaining power
        surplus_ratio = excess_power / total_power
        deficit_ratio = deficit_power / total_power
        
        # Weighted price based on surplus and deficit ratios
        negotiated_price = grid_price * surplus_ratio + (grid_price / 2) * deficit_ratio
        return negotiated_price
    end
end

