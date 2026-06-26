module Interop

using Libdl # Julia's Dynamic Library loader
export VerilatedModel, eval_step!, destroy!

# The core handle for the hardware model
mutable struct VerilatedModel
    ptr::Ptr{Cvoid}
    lib_handle::Ptr{Cvoid} # Store the open library handle instead of path
    
    function VerilatedModel(lib_path::String, create_sym::Symbol)
        # 1. Dynamically load the shared library into memory
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

# Evaluate the combinational logic and dump to VCD
function eval_step!(model::VerilatedModel, time::Int64)
    func_ptr = Libdl.dlsym(model.lib_handle, :top_eval)
    ccall(func_ptr, Cvoid, (Ptr{Cvoid}, UInt64), model.ptr, UInt64(time))
end

# Memory cleanup
function destroy!(model::VerilatedModel)
    if model.ptr != C_NULL
        func_ptr = Libdl.dlsym(model.lib_handle, :top_destroy)
        ccall(func_ptr, Cvoid, (Ptr{Cvoid},), model.ptr)
        model.ptr = C_NULL
        
        # Safely close the library
        Libdl.dlclose(model.lib_handle)
    end
end

end