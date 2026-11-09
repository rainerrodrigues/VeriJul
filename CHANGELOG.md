# Changelog

## v0.2.0

### Added
- `load_dut(sources, top; ...)` builds (with caching) and loads a design in
  one call, returning a `DUT` whose ports are properties: `dut.in_data = 0x42`,
  `dut.out_data`. Any number of designs can be loaded at once.
- Ports wider than 64 bits, read and written as `BigInt`. Inputs can now be
  read back as well as written.
- Build options: multiple source files, `include_dirs`, `defines`,
  `parameters`, `verilator_args`, `force`.
- Build caching: unchanged designs are not rebuilt.
- Multiple clocks with `add_clock!(sim, name; half_period, phase)`, all on
  one timeline. `Simulator(dut; clock=:clk_main)` names the main clock.
- `tick(sim, n; clock, edge, timeout)` and `@tick sim n key=value...`.
- `reset!(sim, port; cycles, active_high)`.
- `ClockStopped` and `TickTimeout` errors, so waiting testbenches fail instead
  of hanging when the clock stops or an edge never arrives.
- `settle!(dut)` evaluates without a clock edge; `enable_trace!(dut, file)`.
- Tutorials in the documentation, and a migration guide.

### Changed
- `sim.time` is now the time of the most recent clock edge.
- Library files are named `libV<top>_<hash>.<ext>`.
- Function pointers are looked up once at load time instead of on every call.

### Compatibility
- The 0.1 interface (`build_dut` + generated `AutoBindings`,
  `VerilatedModel`, `sim.rising_edge`, `sim.clk_val`) still works.

## v0.1.0

First release.
