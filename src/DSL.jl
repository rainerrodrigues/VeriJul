module DSL

using ..SimCore: Simulator, tick
export @tick, @testbench

"""
    @tick sim
    @tick sim n
    @tick sim n clock=:clk_b edge=:falling timeout=1.0

Waits for the next rising edge of the main clock, or `n` edges. Keywords are
passed to [`tick`](@ref VeriJul.SimCore.tick): `clock`, `edge` and `timeout`
(wall-clock seconds).
"""
macro tick(sim, args...)
    pos = Any[]
    kws = Any[]
    for a in args
        if a isa Expr && a.head === :(=)
            push!(kws, Expr(:kw, a.args[1], esc(a.args[2])))
        else
            isempty(kws) || throw(ArgumentError("@tick: the cycle count must come before keywords"))
            push!(pos, esc(a))
        end
    end
    length(pos) <= 1 || throw(ArgumentError("@tick takes at most one cycle count"))
    return Expr(:call, tick, Expr(:parameters, kws...), esc(sim), pos...)
end

"""
    @testbench func

Defines `func` as usual and also a `launch_<func>(sim::Simulator)` that runs it
as an asynchronous task, so it can wait on clock edges with [`@tick`](@ref VeriJul.DSL.@tick).

```julia
@testbench function drive(sim)
    sim.dut.in_data = 0xFF
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