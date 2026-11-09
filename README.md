# VeriJul.jl

[![CI](https://github.com/rainerrodrigues/VeriJul/actions/workflows/ci.yml/badge.svg)](https://github.com/rainerrodrigues/VeriJul/actions/workflows/ci.yml)
[![Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://rainerrodrigues.github.io/VeriJul/dev/)
[![codecov](https://codecov.io/gh/rainerrodrigues/VeriJul/graph/badge.svg)](https://codecov.io/gh/rainerrodrigues/VeriJul)
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

Write hardware testbenches in Julia. VeriJul compiles a Verilog design with
[Verilator](https://www.veripool.org/verilator/), generates Julia bindings for
its ports, and drives the simulation from ordinary Julia tasks, with optional
VCD waveform output.

## Requirements

- Julia 1.10 or newer
- Verilator 4.200 or newer
- A C++17 compiler (`g++` or `clang++`; set `CXX` to choose)

Tested on Linux and macOS. Windows is not supported yet.

```bash
sudo apt-get install verilator g++   # Ubuntu / Debian
brew install verilator               # macOS
```

## Installation

```julia
using Pkg
Pkg.add("VeriJul")
```

## Example

```julia
using VeriJul

lib, bindings = build_dut("examples/filter.v", "filter")
include(bindings)
using .AutoBindings

dut = VerilatedModel(lib)
sim = Simulator(dut)
AutoBindings.enable_trace!(dut, "filter.vcd")

@testbench function ramp(sim)
    AutoBindings.set_in_data!(sim.dut, 0xFF)
    for cycle in 1:6
        @tick sim
        println("cycle $cycle: out_data = ", AutoBindings.get_out_data(sim.dut))
    end
end

start_clock!(sim)
wait(launch_ramp(sim))
stop_clock!(sim)
destroy!(dut)
```

The full script is in [`examples/filter_demo.jl`](examples/filter_demo.jl).
See the [documentation](https://rainerrodrigues.github.io/VeriJul/dev/) for a
step-by-step guide and the API reference.

## Running the tests

```julia
julia --project=. -e 'using Pkg; Pkg.test()'
```

The hardware integration tests are skipped when Verilator or a C++ compiler
is not installed.

## License

MIT. See [LICENSE](LICENSE).
