module SimCore

using Libdl
using ..Interop
using ..Interop: VerilatedModel
using ..Device: Device, DUT

export Simulator, start_clock!, stop_clock!, add_clock!, tick, reset!,
       ClockStopped, TickTimeout

"""
    ClockStopped()

Thrown by [`tick`](@ref VeriJul.SimCore.tick) when the clock isn't running, or
stops while a task is waiting for an edge.
"""
struct ClockStopped <: Exception
    msg::String
end
ClockStopped() = ClockStopped("the simulator clock is not running; call start_clock!(sim)")
Base.showerror(io::IO, e::ClockStopped) = print(io, "ClockStopped: ", e.msg)

"""
    TickTimeout(seconds)

Thrown by [`tick`](@ref VeriJul.SimCore.tick) when the requested edges don't
arrive within `timeout` seconds of wall-clock time.
"""
struct TickTimeout <: Exception
    seconds::Float64
end
Base.showerror(io::IO, e::TickTimeout) =
    print(io, "TickTimeout: no clock edge arrived within $(e.seconds) s")

mutable struct Clock
    name::Symbol
    set_ptr::Ptr{Cvoid}
    half_period::Int64
    value::UInt8
    next_toggle::Int64
    rising::Condition
    falling::Condition
end

"""
    Simulator(dut; clock=:clk, half_period=5)

Simulation state for a [`DUT`](@ref VeriJul.Device.DUT) (or a bare
[`VerilatedModel`](@ref VeriJul.Interop.VerilatedModel)): the current time and
the clocks that drive it.

`clock` names the main clock input; [`tick`](@ref VeriJul.SimCore.tick) and
[`@tick`](@ref VeriJul.DSL.@tick) wait on it unless told otherwise. Add more
clocks with [`add_clock!`](@ref VeriJul.SimCore.add_clock!).

`sim.time` is the simulation time of the most recent clock edge.
"""
mutable struct Simulator
    dut::Union{DUT,VerilatedModel}
    model::VerilatedModel
    time::Int64
    clocks::Vector{Clock}
    clock_task::Union{Task,Nothing}
    running::Bool
end

model_of(m::VerilatedModel) = m
model_of(d::DUT) = Device.model(d)

# Setter for a 1-bit control input (clock or reset). DUTs already hold the
# pointers; bare models are looked up in the library.
function input_setter(dut::DUT, ::VerilatedModel, name::Symbol, what::AbstractString)
    h = get(getfield(dut, :handles), name, nothing)
    (h === nothing || h.port.direction != :in) &&
        error("The design has no input port named `$name` to use as $what")
    return h.set_ptr
end

function input_setter(::VerilatedModel, model::VerilatedModel, name::Symbol, what::AbstractString)
    f = Libdl.dlsym(model.lib_handle, Symbol("set_", name); throw_error=false)
    f === nothing && error("The design has no input port named `$name` to use as $what")
    return f
end

function Simulator(dut::Union{DUT,VerilatedModel}; clock::Symbol=:clk, half_period::Integer=5)
    sim = Simulator(dut, model_of(dut), 0, Clock[], nothing, false)
    add_clock!(sim, clock; half_period=half_period)
    return sim
end

# Keep fields from VeriJul 0.1 working: rising_edge, falling_edge, clk_val
function Base.getproperty(sim::Simulator, s::Symbol)
    s === :rising_edge  && return getfield(sim, :clocks)[1].rising
    s === :falling_edge && return getfield(sim, :clocks)[1].falling
    s === :clk_val      && return getfield(sim, :clocks)[1].value
    return getfield(sim, s)
end

"""
    add_clock!(sim, name; half_period=5, phase=0)

Adds another clock input. It toggles every `half_period` time units, starting
at time `phase`. All clocks run on the same timeline, so their edges
interleave correctly. Wait for its edges with `tick(sim; clock=name)`.
"""
function add_clock!(sim::Simulator, name::Symbol; half_period::Integer=5, phase::Integer=0)
    sim.running && error("Add clocks before calling start_clock!")
    half_period > 0 || throw(ArgumentError("half_period must be positive"))
    any(c -> c.name == name, sim.clocks) && error("Clock `$name` already exists")
    set_ptr = input_setter(sim.dut, sim.model, name, "a clock")
    push!(sim.clocks, Clock(name, set_ptr, half_period, 0x00, phase, Condition(), Condition()))
    return sim
end

function find_clock(sim::Simulator, name::Union{Symbol,Nothing})
    name === nothing && return sim.clocks[1]
    i = findfirst(c -> c.name == name, sim.clocks)
    i === nothing && error("No clock named `$name`; add it with add_clock!(sim, :$name)")
    return sim.clocks[i]
