module VeriJul

include("Interop.jl")
include("SimCore.jl")
include("DSL.jl")
include("Builder.jl")

# Re-export the user-facing tools
using .Interop: VerilatedModel, eval_step!, destroy!
using .SimCore: Simulator, start_clock!, stop_clock!
using .DSL: @tick, @testbench
using .Builder: build_dut

export VerilatedModel, eval_step!, destroy!,
       Simulator, start_clock!, stop_clock!,
       @tick, @testbench,
       build_dut

end
