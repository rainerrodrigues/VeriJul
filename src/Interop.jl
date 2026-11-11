module Interop

using Libdl # Julia's Dynamic Library loader
export VerilatedModel, eval_step!, settle!, destroy!, enable_trace!

"""
    VerilatedModel(lib_path, create_sym=:top_create)

Loads a shared library built by [`build_dut`](@ref VeriJul.Builder.build_dut)
and instantiates the model. The model is freed automatically when
garbage-collected, or explicitly with [`destroy!`](@ref VeriJul.Interop.destroy!).

Most code should use [`load_dut`](@ref VeriJul.Device.load_dut) instead, which
returns a [`DUT`](@ref VeriJul.Device.DUT) with named port access.
"""
mutable struct VerilatedModel
    ptr::Ptr{Cvoid}
    lib_handle::Ptr{Cvoid}
    # Looked up once at load time instead of on every call
    eval_ptr::Ptr{Cvoid}
    settle_ptr::Ptr{Cvoid}

    function VerilatedModel(lib_path::AbstractString, create_sym::Symbol=:top_create)
        isfile(lib_path) || error("Shared library not found: $lib_path")
        lib_handle = Libdl.dlopen(lib_path)

        ptr = ccall(Libdl.dlsym(lib_handle, create_sym), Ptr{Cvoid}, ())
        eval_ptr = Libdl.dlsym(lib_handle, :top_eval)
        # Libraries from earlier development builds lack top_settle; fall back to top_eval
        settle_ptr = something(Libdl.dlsym(lib_handle, :top_settle; throw_error=false), C_NULL)

        model = new(ptr, lib_handle, eval_ptr, settle_ptr)
        finalizer(destroy!, model)
        return model
    end

    # Internal: wrap existing function pointers (no library, no finalizer).
    # Used by the test suite to drive the simulator with a mock design.
    VerilatedModel(ptr::Ptr{Cvoid}, eval_ptr::Ptr{Cvoid}, settle_ptr::Ptr{Cvoid}) =
        new(ptr, C_NULL, eval_ptr, settle_ptr)
end

function check_alive(model::VerilatedModel)
    model.ptr == C_NULL && error("This model has been destroyed")
    return model
end

"""
    eval_step!(model, time)

Evaluates the model and, if tracing is enabled, dumps a waveform sample at
`time`. The simulator's clock calls this for you on every clock edge.
"""
function eval_step!(model::VerilatedModel, time::Integer)
    check_alive(model)
    ccall(model.eval_ptr, Cvoid, (Ptr{Cvoid}, UInt64), model.ptr, UInt64(time))
end

"""
    settle!(model)

Evaluates the model without writing a waveform sample, so combinational
outputs reflect inputs you just set. Useful for designs without a clock.
"""
function settle!(model::VerilatedModel)
    check_alive(model)
    if model.settle_ptr == C_NULL
        ccall(model.eval_ptr, Cvoid, (Ptr{Cvoid}, UInt64), model.ptr, UInt64(0))
    else
        ccall(model.settle_ptr, Cvoid, (Ptr{Cvoid},), model.ptr)
    end
    return model
end

"""
    enable_trace!(model, filename)

Starts writing a VCD waveform to `filename`. The file is flushed and closed
by [`destroy!`](@ref VeriJul.Interop.destroy!).
"""
function enable_trace!(model::VerilatedModel, filename::AbstractString)
    check_alive(model)
    f = Libdl.dlsym(model.lib_handle, :top_enable_trace)
    ccall(f, Cvoid, (Ptr{Cvoid}, Cstring), model.ptr, filename)
    return model
end

"""
    destroy!(model)

Frees the C++ model, closes its VCD file and unloads the library. Safe to call
more than once. Stop any running clock with [`stop_clock!`](@ref VeriJul.SimCore.stop_clock!) first.
"""
function destroy!(model::VerilatedModel)
    if model.ptr != C_NULL
        func_ptr = Libdl.dlsym(model.lib_handle, :top_destroy)
        ccall(func_ptr, Cvoid, (Ptr{Cvoid},), model.ptr)
        model.ptr = C_NULL
        Libdl.dlclose(model.lib_handle)
        model.lib_handle = C_NULL
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Port access shared by the DUT API and the generated AutoBindings

nwords(width::Integer) = cld(width, 32)

# Convert little-endian 32-bit words (word 1 holds the lowest bits) to a BigInt.
function words_to_int(words::AbstractVector{UInt32})
    v = big(0)
    for i in length(words):-1:1
        v = (v << 32) | words[i]
    end
    return v
end

# Split `val` into `nwords(width)` little-endian 32-bit words, masked to `width` bits.
function int_to_words(val::Integer, width::Integer)
    v = big(val) & ((big(1) << width) - 1)   # also wraps negative values
    return [UInt32((v >> (32 * (i - 1))) & 0xffffffff) for i in 1:nwords(width)]
end

mask64(width::Integer) = width >= 64 ? typemax(UInt64) : (UInt64(1) << width) - 1

# Call a generated `get_<port>` function. Ports up to 64 bits return the
# matching unsigned integer type; wider ports return a `BigInt`.
function read_port(fptr::Ptr{Cvoid}, model::VerilatedModel, width::Integer)
    p = check_alive(model).ptr
    if width <= 8
        return ccall(fptr, UInt8, (Ptr{Cvoid},), p)
    elseif width <= 16
        return ccall(fptr, UInt16, (Ptr{Cvoid},), p)
    elseif width <= 32
        return ccall(fptr, UInt32, (Ptr{Cvoid},), p)
    elseif width <= 64
        return ccall(fptr, UInt64, (Ptr{Cvoid},), p)
    else
        buf = zeros(UInt32, nwords(width))
        ccall(fptr, Cvoid, (Ptr{Cvoid}, Ptr{UInt32}), p, buf)
        return words_to_int(buf)
    end
end

# Call a generated `set_<port>` function. `val` is truncated to `width` bits,
# like a Verilog assignment, so negative numbers give their two's complement.
function write_port(fptr::Ptr{Cvoid}, model::VerilatedModel, width::Integer, val::Integer)
    p = check_alive(model).ptr
    if width <= 64
        v = (val % UInt64) & mask64(width)
        if width <= 8
            ccall(fptr, Cvoid, (Ptr{Cvoid}, UInt8), p, v % UInt8)
        elseif width <= 16
            ccall(fptr, Cvoid, (Ptr{Cvoid}, UInt16), p, v % UInt16)
        elseif width <= 32
            ccall(fptr, Cvoid, (Ptr{Cvoid}, UInt32), p, v % UInt32)
        else
            ccall(fptr, Cvoid, (Ptr{Cvoid}, UInt64), p, v)
        end
    else
        buf = int_to_words(val, width)
        ccall(fptr, Cvoid, (Ptr{Cvoid}, Ptr{UInt32}), p, buf)
    end
    return nothing
end

end
