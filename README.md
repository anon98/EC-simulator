# test_julia

## Overview

test_julia: this is a Julia-based simulation project that models an energy community with solar generation, battery storage, and cooperative energy management.

## Setup Instructions

1. **Julia Installation and Setup:**
    ``bash
    sudo add-apt-repository ppa:staticfloat/juliareleases
    sudo apt-get update
    sudo apt-get install julia
Install Packages:
    ``bash
    (@v1.7) pkg> add Random
    (@v1.7) pkg> add Plots

2. **Clone the Repository:**

   ```bash
   git clone <repository-url>
   cd test_julia/src

3.  **Run the simulation**

 ```bash
   julia energy_community.jl --num_nodes 6 --pv_nodes "1,2,3,4" --battery_nodes "2,3,5" --cooperative --cooperative_nodes "1,2,3,4"


Directory Structure

    simulation.jl: Main simulation script.
    local_market.jl: Local market logic.
    output/: Directory for simulation output.
        images/: Contains simulation output images.

