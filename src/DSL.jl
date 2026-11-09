module DSL

using ..SimCore: Simulator
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

Defines `func` as usual and also a `launch_<func>(sim::Simulator)` that runs it
as an asynchronous task, so it can wait on clock edges with [`@tick`](@ref VeriJul.DSL.@tick).

```julia
@testbench function drive(sim)
    AutoBindings.set_in_data!(sim.dut, 0xFF)
    @tick sim
end

task = launch_drive(sim)
wait(task)
```
"""
macro testbench(expr)
    # Ensures the macro is applied to a function
    (expr isa Expr && (expr.head == :function || expr.head == :(=))) ||
        throw(ArgumentError("@testbench must be applied to a function definition"))

    # Strip a return-type annotation / where clause to reach the call signature
    sig = expr.args[1]
    while sig isa Expr && sig.head in (:where, :(::))
        sig = sig.args[1]
    end
    func_name = sig.args[1]
    
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