end

function wake_all(sim::Simulator, err)
    for c in sim.clocks
        notify(c.rising, err; error=true)
        notify(c.falling, err; error=true)
    end
end

"""
    start_clock!(sim[, half_period]) -> Task

Starts the clocks in a background task. On each step it toggles the clocks
due at the earliest time, evaluates the design (writing a waveform sample if
tracing is on) and wakes tasks waiting in [`tick`](@ref VeriJul.SimCore.tick).

Passing `half_period` changes the main clock's half period (VeriJul 0.1 style).
Throws if the clock is already running.
"""
function start_clock!(sim::Simulator, half_period::Union{Integer,Nothing}=nothing)
    sim.running && error("Clock is already running; call stop_clock!(sim) first")
    half_period === nothing || (sim.clocks[1].half_period = half_period)
    sim.running = true

    sim.clock_task = @async try
        toggled = Clock[]
        while sim.running
            t = minimum(c.next_toggle for c in sim.clocks)
            sim.time = t
            empty!(toggled)
            for c in sim.clocks
                if c.next_toggle == t
                    c.value ⊻= 0x01
                    ccall(c.set_ptr, Cvoid, (Ptr{Cvoid}, UInt8), sim.model.ptr, c.value)
                    c.next_toggle += c.half_period
                    push!(toggled, c)
                end
            end
            Interop.eval_step!(sim.model, t)
            for c in toggled
                notify(c.value == 0x01 ? c.rising : c.falling)
            end
            yield()
        end
    catch err
        # Never leave testbenches waiting on a clock that has died
        sim.running = false
        wake_all(sim, err)
        rethrow()
    end
    return sim.clock_task
end

"""
    stop_clock!(sim)

Stops the clocks and waits for the background task to finish. Tasks still
waiting in [`tick`](@ref VeriJul.SimCore.tick) get a
[`ClockStopped`](@ref VeriJul.SimCore.ClockStopped) error instead of hanging.
Call this before `destroy!`-ing the design.
"""
function stop_clock!(sim::Simulator)
    sim.running = false
    t = sim.clock_task
    t === nothing || wait(t)
    sim.clock_task = nothing
    wake_all(sim, ClockStopped("the simulator clock was stopped"))
    return nothing
end

"""
    tick(sim, n=1; clock=nothing, edge=:rising, timeout=nothing)

Waits for `n` edges of a clock (the main clock unless `clock` is given).
`edge` is `:rising` or `:falling`. `timeout` is a wall-clock limit in seconds;
when it passes, a [`TickTimeout`](@ref VeriJul.SimCore.TickTimeout) is thrown.

Throws [`ClockStopped`](@ref VeriJul.SimCore.ClockStopped) if the clock isn't
running. [`@tick`](@ref VeriJul.DSL.@tick) is shorthand for this.
"""
function tick(sim::Simulator, n::Integer=1; clock::Union{Symbol,Nothing}=nothing,
              edge::Symbol=:rising, timeout::Union{Real,Nothing}=nothing)
    edge in (:rising, :falling) || throw(ArgumentError("edge must be :rising or :falling"))
    n >= 0 || throw(ArgumentError("n must be non-negative"))
    c = find_clock(sim, clock)
    cond = edge === :rising ? c.rising : c.falling
    n == 0 && return sim

    timer = nothing
    done = Ref(false)
    if timeout !== nothing
        waiter = current_task()
        timer = Timer(timeout) do _
            # Interrupt the wait unless the task has already moved on
            done[] || schedule(waiter, TickTimeout(timeout); error=true)
        end
    end
    try
        for _ in 1:n
            sim.running || throw(ClockStopped())
            wait(cond)
        end
    finally
        done[] = true
        timer === nothing || close(timer)
    end
    return sim
end

"""
    reset!(sim, port=:rst; cycles=2, active_high=true)

Asserts a reset input for `cycles` rising edges of the main clock, then
releases it. The clock must be running. Use `active_high=false` for an
active-low reset such as `rst_n`.
"""
function reset!(sim::Simulator, port::Symbol=:rst; cycles::Integer=2, active_high::Bool=true)
    set_ptr = input_setter(sim.dut, sim.model, port, "a reset")
    set(v) = ccall(set_ptr, Cvoid, (Ptr{Cvoid}, UInt8), sim.model.ptr, UInt8(v == active_high))
    set(true)
    try
        tick(sim, cycles)
    finally
        sim.model.ptr == C_NULL || set(false)
    end
    return sim
end

end
