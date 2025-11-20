module Market

using ..Types

export solve_market

# === Global economic assumptions ============================================
# Units:
#   - net_power: kW  (positive = surplus, negative = deficit)
#   - dt: hours
#   - prices: €/kWh
#   - energy traded in each step: kWh = kW * dt
#
# Economic baseline:
#   - Surplus agents (producers) can always export to the grid at FEED_IN_TARIFF.
#   - Deficit agents (consumers) can always import from the grid at grid_price.
#   - "Cooperative profit" is the *additional* surplus of the community
#     compared to everyone separately interacting with the grid:
#         ΔW = shared_energy * (grid_price - FEED_IN_TARIFF) * dt

const FEED_IN_TARIFF = 0.05  # €/kWh, placeholder; better: take from model or community


# --- Helper Functions --------------------------------------------------------

"""
    negotiate_price(excess_power, deficit_power, grid_price;
                    feed_in_tariff = FEED_IN_TARIFF)

Compute a Nash-bargaining-style internal trading price between a surplus side
and a deficit side.

Assumptions per unit of energy:
  - Seller fallback: feed_in_tariff  (export to grid)
  - Buyer fallback:  grid_price      (import from grid)
  - Seller utility per unit:  u_s(p) = p - feed_in_tariff
  - Buyer utility per unit:   u_b(p) = grid_price - p

With asymmetric bargaining power α ∈ [0,1] (buyer weight), the Nash product is
    [u_s(p)]^(1-α) * [u_b(p)]^α
Maximization yields the closed-form solution
    p* = α * grid_price + (1 - α) * feed_in_tariff

Here we choose α proportional to the *relative demand*:
    α = deficit_power / (excess_power + deficit_power)
so that the side with the larger volume gets more bargaining power.

If both sides are zero, the function returns the mid-price between grid and feed-in.
"""
function negotiate_price(excess_power::Float64,
                         deficit_power::Float64,
                         grid_price::Float64;
                         feed_in_tariff::Float64 = FEED_IN_TARIFF)

    total_power = excess_power + deficit_power

    if total_power <= 0
        # Degenerate case: no meaningful trade volume -> arbitrary but bounded
        return 0.5 * (grid_price + feed_in_tariff)
    end

    # Buyer bargaining weight α based on relative demand volume
    α = deficit_power / total_power
    α = clamp(α, 0.0, 1.0)

    # Nash bargaining solution with asymmetric bargaining power
    negotiated_price = α * grid_price + (1 - α) * feed_in_tariff
    return negotiated_price
end


# --- Market Solver Interface -------------------------------------------------

function solve_market(community::Community, grid_price::Float64, dt::Float64)
    return solve_market(community.market_model, community, grid_price, dt)
end


# === 1. P2P Nash Bargaining =================================================

"""
    solve_market(model::P2PNashBargaining, community, grid_price, dt)

Bilateral matching among cooperative nodes using a simple greedy algorithm:
  - Sellers: nodes with net_power > 0
  - Buyers:  nodes with net_power < 0
For each seller–buyer pair, we trade up to the minimum of their remaining
surplus/deficit at a Nash-bargained price.

Transactions are recorded in:
  - `transactions[i]` (kW): net P2P power for node i
      (negative = net seller, positive = net buyer)
  - `transaction_matrix[i,j]` (kW): power from i (seller) to j (buyer)

Total cooperative profit is measured relative to the reference of everyone
trading with the external grid:
  ΔW = shared_energy * (grid_price - FEED_IN_TARIFF) * dt
"""
function solve_market(model::P2PNashBargaining,
                      community::Community,
                      grid_price::Float64,
                      dt::Float64)

    coop_indices        = community.cooperative_nodes
    n                   = length(community.nodes)
    transactions        = zeros(Float64, n)
    transaction_matrix  = zeros(Float64, n, n)

    # Remaining net power in kW
    remaining_net_power = [node.net_power for node in community.nodes]

    for seller_idx in coop_indices
        if remaining_net_power[seller_idx] > 0
            for buyer_idx in coop_indices
                if remaining_net_power[buyer_idx] < 0

                    excess  = remaining_net_power[seller_idx]
                    deficit = -remaining_net_power[buyer_idx]
                    amount  = min(excess, deficit)  # kW

                    if amount > 1e-9
                        price = negotiate_price(
                            excess, deficit, grid_price;
                            feed_in_tariff = FEED_IN_TARIFF
                        )

                        # Update remaining powers (kW)
                        remaining_net_power[seller_idx] -= amount
                        remaining_net_power[buyer_idx]  += amount

                        # Bookkeeping in kW (instantaneous power)
                        transactions[seller_idx]      -= amount
                        transactions[buyer_idx]       += amount
                        transaction_matrix[seller_idx, buyer_idx] += amount
                    end
                end
            end
        end
    end

    # Total community energy traded internally (kW -> kWh via dt)
    shared_power   = sum(max(0.0, transactions[i]) for i in coop_indices)
    shared_energy  = shared_power * dt  # kWh

    total_cooperative_profit =
        shared_energy * (grid_price - FEED_IN_TARIFF)

    return transactions, transaction_matrix, total_cooperative_profit
