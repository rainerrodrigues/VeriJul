module DSL

using ..Core
export @tick, @testbench

"""
    @tick sim

Pauses the current execution until the next rising edge of the simulator's clock.
"""
macro tick(sim)
    return quote
        # 'wait' pauses the current Task until the simulator calls 'notify'
        wait($(esc(sim)).rising_edge)
    end
end

"""
    @testbench func

Wraps a standard function into an asynchronous Task so it can yield to the simulator.
"""
macro testbench(expr)
    # Ensures the macro is applied to a function
    @assert expr.head == :function || expr.head == :(=) "Must be applied to a function"
    
    func_name = expr.args[1].args[1]
    
    return quote
        # Defines the user's function
        $(esc(expr))
        
        # Creates a launcher for it
        function $(esc(Symbol("launch_", func_name)))(sim::Simulator)
            @async $(esc(func_name))(sim)
        end
    end
end

end