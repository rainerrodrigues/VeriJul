module Builder

using Libdl
using Scratch: get_scratch!
using FileWatching.Pidfile: mkpidlock

export build_dut, HardwarePort, extract_ports, generate_bindings, verilator_version,
       verilator_cmd, clear_build_cache

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

# Bump when the generated C++ changes, so cached builds are invalidated.
const WRAPPER_VERSION = 3

"""
    verilator_cmd() -> Cmd

The Verilator command VeriJul runs. Set the `VERIJUL_VERILATOR` environment
variable to the path of a `verilator` executable to use that one; otherwise
`verilator` is looked up on `PATH`. Throws an error explaining how to
install Verilator if none is found.
"""
function verilator_cmd()
    override = get(ENV, "VERIJUL_VERILATOR", "")
    if !isempty(override)
        (isfile(override) || Sys.which(override) !== nothing) ||
            error("VERIJUL_VERILATOR is set to `$override`, but no such executable exists")
        return `$override`
    end
    Sys.which("verilator") === nothing &&
        error("Verilator was not found on PATH. Install it (e.g. `apt install verilator` or ",
              "`brew install verilator`), or set VERIJUL_VERILATOR to the path of a `verilator` executable.")
    return `verilator`
end

"""
    verilator_version() -> VersionNumber

Returns the version of the Verilator that [`verilator_cmd`](@ref VeriJul.Builder.verilator_cmd)
finds, or throws an error explaining how to install it.
"""
function verilator_version()
    out = read(`$(verilator_cmd()) --version`, String)
    m = match(r"Verilator\s+(\d+)\.(\d+)", out)
    m === nothing && error("Could not parse Verilator version from: $(repr(out))")
    return VersionNumber(parse(Int, m[1]), parse(Int, m[2]))
end

function check_verilator()
    v = verilator_version()
    v < MIN_VERILATOR && error("VeriJul needs Verilator ≥ $MIN_VERILATOR, found $v")
    return v
end

