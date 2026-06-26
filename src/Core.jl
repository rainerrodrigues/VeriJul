module Core

using ..Interop
using Libdl
export Simulator, start_clock!

mutable struct Simulator
    dut::VerilatedModel
    time::Int64
    clk_val::UInt8
    rising_edge::Condition  # The async primitive that testbenches wait on
    falling_edge::Condition
    
    Simulator(dut) = new(dut, 0, 0, Condition(), Condition())
end

function start_clock!(sim::Simulator, half_period::Int64=5)
    # Dynamically find the clock setter function pointer
    set_clk_ptr = Libdl.dlsym(sim.dut.lib_handle, :set_clk)
    
    # Launching the clock oscillator as a background coroutine
    @async while true
        # Toggling the clock
        sim.clk_val = sim.clk_val == 1 ? 0 : 1
        ccall(set_clk_ptr, Cvoid, (Ptr{Cvoid}, UInt8), sim.dut.ptr, sim.clk_val)
        
        #  Evaluate the silicon and dump the trace
        Interop.eval_step!(sim.dut, sim.time)
        
        # Waking up any testbench code waiting for this specific edge
        if sim.clk_val == 1
            notify(sim.rising_edge)
        else
            notify(sim.falling_edge)
        end
        
        # Advancing time and hand control back to the Julia scheduler
        sim.time += half_period
        yield() 
    end
end

end