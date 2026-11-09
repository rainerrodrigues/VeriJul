```@meta
CurrentModule = VeriJul
```

# Migrating from 0.1

Code written for VeriJul 0.1 keeps working in 0.2. The new interface is
shorter and avoids a module that every design shared.

| VeriJul 0.1 | VeriJul 0.2 |
|---|---|
| `lib, b = build_dut(src, "top"); include(b); using .AutoBindings` | `dut = load_dut(src, "top")` |
| `dut = VerilatedModel(lib, :top_create)` | (part of `load_dut`) |
| `AutoBindings.set_in_data!(dut, 0x42)` | `dut.in_data = 0x42` |
| `AutoBindings.get_out_data(dut)` | `dut.out_data` |
| `AutoBindings.enable_trace!(dut, "w.vcd")` | `enable_trace!(dut, "w.vcd")` |
| `@tick sim` (repeated) | `@tick sim n` |

## Behaviour changes

- `build_dut` caches builds and names the library `libV<top>_<hash>.so`
  (or `.dylib`). Use the returned path rather than building it yourself.
- `load_dut` uses `build/<top>` as its default build directory, so several
  designs can share a working directory.
- `tick`/`@tick` throw [`ClockStopped`](@ref) when the clock isn't running,
  where 0.1 would wait forever.
- `sim.time` is the time of the most recent clock edge. In 0.1 it was the
  time of the next edge.
- `sim.rising_edge`, `sim.falling_edge` and `sim.clk_val` still exist and
  refer to the main clock.
- Every design's generated module is called `AutoBindings`, so including the
  bindings of a second design replaces the first. `load_dut` doesn't generate
  a module, so any number of designs can be loaded at once.
