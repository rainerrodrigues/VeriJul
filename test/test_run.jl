# Integration test: build filter.v with Verilator, then drive it from Julia.
# Included from runtests.jl, so it runs inside a @testset at Main's top level.

project_root = dirname(@__DIR__)
verilog_file = joinpath(project_root, "examples", "filter.v")
build_dir = mktempdir()

so_path, binding_path = VeriJul.Builder.build_dut(verilog_file, "filter"; build_dir=build_dir)
@test isfile(so_path)

include(binding_path)
using .AutoBindings

dut = VerilatedModel(so_path, :top_create)
sim = Simulator(dut)
vcd_path = joinpath(build_dir, "waveform.vcd")
AutoBindings.enable_trace!(sim.dut, vcd_path)

@test AutoBindings.get_out_data(sim.dut) == 0x00

start_clock!(sim)
@test_throws ErrorException start_clock!(sim)   # double-start is rejected

outputs = UInt8[]
@sync @async begin
    # Hold 0xFF long enough to fill the 4-tap pipeline plus the output register
    AutoBindings.set_in_data!(sim.dut, 0xFF)
    for _ in 1:6
        @tick sim
        push!(outputs, AutoBindings.get_out_data(sim.dut))
    end
    @test outputs[end] == 0xFF
    @test issorted(outputs)          # moving average ramps up monotonically
    @test any(<(0xFF), outputs)      # ...and isn't instantly at full scale

    # Drain back to zero
    AutoBindings.set_in_data!(sim.dut, 0)
    for _ in 1:6
        @tick sim
    end
    @test AutoBindings.get_out_data(sim.dut) == 0x00
end

stop_clock!(sim)
@test sim.clock_task === nothing
@test sim.time > 0

destroy!(dut)
@test isfile(vcd_path) && filesize(vcd_path) > 0