# C++ storage type Verilator uses for a port (CData/SData/IData/QData), or
# `nothing` for VlWide ports, which are passed as arrays of 32-bit words.
function ctype(width::Int)
    width <= 8  && return "uint8_t"
    width <= 16 && return "uint16_t"
    width <= 32 && return "uint32_t"
    width <= 64 && return "uint64_t"
    return nothing
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
Every port gets a getter; input ports also get a setter.
"""
function generate_bindings(ports::Vector{HardwarePort}, module_name::String)
    V = "V$(module_name)"

    cpp_code = """
    #include <cstdint>
    #include <cstring>
    #include <verilated.h>
    #include "verilated_vcd_c.h"
    #include "$V.h"

    // Verilator's runtime may call sc_time_stamp() when a context's time is
    // zero. It must be defined by the program (macOS refuses to link without
    // it); real time lives in each model's own VerilatedContext.
    double sc_time_stamp() { return 0; }

    // Each model gets its own context, so models of the same design (or a
    // library that the OS keeps loaded after dlclose) never share time.
    struct Handle {
        VerilatedContext* ctx;
        $V* top;
        VerilatedVcdC* tfp;
    };

    extern "C" {
        Handle* top_create() {
            VerilatedContext* ctx = new VerilatedContext;
            ctx->traceEverOn(true);
            return new Handle{ctx, new $V(ctx, "TOP"), nullptr};
        }

        void top_enable_trace(Handle* h, const char* filename) {
            if (h->tfp) return;
            h->tfp = new VerilatedVcdC;
            h->top->trace(h->tfp, 99);
            h->tfp->open(filename);
        }

        void top_eval(Handle* h, uint64_t time) {
            h->ctx->time(time);
            h->top->eval();
            if (h->tfp) h->tfp->dump(time);
        }

        // Evaluate without writing a waveform sample
        void top_settle(Handle* h) { h->top->eval(); }

        void top_destroy(Handle* h) {
            h->top->final();
            if (h->tfp) { h->tfp->close(); delete h->tfp; }
            delete h->top;
            delete h->ctx;
            delete h;
        }
    """

    jl_code = """
    # Generated by VeriJul. Prefer `load_dut`, which needs no generated module.
    module AutoBindings
    using VeriJul.Interop
    using Libdl

    enable_trace!(model::VerilatedModel, filename::AbstractString) =
        Interop.enable_trace!(model, filename)
    """

    for port in ports
        n, w = port.name, port.width
        t = ctype(w)
        if t === nothing
            # VlWide (Verilator 5) and WData[] (Verilator 4) are both plain word arrays
            cpp_code *= "    void get_$n(Handle* h, uint32_t* out) { std::memcpy(out, &h->top->$n, sizeof(h->top->$n)); }\n"
            port.direction == :in &&
                (cpp_code *= "    void set_$n(Handle* h, const uint32_t* in) { std::memcpy(&h->top->$n, in, sizeof(h->top->$n)); }\n")
        else
            cpp_code *= "    $t get_$n(Handle* h) { return h->top->$n; }\n"
            port.direction == :in &&
                (cpp_code *= "    void set_$n(Handle* h, $t val) { h->top->$n = val; }\n")
        end

        jl_code *= "get_$n(model::VerilatedModel) = Interop.read_port(Libdl.dlsym(model.lib_handle, :get_$n), model, $w)\n"
        port.direction == :in &&
            (jl_code *= "set_$(n)!(model::VerilatedModel, val::Integer) = Interop.write_port(Libdl.dlsym(model.lib_handle, :set_$n), model, $w, val)\n")
    end

    cpp_code *= "}\n"
    jl_code *= "end\n"

    return cpp_code, jl_code
end

# The C++ compiler command, e.g. `g++` or `ccache g++` (from the CXX variable).
function cxx_cmd()
    cxx = get(ENV, "CXX", Sys.isapple() ? "c++" : "g++")
    words = split(cxx)
    (isempty(words) || Sys.which(words[1]) === nothing) &&
        error("C++ compiler `$cxx` not found. Verilator turns the design into C++, so a C++17 ",
              "compiler is needed: install g++ or clang, or set CXX to the compiler's path.")
    return Cmd(String.(words))
end

# Marks a directory as created by VeriJul, so it may be emptied on rebuild.
const BUILD_MARKER = ".verijul-build"
# Lock file held for the whole build, so parallel Julia processes don't clash.
const BUILD_LOCK = ".verijul-lock"
# Written last by a successful build: the build key and the library's file name.
const BUILD_RECORD = "build-record.txt"

# Make sure `dir` exists and is VeriJul's, without ever deleting files VeriJul
# didn't create: a non-empty directory must already have the marker.
function claim_build_dir(dir::AbstractString)
    if isdir(dir) && !isempty(readdir(dir))
        isfile(joinpath(dir, BUILD_MARKER)) ||
            error("Refusing to use `$dir` as a build directory: it is not empty and was not ",
                  "created by VeriJul. Pass an empty or new directory as `build_dir`, or omit ",
                  "`build_dir` to use VeriJul's build cache.")
    end
    mkpath(dir)
    marker = joinpath(dir, BUILD_MARKER)
    isfile(marker) ||
        write(marker, "Created by VeriJul.jl. This directory may be deleted and rebuilt at any time.\n")
    return dir
end

# Delete everything VeriJul put in a claimed directory, except the marker and lock.
function clear_build_dir(dir::AbstractString)
    for f in readdir(dir)
        f in (BUILD_MARKER, BUILD_LOCK) && continue
        rm(joinpath(dir, f); recursive=true, force=true)
    end
    return dir
end

prepare_build_dir(dir::AbstractString) = clear_build_dir(claim_build_dir(dir))

# A finished build for `key` in `dir`, or nothing.
function cached_build(dir::AbstractString, key::AbstractString)
    record = joinpath(dir, BUILD_RECORD)
    isfile(record) || return nothing
    lines = readlines(record)
    (length(lines) >= 2 && lines[1] == key) || return nothing
    lib, bindings = joinpath(dir, lines[2]), joinpath(dir, "bindings.jl")
    return isfile(lib) && isfile(bindings) ? (lib, bindings) : nothing
end

build_cache() = get_scratch!(Base.moduleroot(@__MODULE__), "builds")

"""
    clear_build_cache()

Deletes all cached builds in VeriJul's default build location (used when
`build_dir` is not given). Designs that are still loaded keep working.
"""
clear_build_cache() = (rm(build_cache(); recursive=true, force=true); nothing)

# Everything that affects the build output, so unchanged designs are not rebuilt.
function build_key(sources, top, include_dirs, defines, parameters, verilator_args, vver, cxx)
    h = hash((WRAPPER_VERSION, string(vver), top, cxx, verilator_args))
    for f in sources
        h = hash((f, read(f)), h)
    end
    for dir in include_dirs, (root, _, files) in walkdir(dir), f in sort(files)
        path = joinpath(root, f)
        h = hash((path, read(path)), h)
    end
    h = hash(sort!([string(k) => string(something(v, "")) for (k, v) in defines]), h)
    h = hash(sort!([string(k) => string(v) for (k, v) in parameters]), h)
    return string(h, base=16, pad=16)
end

"""
    build_dut(sources, top_module; kwargs...) -> (lib_path, bindings_path)

