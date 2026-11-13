module Device

using Libdl
using ..Interop
using ..Interop: VerilatedModel, read_port, write_port
using ..Builder: Builder, HardwarePort, build_dut, extract_ports

export DUT, load_dut, ports

struct PortHandle
    port::HardwarePort
    get_ptr::Ptr{Cvoid}
    set_ptr::Ptr{Cvoid}   # C_NULL for outputs
end

"""
    DUT

A loaded hardware design. Read and write its ports as properties:

```julia
dut.in_data = 0x42      # set an input (truncated to the port width)
dut.out_data            # read an output (or an input)
```

Ports up to 64 bits read back as `UInt8`/`UInt16`/`UInt32`/`UInt64`; wider
ports read back as `BigInt` and accept any `Integer`.

Create one with [`load_dut`](@ref VeriJul.Device.load_dut). List its ports
with [`ports`](@ref VeriJul.Device.ports).
"""
struct DUT
    model::VerilatedModel
    top::String
    lib_path::String
    handles::Dict{Symbol,PortHandle}
    order::Vector{Symbol}
end

function DUT(lib_path::AbstractString, top::AbstractString, port_list::Vector{HardwarePort})
    model = VerilatedModel(lib_path)
    handles = Dict{Symbol,PortHandle}()
    for p in port_list
        get_ptr = Libdl.dlsym(model.lib_handle, Symbol("get_", p.name); throw_error=false)
        get_ptr === nothing && error("Library $lib_path has no getter for port `$(p.name)`. ",
                                     "It was probably built by an older VeriJul; rebuild with force=true.")
        set_ptr = p.direction == :in ? Libdl.dlsym(model.lib_handle, Symbol("set_", p.name)) : C_NULL
        handles[Symbol(p.name)] = PortHandle(p, get_ptr, set_ptr)
    end
    return DUT(model, String(top), String(lib_path), handles, [Symbol(p.name) for p in port_list])
end

"""
    load_dut(sources, top_module; kwargs...) -> DUT

Builds the design (or reuses a cached build) and loads it. Takes the same
keywords as [`build_dut`](@ref VeriJul.Builder.build_dut): `build_dir`,
`include_dirs`, `defines`, `parameters`, `verilator_args`, `force`, `verbose`.

```julia
dut = load_dut("filter.v", "filter")
dut.in_data = 0xFF
```

By default the build goes into VeriJul's build cache, one folder per design
and set of options, so nothing is written to the current directory.
"""
function load_dut(sources, top_module::AbstractString;
                  build_dir::Union{AbstractString,Nothing}=nothing, kwargs...)
    lib, _ = build_dut(sources, top_module; build_dir=build_dir, kwargs...)
    header = joinpath(dirname(lib), "V$(top_module).h")
    return DUT(lib, top_module, extract_ports(header))
end

handle(d::DUT, name::Symbol) =
    get(getfield(d, :handles), name) do
        error("Design `$(getfield(d, :top))` has no port named `$name`. Ports: ",
              join(getfield(d, :order), ", "))
    end

function Base.getproperty(d::DUT, name::Symbol)
    h = handle(d, name)
    return read_port(h.get_ptr, getfield(d, :model), h.port.width)
end

function Base.setproperty!(d::DUT, name::Symbol, val::Integer)
    h = handle(d, name)
    h.port.direction == :in || error("Port `$name` is an output and cannot be written")
    write_port(h.set_ptr, getfield(d, :model), h.port.width, val)
    return val
end

Base.setproperty!(d::DUT, name::Symbol, val) =
    throw(ArgumentError("Port values must be integers (or Bool), got $(typeof(val))"))

Base.propertynames(d::DUT, private::Bool=false) = Tuple(getfield(d, :order))

"""
    ports(dut) -> Vector{HardwarePort}

The design's top-level ports, in declaration order.
"""
ports(d::DUT) = [getfield(d, :handles)[n].port for n in getfield(d, :order)]

# The underlying VerilatedModel
model(d::DUT) = getfield(d, :model)

Interop.settle!(d::DUT) = (Interop.settle!(model(d)); d)
Interop.enable_trace!(d::DUT, filename::AbstractString) = (Interop.enable_trace!(model(d), filename); d)
Interop.destroy!(d::DUT) = Interop.destroy!(model(d))

function Base.show(io::IO, d::DUT)
    alive = model(d).ptr != C_NULL
    print(io, "DUT(", getfield(d, :top), ", ", length(getfield(d, :order)), " ports",
          alive ? "" : ", destroyed", ")")
end

function Base.show(io::IO, ::MIME"text/plain", d::DUT)
    show(io, d)
    for p in ports(d)
        print(io, "\n  ", rpad(p.direction == :in ? "input" : "output", 7), " ",
              rpad(p.name, 16), " ", p.width, p.width == 1 ? " bit" : " bits")
    end
end

end
