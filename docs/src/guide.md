```@meta
CurrentModule = VeriJul
```

# Guide

This walkthrough drives the 4-tap moving-average filter from
[`examples/filter.v`](https://github.com/rainerrodrigues/VeriJul/blob/main/examples/filter.v).

## 1. Build the design

```julia
using VeriJul
lib, bindings = build_dut("filter.v", "filter"; build_dir="build")
```

[`build_dut`](@ref) runs Verilator, reads the top module's ports and compiles a
shared library. Pass `verbose=true` to see the tool output.

## 2. Load the bindings

```julia
include(bindings)
using .AutoBindings
```

The generated `AutoBindings` module has one function per port:

| Port direction | Function |
|---|---|
| input `in_data` | `AutoBindings.set_in_data!(dut, value)` |
| output `out_data` | `AutoBindings.get_out_data(dut)` |

Inputs accept any integer and are masked to the port width. Ports up to 64 bits
are supported.

## 3. Create a simulator

```julia
dut = VerilatedModel(lib)
sim = Simulator(dut)
AutoBindings.enable_trace!(dut, "filter.vcd")   # optional
```

The design needs an input named `clk`. [`start_clock!`](@ref) toggles it in a
background task.

## 4. Write a testbench

```julia
@testbench function ramp(sim)
    AutoBindings.set_in_data!(sim.dut, 0xFF)
    for cycle in 1:6
        @tick sim                     # wait for the next rising edge
        println(cycle, " => ", AutoBindings.get_out_data(sim.dut))
    end
end

start_clock!(sim)
wait(launch_ramp(sim))
```

## 5. Clean up

```julia
stop_clock!(sim)
destroy!(dut)      # closes the VCD file
```

Always stop the clock before destroying the model. Open `filter.vcd` in a
waveform viewer such as GTKWave to inspect the run.