Verilates `sources` (one path or a vector of paths) with `top_module` as the
top, generates bindings and compiles everything into a shared library.
Returns the library path and the path of the generated `bindings.jl`.

Most code should call [`load_dut`](@ref VeriJul.Device.load_dut), which builds
and loads in one step and takes the same keywords.

# Keywords
- `build_dir`: where build files go. By default each design and set of options
  gets its own folder in VeriJul's build cache (a Scratch.jl space, removed
  with [`clear_build_cache`](@ref VeriJul.Builder.clear_build_cache) or when
  VeriJul is uninstalled). A directory you pass must be empty, new, or one
  VeriJul created earlier; VeriJul never deletes files it didn't create.
- `include_dirs=String[]`: directories searched by `` `include `` (`-I`).
- `defines=Dict()`: preprocessor macros, e.g. `Dict("DEPTH" => 16, "FAST" => nothing)`
  (`+define+`).
- `parameters=Dict()`: top-level parameter overrides, e.g. `Dict("WIDTH" => 12)` (`-G`).
  Values are passed to Verilator as written, so string parameters need
  their own quotes: `"\\"name\\""`.
- `verilator_args=String[]`: extra command-line arguments for Verilator.
- `force=false`: rebuild even if nothing changed.
- `verbose=false`: show Verilator and compiler output.

Builds are cached: if the sources, files in `include_dirs`, options,
Verilator version and compiler are unchanged, the existing library is reused.
To rebuild, VeriJul empties the build directory first.
Files pulled in by `` `include `` from outside `include_dirs` are not tracked;
pass `force=true` after changing them.

