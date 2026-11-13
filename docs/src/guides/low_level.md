```@meta
CurrentModule = VeriJul
```

# Lower-level API

[`load_dut`](@ref) and [`DUT`](@ref) cover most uses. Underneath them is a
smaller interface that works on a bare [`VerilatedModel`](@ref) and a
generated bindings file. It is useful when you want the build step and the
loading step separate, or want to see exactly what VeriJul generates.

| With `load_dut` | Lower-level equivalent |
|---|---|
| `dut = load_dut(src, "top")` | `lib, b = build_dut(src, "top"); include(b); using .AutoBindings; m = VerilatedModel(lib)` |
| `dut.in_data = 0x42` | `AutoBindings.set_in_data!(m, 0x42)` |
| `dut.out_data` | `AutoBindings.get_out_data(m)` |
| `enable_trace!(dut, "w.vcd")` | `AutoBindings.enable_trace!(m, "w.vcd")` or `enable_trace!(m, "w.vcd")` |
| `Simulator(dut)` | `Simulator(m)` |

[`build_dut`](@ref) returns the path of the compiled library and of the
generated `bindings.jl`. That file defines a module called `AutoBindings` with
a `get_<port>` function for every port and a `set_<port>!` function for every
input. Values follow the same rules as `DUT` properties (see
[Ports and wide signals](@ref)).

## Limits

- Every design's generated module is called `AutoBindings`, so including the
  bindings of a second design replaces the first. `load_dut` doesn't generate
  a module, so any number of designs can be loaded at once.
- Function lookups in `AutoBindings` happen on every call. `DUT` looks them
  up once when the design is loaded.

## Simulator fields

`sim.rising_edge` and `sim.falling_edge` are the `Condition`s that the main
clock notifies on each edge, and `sim.clk_val` is the main clock's current
value. [`tick`](@ref) is usually more convenient than waiting on them
directly.
