```@meta
CurrentModule = VeriJul
```

# API

## Loading designs

```@docs
load_dut
DUT
ports
settle!
enable_trace!
destroy!
```

## Simulation

```@docs
Simulator
add_clock!
start_clock!
stop_clock!
tick
@tick
reset!
@testbench
ClockStopped
TickTimeout
```

## Building

```@docs
build_dut
VeriJul.Builder.clear_build_cache
VeriJul.Builder.verilator_cmd
VeriJul.Builder.verilator_version
HardwarePort
VeriJul.Builder.extract_ports
VeriJul.Builder.generate_bindings
```

## Low-level model access

```@docs
VerilatedModel
eval_step!
```