Set the `CXX` environment variable to choose the C++ compiler (default `g++`,
or `c++` on macOS; `CXX="ccache g++"` also works). Set `VERIJUL_VERILATOR` to
choose the Verilator executable (see [`verilator_cmd`](@ref VeriJul.Builder.verilator_cmd)).
"""
function build_dut(sources::Union{AbstractString,AbstractVector{<:AbstractString}}, top_module::AbstractString;
                   build_dir::Union{AbstractString,Nothing}=nothing,
                   include_dirs::AbstractVector{<:AbstractString}=String[],
                   defines::AbstractDict=Dict{String,Any}(),
                   parameters::AbstractDict=Dict{String,Any}(),
                   verilator_args::AbstractVector{<:AbstractString}=String[],
                   force::Bool=false, verbose::Bool=false)
    top_module = String(top_module)
    srcs = [abspath(s) for s in (sources isa AbstractString ? [sources] : sources)]
    isempty(srcs) && error("No Verilog sources given")
    for s in srcs
        isfile(s) || error("Verilog source not found: $s")
    end
    incs = [abspath(d) for d in include_dirs]
    for d in incs
        isdir(d) || error("Include directory not found: $d")
    end
    vver = check_verilator()
    verilator = verilator_cmd()
    cxx = cxx_cmd()
    args = String.(verilator_args)

    key = build_key(srcs, top_module, incs, defines, parameters, args, vver, string(cxx))
    build_dir = build_dir === nothing ? joinpath(build_cache(), "$(top_module)_$(key)") : abspath(build_dir)

    claim_build_dir(build_dir)
    # Hold a lock for the whole check-and-build, so another Julia process
    # building the same design waits and then reuses the result.
    return mkpidlock(joinpath(build_dir, BUILD_LOCK); stale_age=600) do
        if !force
            cached = cached_build(build_dir, key)
            if cached !== nothing
                verbose && @info "Design unchanged, reusing $(cached[1])"
                return cached
            end
        end
        clear_build_dir(build_dir)
        compile_design(build_dir, key, srcs, top_module, incs, defines, parameters, args,
                       verilator, cxx, vver, verbose)
    end
end

function compile_design(build_dir, key, srcs, top_module, incs, defines, parameters, args,
                        verilator, cxx, vver, verbose)
    # Every build gets a new library name: dlopen returns an already-loaded
    # library for a path it has seen, so reusing a path could run old code.
    lib_name = "libV$(top_module)_$(key[1:12])_$(string(time_ns(), base=36)).$(Libdl.dlext)"
    output_lib = joinpath(build_dir, lib_name)
    jl_binding_path = joinpath(build_dir, "bindings.jl")

    # Show tool output only when asked, but always surface it if a step fails
    function sh(cmd)
        verbose && return run(cmd)
        log = IOBuffer()
        proc = run(pipeline(ignorestatus(cmd); stdout=log, stderr=log))
        success(proc) || error("Command failed: $cmd\n", String(take!(log)))
        return proc
    end

    flags = String[]
    append!(flags, ["-I$d" for d in incs])
    for (k, v) in defines
        push!(flags, v === nothing ? "+define+$k" : "+define+$k=$v")
    end
    append!(flags, ["-G$k=$v" for (k, v) in parameters])
    append!(flags, args)

    verbose && @info "Running Verilator $vver"
    sh(`$verilator -Wno-fatal --trace --cc $srcs --top-module $top_module -Mdir $build_dir $flags`)

    verbose && @info "Generating bindings"
    ports = extract_ports(joinpath(build_dir, "V$(top_module).h"))
    cpp_code, jl_code = generate_bindings(ports, top_module)

    wrapper_path = joinpath(build_dir, "wrapper.cpp")
    write(wrapper_path, cpp_code)

    verilator_root = strip(read(`$verilator --getenv VERILATOR_ROOT`, String))
    inc_dir = joinpath(verilator_root, "include")

    generated_cpps = filter(f -> startswith(f, "V$(top_module)") && endswith(f, ".cpp"), readdir(build_dir))
    core_files = [joinpath(inc_dir, "verilated.cpp")]
    for extra in ("verilated_threads.cpp", "verilated_vcd_c.cpp")
        f = joinpath(inc_dir, extra)
        isfile(f) && push!(core_files, f)
    end
    cpp_files = [wrapper_path, joinpath.(build_dir, generated_cpps)..., core_files...]

    verbose && @info "Compiling shared library with $cxx"
    sh(`$cxx -std=c++17 -O2 -fPIC -shared -pthread -I$inc_dir -I$(joinpath(inc_dir, "vltstd")) -I$build_dir $cpp_files -o $output_lib`)

    write(jl_binding_path, jl_code)
    # Written last: marks the build as complete and usable
    write(joinpath(build_dir, BUILD_RECORD), key, "\n", lib_name, "\n")

    verbose && @info "Build complete" output_lib
    return output_lib, jl_binding_path
end

end
