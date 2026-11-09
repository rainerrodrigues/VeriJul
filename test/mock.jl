# A tiny "design" written in Julia and exposed through C function pointers,
# so the simulator, DUT and tick logic can be tested without Verilator.
# It behaves like examples/counter/counter.v: `count` adds `step` on each
# rising clk edge (cleared while rst is high), `slow_count` adds 1 on each
# rising clk_slow edge, and `wide_out` is ~wide_in over 100 bits.
module MockDesign

using VeriJul
using VeriJul.Interop: VerilatedModel
using VeriJul.Device: DUT, PortHandle

mutable struct State
    clk::UInt8; clk_slow::UInt8; rst::UInt8; step::UInt8
    prev_clk::UInt8; prev_slow::UInt8
    count::UInt8; slow_count::UInt16
    wide_in::Vector{UInt32}
    evals::Int; last_time::UInt64
end
const S = State(0, 0, 0, 0, 0, 0, 0, 0, zeros(UInt32, 4), 0, 0)

function reset_state!()
    S.clk = S.clk_slow = S.rst = S.step = S.prev_clk = S.prev_slow = S.count = 0
    S.slow_count = 0; fill!(S.wide_in, 0); S.evals = 0; S.last_time = 0
end

function eval_model(::Ptr{Cvoid}, time::UInt64)::Cvoid
    S.evals += 1; S.last_time = time
    if S.clk == 1 && S.prev_clk == 0
        S.count = S.rst == 1 ? 0x00 : S.count + S.step
    end
    if S.clk_slow == 1 && S.prev_slow == 0
        S.slow_count = S.rst == 1 ? 0x0000 : S.slow_count + 0x0001
    end
    S.prev_clk = S.clk; S.prev_slow = S.clk_slow
    return nothing
end
settle_model(::Ptr{Cvoid})::Cvoid = nothing

set_clk(::Ptr{Cvoid}, v::UInt8)::Cvoid = (S.clk = v; nothing)
set_clk_slow(::Ptr{Cvoid}, v::UInt8)::Cvoid = (S.clk_slow = v; nothing)
set_rst(::Ptr{Cvoid}, v::UInt8)::Cvoid = (S.rst = v; nothing)
set_step(::Ptr{Cvoid}, v::UInt8)::Cvoid = (S.step = v; nothing)
get_clk(::Ptr{Cvoid})::UInt8 = S.clk
get_rst(::Ptr{Cvoid})::UInt8 = S.rst
get_step(::Ptr{Cvoid})::UInt8 = S.step
get_count(::Ptr{Cvoid})::UInt8 = S.count
get_slow_count(::Ptr{Cvoid})::UInt16 = S.slow_count
function set_wide_in(::Ptr{Cvoid}, p::Ptr{UInt32})::Cvoid
    for i in 1:4; S.wide_in[i] = unsafe_load(p, i); end
    return nothing
end
function get_wide_in(::Ptr{Cvoid}, p::Ptr{UInt32})::Cvoid
    for i in 1:4; unsafe_store!(p, S.wide_in[i], i); end
    return nothing
end
function get_wide_out(::Ptr{Cvoid}, p::Ptr{UInt32})::Cvoid
    for i in 1:4; unsafe_store!(p, ~S.wide_in[i] & (i == 4 ? 0x0000000f : 0xffffffff), i); end
    return nothing
end

function make_dut()
    reset_state!()
    P = Ptr{Cvoid}
    # Static @cfunction pointers for named functions (nothing for the GC to free)
    ptr(f, R, A...) = eval(:(@cfunction($(nameof(f)), $R, ($(A...),))))
    model = VerilatedModel(Ptr{Cvoid}(1), ptr(eval_model, Cvoid, P, UInt64), ptr(settle_model, Cvoid, P))
    specs = [
        ("clk", :in, 1, ptr(get_clk, UInt8, P), ptr(set_clk, Cvoid, P, UInt8)),
        ("clk_slow", :in, 1, ptr(get_clk, UInt8, P), ptr(set_clk_slow, Cvoid, P, UInt8)),
        ("rst", :in, 1, ptr(get_rst, UInt8, P), ptr(set_rst, Cvoid, P, UInt8)),
        ("step", :in, 8, ptr(get_step, UInt8, P), ptr(set_step, Cvoid, P, UInt8)),
        ("wide_in", :in, 100, ptr(get_wide_in, Cvoid, P, Ptr{UInt32}), ptr(set_wide_in, Cvoid, P, Ptr{UInt32})),
        ("wide_out", :out, 100, ptr(get_wide_out, Cvoid, P, Ptr{UInt32}), C_NULL),
        ("count", :out, 8, ptr(get_count, UInt8, P), C_NULL),
        ("slow_count", :out, 16, ptr(get_slow_count, UInt16, P), C_NULL),
    ]
    handles = Dict(Symbol(n) => PortHandle(HardwarePort(n, d, w), g, s) for (n, d, w, g, s) in specs)
    return DUT(model, "mock", "", handles, [Symbol(s[1]) for s in specs])
end

end
