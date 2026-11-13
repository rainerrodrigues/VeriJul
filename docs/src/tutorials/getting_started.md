```@meta
CurrentModule = VeriJul
```

# Getting started

This tutorial builds a small Verilog design, drives it from Julia and
records a waveform. It uses the 4-tap moving-average filter from
[`examples/filter.v`](https://github.com/rainerrodrigues/VeriJul.jl/blob/main/examples/filter.v):

```verilog
module filter (
    input  wire       clk,
    input  wire [7:0] in_data,
    output reg  [7:0] out_data
);
```

On every rising edge of `clk` it shifts `in_data` into a 4-entry history and
outputs the average of the previous four samples.

## Build and load the design

[`load_dut`](@ref) runs Verilator, compiles the result and loads it. Builds
are cached, so running it again with the same sources is instant.

```@example start
using VeriJul

src = joinpath(pkgdir(VeriJul), "examples", "filter.v")
dut = load_dut(src, "filter"; build_dir=mktempdir())
```

The [`DUT`](@ref) shows its ports. You can also list them with
[`ports`](@ref):

```@example start
ports(dut)
```

## Drive the clock

A [`Simulator`](@ref) owns simulation time and toggles the `clk` input in a
background task once you call [`start_clock!`](@ref). By default the clock
has a half period of 5 time units, so rising edges arrive every 10.

```@example start
sim = Simulator(dut)
start_clock!(sim)
```

[`@tick`](@ref) waits for rising edges. Set an input, wait, and read the
output:

```@example start
dut.in_data = 0xFF
for cycle in 1:6
    @tick sim
    println("t = ", sim.time, "   out_data = ", dut.out_data)
end
```

The output ramps up over four cycles as the history fills with `0xFF`, one
cycle later than you might expect because `out_data` is itself a register.

Inputs take any integer and are truncated to the port width, just like a
Verilog assignment:

```@example start
dut.in_data = 0x142    # 9 bits; only the low 8 are kept
dut.in_data
```

## Record a waveform

Call [`enable_trace!`](@ref) before simulating to write a VCD file. Each
clock edge adds a sample at `sim.time`. The file is flushed when the design
is destroyed.

```@example start
stop_clock!(sim)
destroy!(dut)

dut = load_dut(src, "filter"; build_dir=mktempdir())
vcd = joinpath(mktempdir(), "filter.vcd")
enable_trace!(dut, vcd)

sim = Simulator(dut)
start_clock!(sim)
for x in (0x10, 0x80, 0xFF, 0x00, 0x40)
    dut.in_data = x
    @tick sim 2
end
stop_clock!(sim)
destroy!(dut)

filesize(vcd)
```

Open the file in [GTKWave](https://gtkwave.sourceforge.net/) or
[Surfer](https://surfer-project.org/) to see `clk`, `in_data`, `out_data`
and the internal shift register.

## Clean up

Always stop the clock before destroying a design: the clock task calls into
the model on every edge. [`stop_clock!`](@ref) waits for that task to finish.
A design that is garbage-collected is destroyed automatically, but calling
[`destroy!`](@ref) yourself makes sure the waveform is written.

Next: [Self-checking testbenches](@ref).
