# Changelog

## v0.1.0

First release.

- `load_dut(sources, top; ...)` builds and loads a Verilog design with
  Verilator and returns a `DUT` whose ports are properties:
  `dut.in_data = 0x42`, `dut.out_data`. Ports of any width are supported;
  ports wider than 64 bits are `BigInt`s. Any number of designs can be loaded
  at once.
- Build options: multiple source files, `include_dirs`, `defines`,
  `parameters`, `verilator_args`, `force`, `verbose`.
- Build caching. By default builds go into VeriJul's own scratch space, so
  nothing is written to the working directory; a `build_dir` you pass is
  only emptied if VeriJul created it. `clear_build_cache()` removes cached
  builds.
- `Simulator` with multiple clocks on one timeline (`add_clock!`),
  `tick`/`@tick sim n` with `clock`, `edge` and `timeout` options, and
  `reset!`. Waiting testbenches get `ClockStopped` or `TickTimeout` errors
  instead of hanging.
- `@testbench`, `settle!`, VCD waveforms with `enable_trace!`.
- A lower-level API: `build_dut`, the generated `AutoBindings` module, and
  `VerilatedModel`.
- `VERIJUL_VERILATOR` and `CXX` choose the Verilator and C++ compiler
  executables.
- Documentation with four tutorials, and runnable examples.
