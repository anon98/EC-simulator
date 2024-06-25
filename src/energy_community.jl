# energy_community.jl
using ArgParse
using FilePathsBase: mkpath  # For creating directories if they don't exist
include("simulation.jl")
include("cleanup.jl")
cleanup_images()
function parse_arguments()
    s = ArgParseSettings()
    
    @add_arg_table! s begin
        "--num_nodes"
        help = "Number of nodes in the energy community"
        arg_type = Int
        default = 5
        
        "--pv_nodes"
        help = "Comma-separated list of nodes with PV systems"
        arg_type = String
        default = "1,3,4"
        
        "--battery_nodes"
        help = "Comma-separated list of nodes with batteries"
        arg_type = String
        default = "2,3,5"
        
        "--cooperative"
        help = "Flag to enable cooperative behavior"
        action = :store_true
        
        "--cooperative_nodes"
        help = "Comma-separated list of nodes that are cooperative"
        arg_type = String
        default = "1,2"
    end
    
    parsed_args = parse_args(s)
    
    num_nodes = parsed_args["num_nodes"]
    pv_nodes = [parse(Int, x) for x in split(parsed_args["pv_nodes"], ",")]
    battery_nodes = [parse(Int, x) for x in split(parsed_args["battery_nodes"], ",")]
    cooperative = parsed_args["cooperative"]
    cooperative_nodes = [parse(Int, x) for x in split(parsed_args["cooperative_nodes"], ",")]

    return num_nodes, pv_nodes, battery_nodes, cooperative, cooperative_nodes
end

function central_management(num_nodes, pv_nodes, battery_nodes, cooperative, cooperative_nodes)
    dt = 1.0
    simulation_hours = 24

    times, solar_generation_data, load_profile_data, battery_soc, grid_interactions, net_profit, transaction_matrix = simulate_energy_community(num_nodes, SIMULATION_HOURS, DT, pv_nodes, battery_nodes, cooperative, cooperative_nodes)
    
    println("Total Net Profit for $num_nodes nodes: $net_profit Euros")

    # Create output directory if it doesn't exist
    output_dir = "outputs/images_EC"
    mkpath(output_dir)
    
    # Plot for each node
    for n in 1:num_nodes
        p = plot()
        if n in pv_nodes
            plot!(p, times, solar_generation_data[:, n], label="Solar PV Generation (kW)", linewidth=2, color="blue")
        end
        plot!(p, times, load_profile_data[:, n], label="Load Profile (kW)", linewidth=2, color="red")
        if n in battery_nodes
            plot!(p, times, battery_soc[n, :] ./ BATTERY_CAPACITY * 100, label="Battery SOC (%)", linewidth=2, color="green")
        end
        plot!(p, times, grid_interactions[n, :], label="Grid Interactions (kW)", linewidth=2, color="black")

        xlabel!(p, "Time (hours)")
        ylabel!(p, "Power (kW) / SOC (%) / Grid (kW)")
        title!(p, "Microgrid Simulation - Node $n")
        savefig(p, joinpath(output_dir, "microgrid_simulation_node_$n.png"))
    end
    
    # Plot for net transactions
    net_transactions = sum(grid_interactions, dims=1)
    p_net = plot(times, net_transactions[:], label="Net Transactions (kW)", linewidth=2, color="purple")
    xlabel!(p_net, "Time (hours)")
    ylabel!(p_net, "Net Transactions (kW)")
    title!(p_net, "Energy Community Net Transactions")
    savefig(p_net, joinpath(output_dir, "energy_community_net_transactions.png"))

    # Plot transactions between cooperative nodes
    if cooperative
        for i in 1:length(cooperative_nodes)
            for j in 1:length(cooperative_nodes)
                if i != j
                    p_trans = plot(times, transaction_matrix[i, j, :], label="Transactions from Node $i to Node $j (kW)", linewidth=2, color="orange")
                    xlabel!(p_trans, "Time (hours)")
                    ylabel!(p_trans, "Power (kW)")
                    title!(p_trans, "Transactions between Cooperative Nodes")
                    savefig(p_trans, joinpath(output_dir, "transactions_node_$(cooperative_nodes[i])_to_node_$(cooperative_nodes[j]).png"))
                end
            end
        end
    end
end

num_nodes, pv_nodes, battery_nodes, cooperative, cooperative_nodes = parse_arguments()
central_management(num_nodes, pv_nodes, battery_nodes, cooperative, cooperative_nodes)