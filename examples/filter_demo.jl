# Drive the 4-tap moving-average filter in examples/filter.v from Julia.
# Run with:  julia --project=. examples/filter_demo.jl
using VeriJul

dut = load_dut(joinpath(@__DIR__, "filter.v"), "filter"; build_dir=mktempdir())
enable_trace!(dut, "filter.vcd")                 # optional waveform dump

sim = Simulator(dut)
start_clock!(sim)

dut.in_data = 0xFF
for cycle in 1:6
    @tick sim
    println("cycle $cycle: out_data = ", dut.out_data)
end

stop_clock!(sim)
destroy!(dut)                                    # flushes filter.vcd
