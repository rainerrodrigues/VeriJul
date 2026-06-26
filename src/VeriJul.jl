module VeriJul

include("Interop.jl")
include("Core.jl")
include("DSL.jl")
include("Builder.jl")

# Re-export the user-facing tools
using .DSL: @tick, @testbench
using .Core: Simulator, run_sim!

export @tick, Simulator, start_clock!

end