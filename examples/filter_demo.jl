# Drive the 4-tap moving-average filter in examples/filter.v from Julia.
# Run with:  julia --project=. examples/filter_demo.jl
using VeriJul

lib, bindings = build_dut(joinpath(@__DIR__, "filter.v"), "filter"; build_dir=mktempdir())
include(bindings)          # defines the AutoBindings module
using .AutoBindings

dut = VerilatedModel(lib)
sim = Simulator(dut)
AutoBindings.enable_trace!(dut, "filter.vcd")   # optional waveform dump

@testbench function ramp(sim)
    AutoBindings.set_in_data!(sim.dut, 0xFF)
    for cycle in 1:6
        @tick sim
        println("cycle $cycle: out_data = ", AutoBindings.get_out_data(sim.dut))
    end
end

start_clock!(sim)
wait(launch_ramp(sim))
stop_clock!(sim)
destroy!(dut)              # flushes filter.vcd
