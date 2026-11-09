module Builder

using Libdl

export build_dut, HardwarePort, extract_ports, generate_bindings, verilator_version

"""
    HardwarePort(name, direction, width)

A top-level port of a Verilated design. `direction` is `:in` or `:out`
(`inout` ports are treated as `:in`), `width` is the bit width.
"""
struct HardwarePort
    name::String
    direction::Symbol
    width::Int
end

# Oldest Verilator release the generated wrapper is known to work with.
const MIN_VERILATOR = v"4.200"

"""
    verilator_version() -> VersionNumber

Returns the version of the `verilator` executable on `PATH`, or throws an
error explaining how to install it.
"""
function verilator_version()
    Sys.which("verilator") === nothing &&
        error("`verilator` was not found on PATH. Install it (e.g. `apt install verilator` or `brew install verilator`).")
    out = read(`verilator --version`, String)
    m = match(r"Verilator\s+(\d+)\.(\d+)", out)
    m === nothing && error("Could not parse Verilator version from: $(repr(out))")
    return VersionNumber(parse(Int, m[1]), parse(Int, m[2]))
end

function check_verilator()
    v = verilator_version()
    v < MIN_VERILATOR && error("VeriJul needs Verilator ≥ $MIN_VERILATOR, found $v")
    return v
end

# Map a port width onto the storage type Verilator uses (CData/SData/IData/QData).
function port_types(width::Int)
    width <= 8  && return ("uint8_t",  "UInt8")
    width <= 16 && return ("uint16_t", "UInt16")
    width <= 32 && return ("uint32_t", "UInt32")
    width <= 64 && return ("uint64_t", "UInt64")
    error("Ports wider than 64 bits (VlWide) are not supported yet (got $width bits)")
end

# Port declarations in the Verilator-generated model header look like
#   VL_IN8(&clk,0,0);  VL_OUT16(&data,15,0);  VL_INW(&wide,99,0,4);
# (older releases omit the `&`).
const PORT_DECL = r"\bVL_(IN|OUT|INOUT)(8|16|64|W)?\(\s*&?\s*(\w+)\s*,\s*(\d+)\s*,\s*(\d+)"

"""
    extract_ports(header_path) -> Vector{HardwarePort}

Reads the ports of a Verilated model from its generated `V<top>.h` header.
"""
function extract_ports(header_path::AbstractString)
    ports = HardwarePort[]
    for m in eachmatch(PORT_DECL, read(header_path, String))
        dir = m[1] == "OUT" ? :out : :in
        width = abs(parse(Int, m[4]) - parse(Int, m[5])) + 1
        push!(ports, HardwarePort(m[3], dir, width))
    end
    isempty(ports) && error("No ports found in $header_path")
    return ports
end

"""
    generate_bindings(ports, module_name) -> (cpp_code, jl_code)

Generates the C++ shim exposing the model through a C ABI, and the Julia
`AutoBindings` module that wraps it (`set_<port>!` / `get_<port>`).
"""
function generate_bindings(ports::Vector{HardwarePort}, module_name::String)
    V = "V$(module_name)"

    cpp_code = """
    #include <cstdint>
    #include <verilated.h>
    #include "verilated_vcd_c.h"
    #include "$V.h"

    // Verilator's runtime calls sc_time_stamp() for \$finish/\$stop messages.
    // It must be defined by the program; macOS refuses to link without it.
    static double vj_time = 0;
    double sc_time_stamp() { return vj_time; }

    // One handle per model instance so several models can trace independently
    struct Handle {
        $V* top;
        VerilatedVcdC* tfp;
    };

    extern "C" {
        Handle* top_create() {
            Verilated::traceEverOn(true);
            return new Handle{new $V(), nullptr};
        }

        void top_enable_trace(Handle* h, const char* filename) {
            if (h->tfp) return;
            h->tfp = new VerilatedVcdC;
            h->top->trace(h->tfp, 99);
            h->tfp->open(filename);
        }

        void top_eval(Handle* h, uint64_t time) {
            vj_time = static_cast<double>(time);
            h->top->eval();
            if (h->tfp) h->tfp->dump(time);
        }

        void top_destroy(Handle* h) {
            h->top->final();
            if (h->tfp) { h->tfp->close(); delete h->tfp; }
            delete h->top;
            delete h;
        }
    """

    jl_code = """
    module AutoBindings
    using VeriJul.Interop
    using Libdl

    function enable_trace!(model::VerilatedModel, filename::AbstractString)
        func_ptr = Libdl.dlsym(model.lib_handle, :top_enable_trace)
        ccall(func_ptr, Cvoid, (Ptr{Cvoid}, Cstring), model.ptr, filename)
    end
    """

    for port in ports
        ctype, jltype = port_types(port.width)
        # Mask inputs to the port width so stray upper bits never reach the model
        storage_bits = parse(Int, jltype[5:end])
        mask = port.width == storage_bits ? "" : " & 0x" * string((UInt64(1) << port.width) - 1, base=16)

        if port.direction == :in
            cpp_code *= "    void set_$(port.name)(Handle* h, $ctype val) { h->top->$(port.name) = val; }\n"
            jl_code *= """
            function set_$(port.name)!(model::VerilatedModel, val::Integer)
                func_ptr = Libdl.dlsym(model.lib_handle, :set_$(port.name))
                ccall(func_ptr, Cvoid, (Ptr{Cvoid}, $jltype), model.ptr, (val % $jltype)$mask)
            end
            """
        else
            cpp_code *= "    $ctype get_$(port.name)(Handle* h) { return h->top->$(port.name); }\n"
            jl_code *= """
            function get_$(port.name)(model::VerilatedModel)
                func_ptr = Libdl.dlsym(model.lib_handle, :get_$(port.name))
                return ccall(func_ptr, $jltype, (Ptr{Cvoid},), model.ptr)
            end
            """
        end
    end

    cpp_code *= "}\n"
    jl_code *= "end\n"

    return cpp_code, jl_code
