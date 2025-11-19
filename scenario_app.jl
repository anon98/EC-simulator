# scenario_app.jl
# Main application launcher for LEC Scenario Generator

push!(LOAD_PATH, joinpath(@__DIR__, "src"))

using HTTP

include("src/server.jl")
using .Server

function open_browser(url::String)
    @static if Sys.iswindows()
        run(`cmd /c start $url`, wait=false)
    elseif Sys.isapple()
        run(`open $url`, wait=false)
    else
        run(`xdg-open $url`, wait=false)
    end
end

function main()
    println("=" ^ 60)
    println("🏘️  LEC Scenario Generator Application")
    println("=" ^ 60)
    println()
    
    port = 8080
    host = "127.0.0.1"
    url = "http://$host:$port/index.html"  # Landing page with both options
    
    # Start server in async task
    @async begin
        try
            start_server(port=port, host=host)
        catch e
            println("Server error: $e")
        end
    end
    
    # Wait for server to start
    println("Starting server...")
    sleep(2)
    
    # Open browser
    println("Opening browser at $url")
    try
        open_browser(url)
    catch e
        println("Could not auto-open browser. Please manually navigate to:")
        println("  $url")
    end
    
    println()
    println("Server is running. Press Ctrl+C to stop.")
    println()
    
    # Keep running
    try
        while true
            sleep(1)
        end
    catch InterruptException
        println("\nShutting down...")
        stop_server()
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
