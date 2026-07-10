using VeriJul

println("--- Starting VeriJul Build Process ---")

project_root = dirname(@__DIR__) 
verilog_file = joinpath(project_root, "src", "filter.v")

# Building the library
so_path, binding_path = VeriJul.Builder.build_dut(verilog_file, "filter")

# Loading the bindings
include(binding_path)
using .AutoBindings

# Instantiating the simulation
dut = VeriJul.Interop.VerilatedModel(so_path, :top_create)
sim = VeriJul.Core.Simulator(dut)

AutoBindings.enable_trace!(sim.dut, abspath("build/wavefo

println("--- Simulation Initialized ---")

# START THE HARDWARE CLOCK
VeriJul.Core.start_clock!(sim)

# Running an asynchronous Testbench
@sync begin
    @async begin
        println("[t=$(sim.time)] Initial out_data: ", AutoBindings.get_out_data(sim.dut))
        
        println("[t=$(sim.time)] Setting in_data to 0xFF...")
        AutoBindings.set_in_data!(sim.dut, 0xFF)
        
        # Waiting for the next rising edge (the background clock task handles the actual toggling)
        @tick sim 
        
        println("[t=$(sim.time)] out_data after cycle 1: ", AutoBindings.get_out_data(sim.dut))
        
        println("[t=$(sim.time)] Setting in_data to 0x42...")
        AutoBindings.set_in_data!(sim.dut, 0x42)
        
        @tick sim 
        
        println("[t=$(sim.time)] out_data after cycle 2: ", AutoBindings.get_out_data(sim.dut))
    end
end

println("--- Test Complete ---")