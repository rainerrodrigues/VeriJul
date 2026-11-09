# VeriJul.jl

[![CI](https://github.com/rainerrodrigues/VeriJul.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/rainerrodrigues/VeriJul.jl/actions/workflows/ci.yml)
[![Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://rainerrodrigues.github.io/VeriJul.jl/dev/)
[![codecov](https://codecov.io/gh/rainerrodrigues/VeriJul.jl/graph/badge.svg)](https://codecov.io/gh/rainerrodrigues/VeriJul.jl)
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

dut = load_dut("examples/filter.v", "filter")   # build (cached) and load
enable_trace!(dut, "filter.vcd")                 # optional waveform

sim = Simulator(dut)                             # drives the `clk` input
start_clock!(sim)

dut.in_data = 0xFF
for cycle in 1:6
    @tick sim                                    # wait for a rising edge
    println("cycle $cycle: out_data = ", dut.out_data)
end

stop_clock!(sim)
destroy!(dut)
```

Also included:

- multi-file designs, include directories, `` `define``s and parameter overrides
- several clocks with their own periods (`add_clock!`), `@tick sim n clock=:clk_b`
- `reset!`, and timeouts so stuck testbenches fail instead of hanging
- ports of any width, with wide ports as `BigInt`

The [documentation](https://rainerrodrigues.github.io/VeriJul.jl/dev/) has
tutorials for each of these and the API reference. Runnable scripts are in
[`examples/`](examples/).

## Running the tests

```julia
julia --project=. -e 'using Pkg; Pkg.test()'
```

The hardware integration tests are skipped when Verilator or a C++ compiler
is not installed.

## License

MIT. See [LICENSE](LICENSE).