end


# === 2. Community Self-Consumption (Pro-rata) ===============================

"""
    solve_market(model::CommunitySelfConsumption, community, grid_price, dt)

Virtual sharing with a single community pool:
  - Total cooperative surplus = min(total_excess, total_deficit)
  - Surpluses are pooled and allocated pro-rata to deficits.
  - Internal transfer price is purely virtual (no explicit €-flows).

Cooperative profit is defined as the avoided external exchanges with the grid:
  ΔW = shared_energy * (grid_price - FEED_IN_TARIFF) * dt
"""
function solve_market(model::CommunitySelfConsumption,
                      community::Community,
                      grid_price::Float64,
                      dt::Float64)

    coop_indices       = community.cooperative_nodes
    n                  = length(community.nodes)
    transactions       = zeros(Float64, n)
    transaction_matrix = zeros(Float64, n, n)

    total_excess  = sum(max(0.0, community.nodes[i].net_power)  for i in coop_indices)
    total_deficit = sum(max(0.0, -community.nodes[i].net_power) for i in coop_indices)

    shared_power = min(total_excess, total_deficit)

    if shared_power > 1e-9
        for seller_idx in coop_indices
            p_seller = community.nodes[seller_idx].net_power
            if p_seller > 0
                share_contribution = p_seller / total_excess
                sold_amount        = share_contribution * shared_power  # kW

                transactions[seller_idx] -= sold_amount

                # Distribute this sold amount to buyers pro-rata to their deficits
                for buyer_idx in coop_indices
                    p_buyer = community.nodes[buyer_idx].net_power
                    if p_buyer < 0
                        share_consumption = -p_buyer / total_deficit
                        bought_amount     = sold_amount * share_consumption

                        transactions[buyer_idx]       += bought_amount
                        transaction_matrix[seller_idx, buyer_idx] += bought_amount
                    end
                end
            end
        end
    end

    shared_energy = shared_power * dt  # kWh

    # Community surplus vs. everyone trading with grid independently
    total_cooperative_profit =
        shared_energy * (grid_price - FEED_IN_TARIFF)

    return transactions, transaction_matrix, total_cooperative_profit
end


# === 3. SDR Pricing (Supply/Demand Ratio) ===================================

