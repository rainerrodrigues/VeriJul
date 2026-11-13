```@meta
CurrentModule = VeriJul
```

# Build options and multiple clocks

Real designs span several files, use `` `include `` and `` `define ``, have
parameters, and often more than one clock. This tutorial uses the counter in
[`examples/counter`](https://github.com/rainerrodrigues/VeriJul.jl/tree/main/examples/counter):

```text
examples/counter/
├── counter.v          top module, `include "consts.vh"
├── inverter.v         submodule
└── include/consts.vh  defines INIT_VAL (default 8'd7)
```

```verilog
module counter #(parameter WIDTH = 8) (
    input  wire             clk,        // count += step on each rising edge
    input  wire             clk_slow,   // slow_count += 1 on each rising edge
    input  wire             rst,
    input  wire [WIDTH-1:0] step,
    input  wire [99:0]      wide_in,
    output wire [99:0]      wide_out,   // ~wide_in
    output wire [63:0]      upper,      // wide_in[99:36]
    output wire [7:0]       init_val,   // `INIT_VAL
    output reg  [WIDTH-1:0] count,
    output reg  [15:0]      slow_count
);
```

## Multiple files and include directories

Pass a vector of sources and the directories `` `include `` should search:

```@example clocks
using VeriJul

dir = joinpath(pkgdir(VeriJul), "examples", "counter")
srcs = [joinpath(dir, "counter.v"), joinpath(dir, "inverter.v")]
incs = [joinpath(dir, "include")]

dut = load_dut(srcs, "counter"; include_dirs=incs, build_dir=mktempdir())
```

## Parameters and defines

`parameters` overrides top-level parameters (Verilator's `-G`) and `defines`
sets preprocessor macros (`+define+`). Each combination is its own build, and
each is cached:

```@example clocks
wide = load_dut(srcs, "counter"; include_dirs=incs, build_dir=mktempdir(),
                parameters=Dict("WIDTH" => 12),
                defines=Dict("INIT_VAL" => "8'd42"))
settle!(dut); settle!(wide)
(default_init = dut.init_val, overridden_init = wide.init_val,
 count_width = only(p.width for p in ports(wide) if p.name == "count"))
```

[`settle!`](@ref) evaluates the design without a clock edge, so
combinational outputs like `init_val` update. Use `defines=Dict("NAME" => nothing)`
for a macro without a value, and `verilator_args` for any other Verilator flag.

### Build caching

`load_dut` and [`build_dut`](@ref) skip the build when the sources, the files
in `include_dirs`, the options, the Verilator version and the compiler are
all unchanged. Pass `force=true` to rebuild anyway, for example after editing
a file that is included from outside `include_dirs`, and `verbose=true` to
see Verilator's output.

### Where builds go

Without `build_dir`, each design and set of options gets its own folder in
VeriJul's build cache (a [Scratch.jl](https://github.com/JuliaPackaging/Scratch.jl)
space in your Julia depot), so nothing is written to the current directory
and cached builds survive between sessions. [`clear_build_cache`](@ref VeriJul.Builder.clear_build_cache)
deletes them, and they are removed when VeriJul is uninstalled.

If you pass `build_dir`, it must be new, empty, or a directory VeriJul
created before (VeriJul marks those with a `.verijul-build` file). VeriJul
refuses to use a non-empty directory it didn't create, so it never deletes
your files.

```@example clocks
destroy!(wide) # hide
nothing # hide
```

## Two clocks

The [`Simulator`](@ref) drives `clk` by default. Add other clocks with
[`add_clock!`](@ref) before starting. Here `clk` has a period of 10 and
`clk_slow` a period of 30:

```@example clocks
sim = Simulator(dut)                         # clk: half period 5
add_clock!(sim, :clk_slow; half_period=15)
start_clock!(sim)

reset!(sim)
dut.step = 1
for _ in 1:7
    @tick sim
    println("t = ", lpad(sim.time, 3), "   count = ", lpad(Int(dut.count), 2),
            "   slow_count = ", dut.slow_count)
end
```

All clocks share one timeline, so their edges interleave correctly: the
simulator always advances to the earliest pending edge, toggles every clock
due at that time, and evaluates the design once.

Wait for a specific clock with `clock=`, and for falling edges with
`edge=:falling`:

```@example clocks
@tick sim 2 clock=:clk_slow
(time = sim.time, slow_count = dut.slow_count)
```

```@example clocks
@tick sim edge=:falling
sim.time
```

Use `phase` to offset a clock: `add_clock!(sim, :clk_b; half_period=5, phase=2)`
first toggles `clk_b` at time 2.

```@example clocks
stop_clock!(sim) # hide
destroy!(dut) # hide
nothing # hide
```

Next: [Ports and wide signals](@ref).
