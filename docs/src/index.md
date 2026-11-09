```@meta
CurrentModule = VeriJul
```

# VeriJul.jl

VeriJul lets you write hardware testbenches in Julia. It compiles a Verilog
design with [Verilator](https://www.veripool.org/verilator/), generates Julia
bindings for its ports, and drives the simulation from ordinary Julia tasks.

## Requirements

- Julia 1.10 or newer
- Verilator 4.200 or newer on your `PATH`
- A C++17 compiler (`g++` or `clang++`; set `CXX` to pick one)

VeriJul is tested on Linux and macOS. Windows is not supported yet.

```bash
# Ubuntu / Debian
sudo apt-get install verilator g++
# macOS
brew install verilator
```

## Installation

```julia
using Pkg
Pkg.add("VeriJul")
```

Next, see the [Guide](@ref) for a full walkthrough.