"""
    solve_market(model::SDRPricing, community, grid_price, dt)

SDR-based internal price:
  - total_supply = total_excess ≥ 0
  - total_demand = total_deficit ≥ 0
  - λ = total_demand / (total_supply + total_demand) ∈ [0,1]
  - internal_price = FEED_IN_TARIFF + λ * (grid_price - FEED_IN_TARIFF)

Thus:
  - If demand ≪ supply, λ ≈ 0 ⇒ price ≈ FEED_IN_TARIFF.
  - If demand ≫ supply, λ ≈ 1 ⇒ price ≈ grid_price.

Matching of energy is as in CommunitySelfConsumption (pro-rata).
Total community surplus is again measured relative to FEED_IN_TARIFF / grid.
"""
function solve_market(model::SDRPricing,
                      community::Community,
                      grid_price::Float64,
                      dt::Float64)

    coop_indices       = community.cooperative_nodes
    n                  = length(community.nodes)
    transactions       = zeros(Float64, n)
    transaction_matrix = zeros(Float64, n, n)

    total_excess  = sum(max(0.0, community.nodes[i].net_power)  for i in coop_indices)
    total_deficit = sum(max(0.0, -community.nodes[i].net_power) for i in coop_indices)

    total_volume = total_excess + total_deficit

    internal_price::Float64
    if total_volume <= 1e-9
        # No internal trade; price is irrelevant but keep it bounded
        internal_price = 0.5 * (grid_price + FEED_IN_TARIFF)
    else
        λ = total_deficit / total_volume  # demand share ∈ [0,1]
        internal_price = FEED_IN_TARIFF + λ * (grid_price - FEED_IN_TARIFF)
    end

    # Pro-rata matching identical to CommunitySelfConsumption
    shared_power = min(total_excess, total_deficit)

    if shared_power > 1e-9
        for seller_idx in coop_indices
            p_seller = community.nodes[seller_idx].net_power
            if p_seller > 0
                share_contribution = p_seller / total_excess
                sold_amount        = share_contribution * shared_power

                transactions[seller_idx] -= sold_amount

                for buyer_idx in coop_indices
                    p_buyer = community.nodes[buyer_idx].net_power
                    if p_buyer < 0
                        share_consumption = -p_buyer / total_deficit
                        bought_amount     = sold_amount * share_consumption

                        transactions[buyer_idx]       += bought_amount
                        transaction_matrix[seller_idx, buyer_idx] += bought_amount
                    end
                end
            end
        end
    end

    shared_energy = shared_power * dt  # kWh

    # Note: with the assumed baseline, *total* community surplus does NOT
    # depend on the internal_price, only on the traded volume.
    total_cooperative_profit =
        shared_energy * (grid_price - FEED_IN_TARIFF)

    return transactions, transaction_matrix, total_cooperative_profit
end


# === 4. Pay-as-Clear (Double Auction) =======================================

"""
    solve_market(model::PayAsClear, community, grid_price, dt)

Stylized uniform-price double auction:

  - Buyers bid up to grid_price.
  - Sellers are willing to accept down to FEED_IN_TARIFF.
  - With homogeneous valuations, any price in [FEED_IN_TARIFF, grid_price]
    implements the same allocative outcome (same traded quantity).

Here we use a simple rule:
  - If total_excess > total_deficit: price = FEED_IN_TARIFF (supply abundant)
  - If total_deficit > total_excess: price = grid_price   (demand tight)
  - If equal:                         mid-price

Matching is again pro-rata. Total community surplus is computed relative to
the grid baseline and equals shared_energy * (grid_price - FEED_IN_TARIFF) * dt.
"""
function solve_market(model::PayAsClear,
                      community::Community,
                      grid_price::Float64,
                      dt::Float64)

    coop_indices  = community.cooperative_nodes
    n             = length(community.nodes)

    total_excess  = sum(max(0.0, community.nodes[i].net_power)  for i in coop_indices)
    total_deficit = sum(max(0.0, -community.nodes[i].net_power) for i in coop_indices)

    clearing_price::Float64
    if total_excess > total_deficit
        clearing_price = FEED_IN_TARIFF
    elseif total_deficit > total_excess
        clearing_price = grid_price
    else
        clearing_price = 0.5 * (grid_price + FEED_IN_TARIFF)
    end

    # Pro-rata matching
    transactions       = zeros(Float64, n)
    transaction_matrix = zeros(Float64, n, n)

    shared_power = min(total_excess, total_deficit)

    if shared_power > 1e-9
        for seller_idx in coop_indices
            p_seller = community.nodes[seller_idx].net_power
            if p_seller > 0
                share_contribution = p_seller / total_excess
                sold_amount        = share_contribution * shared_power

                transactions[seller_idx] -= sold_amount

                for buyer_idx in coop_indices
                    p_buyer = community.nodes[buyer_idx].net_power
                    if p_buyer < 0
                        share_consumption = -p_buyer / total_deficit
                        bought_amount     = sold_amount * share_consumption

                        transactions[buyer_idx]       += bought_amount
                        transaction_matrix[seller_idx, buyer_idx] += bought_amount
                    end
                end
            end
        end
    end

    shared_energy = shared_power * dt  # kWh

    total_cooperative_profit =
        shared_energy * (grid_price - FEED_IN_TARIFF)

    return transactions, transaction_matrix, total_cooperative_profit
end

end
