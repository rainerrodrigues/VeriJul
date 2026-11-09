module Interop

using Libdl # Julia's Dynamic Library loader
export VerilatedModel, eval_step!, destroy!

"""
    VerilatedModel(lib_path, create_sym=:top_create)

Loads the shared library built by [`build_dut`](@ref VeriJul.Builder.build_dut) and instantiates the
model. The model is freed automatically when garbage-collected, or explicitly
with [`destroy!`](@ref VeriJul.Interop.destroy!).
"""
mutable struct VerilatedModel
    ptr::Ptr{Cvoid}
    lib_handle::Ptr{Cvoid} # Store the open library handle instead of path
    
    function VerilatedModel(lib_path::AbstractString, create_sym::Symbol=:top_create)
        # 1. Dynamically load the shared library into memory
        isfile(lib_path) || error("Shared library not found: $lib_path")
        lib_handle = Libdl.dlopen(lib_path)
        
        # 2. Look up the memory address of the C++ create function
        func_ptr = Libdl.dlsym(lib_handle, create_sym)
        
        # 3. Call the function pointer directly
        ptr = ccall(func_ptr, Ptr{Cvoid}, ())
        
        model = new(ptr, lib_handle)
        
        # Attach a finalizer to prevent C++ memory leaks
        finalizer(destroy!, model)
        return model
    end
end

"""
    eval_step!(model, time)

Evaluates the model and, if tracing is enabled, dumps a waveform sample at
`time`. [`start_clock!`](@ref VeriJul.SimCore.start_clock!) calls this for you on every clock edge.
"""
function eval_step!(model::VerilatedModel, time::Integer)
    func_ptr = Libdl.dlsym(model.lib_handle, :top_eval)
    ccall(func_ptr, Cvoid, (Ptr{Cvoid}, UInt64), model.ptr, UInt64(time))
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
        
        # Safely close the library
        Libdl.dlclose(model.lib_handle)
        model.lib_handle = C_NULL
    end
end

end