```@meta
CurrentModule = VeriJul
```

# API

## Building

```@docs
build_dut
VeriJul.Builder.verilator_version
VeriJul.Builder.HardwarePort
VeriJul.Builder.extract_ports
VeriJul.Builder.generate_bindings
```

## Models

```@docs
VerilatedModel
eval_step!
destroy!
```

## Simulation

```@docs
Simulator
start_clock!
stop_clock!
@tick
@testbench
```
