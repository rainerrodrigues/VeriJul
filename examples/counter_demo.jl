# Two clocks, a reset, build options and a 100-bit port, using examples/counter.
# Run with:  julia --project=. examples/counter_demo.jl
using VeriJul

dir = joinpath(@__DIR__, "counter")
dut = load_dut([joinpath(dir, "counter.v"), joinpath(dir, "inverter.v")], "counter";
               include_dirs=[joinpath(dir, "include")],
               parameters=Dict("WIDTH" => 12),
               defines=Dict("INIT_VAL" => "8'd42"),
               build_dir=mktempdir())
display(dut)

sim = Simulator(dut)                              # clk: period 10
add_clock!(sim, :clk_slow; half_period=15)        # clk_slow: period 30
start_clock!(sim)
reset!(sim)

dut.step = 5
for _ in 1:6
    @tick sim
    println("t = $(sim.time)  count = $(dut.count)  slow_count = $(dut.slow_count)")
end

dut.wide_in = big(2)^99 + 1
@tick sim
println("wide_out = 0x", string(dut.wide_out, base=16), "   init_val = ", dut.init_val)

stop_clock!(sim)
destroy!(dut)