end

"""
    build_dut(verilog_file, top_module; build_dir="./build", verbose=false) -> (lib_path, bindings_path)

Verilates `verilog_file` with `top_module` as the top, generates bindings and
compiles everything into a shared library. Returns the library path (load it
with [`VerilatedModel`](@ref VeriJul.Interop.VerilatedModel)) and the path of the generated `bindings.jl`
(load it with `include`).

`build_dir` is deleted and recreated. Set the `CXX` environment variable to
choose the C++ compiler (default `g++`, or `c++` on macOS).
"""
function build_dut(verilog_file::String, top_module::String;
                   build_dir::String="./build", verbose::Bool=false)
    verilog_file = abspath(verilog_file)
    isfile(verilog_file) || error("Verilog source not found: $verilog_file")
    vver = check_verilator()

    build_dir = abspath(build_dir)
    rm(build_dir, force=true, recursive=true)
    mkpath(build_dir)

    # Show tool output only when asked, but always surface it if a step fails
    function sh(cmd)
        verbose && return run(cmd)
        log = IOBuffer()
        proc = run(pipeline(ignorestatus(cmd); stdout=log, stderr=log))
        success(proc) || error("Command failed: $cmd\n", String(take!(log)))
        return proc
    end

    verbose && @info "Running Verilator $vver"
    sh(`verilator -Wno-fatal --trace --cc $verilog_file --top-module $top_module -Mdir $build_dir`)

    verbose && @info "Generating bindings"
    ports = extract_ports(joinpath(build_dir, "V$(top_module).h"))
    cpp_code, jl_code = generate_bindings(ports, top_module)

    wrapper_path = joinpath(build_dir, "wrapper.cpp")
    write(wrapper_path, cpp_code)
    jl_binding_path = joinpath(build_dir, "bindings.jl")
    write(jl_binding_path, jl_code)

    verilator_root = strip(read(`verilator --getenv VERILATOR_ROOT`, String))
    inc_dir = joinpath(verilator_root, "include")

    # All V<top_module>*.cpp files generated by Verilator
    generated_cpps = filter(f -> startswith(f, "V$(top_module)") && endswith(f, ".cpp"), readdir(build_dir))
    core_files = [joinpath(inc_dir, "verilated.cpp")]
    for extra in ("verilated_threads.cpp", "verilated_vcd_c.cpp")
        f = joinpath(inc_dir, extra)
        isfile(f) && push!(core_files, f)
    end
    cpp_files = [wrapper_path, joinpath.(build_dir, generated_cpps)..., core_files...]

    output_lib = joinpath(build_dir, "libV$(top_module).$(Libdl.dlext)")
    cxx = get(ENV, "CXX", Sys.isapple() ? "c++" : "g++")
    verbose && @info "Compiling shared library with $cxx"
    sh(`$cxx -std=c++17 -O2 -fPIC -shared -pthread -I$inc_dir -I$(joinpath(inc_dir, "vltstd")) -I$build_dir $cpp_files -o $output_lib`)

    verbose && @info "Build complete" output_lib
    return output_lib, jl_binding_path
end

end
