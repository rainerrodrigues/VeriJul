module SimCore

using ..Interop
using Libdl
export Simulator, start_clock!, stop_clock!

"""
    Simulator(dut::VerilatedModel)

Simulation state for a model: current time, clock value, and the
`rising_edge`/`falling_edge` conditions testbenches wait on (see [`@tick`](@ref VeriJul.DSL.@tick)).
The design must have an input port named `clk`.
"""
mutable struct Simulator
    dut::VerilatedModel
    time::Int64
    clk_val::UInt8
    rising_edge::Condition  # The async primitive that testbenches wait on
    falling_edge::Condition
    clock_task::Union{Task,Nothing}
    running::Bool

    Simulator(dut::VerilatedModel) = new(dut, 0, 0x00, Condition(), Condition(), nothing, false)
end

"""
    start_clock!(sim, half_period=5) -> Task

Starts a background task that toggles `clk` every `half_period` time units,
evaluates the model on each edge and wakes any task waiting in [`@tick`](@ref VeriJul.DSL.@tick).
Throws if the clock is already running.
"""
function start_clock!(sim::Simulator, half_period::Integer=5)
    # Starting a second oscillator would toggle the clock twice per step
    sim.running && error("Clock is already running; call stop_clock!(sim) first")

    set_clk_ptr = Libdl.dlsym(sim.dut.lib_handle, :set_clk)
    sim.running = true

    # Launch the clock oscillator as a background coroutine
    sim.clock_task = @async while sim.running
        sim.clk_val = sim.clk_val == 0x01 ? 0x00 : 0x01
        ccall(set_clk_ptr, Cvoid, (Ptr{Cvoid}, UInt8), sim.dut.ptr, sim.clk_val)

        # Evaluate the model and dump the trace
        Interop.eval_step!(sim.dut, sim.time)

        # Wake any testbench code waiting for this edge
        notify(sim.clk_val == 0x01 ? sim.rising_edge : sim.falling_edge)

        # Advance time and hand control back to the Julia scheduler
        sim.time += half_period
        yield()
    end
    return sim.clock_task
end

"""
    stop_clock!(sim)

Stops the background clock and waits for it to finish. Call this before
`destroy!`-ing the model so the clock never touches freed memory.
"""
function stop_clock!(sim::Simulator)
    sim.running = false
    t = sim.clock_task
    t === nothing || wait(t)
    sim.clock_task = nothing
    return nothing
end

end
