```@meta
CurrentModule = VeriJul
```

# Ports and wide signals

Every top-level port of a [`DUT`](@ref) is a property. Inputs can be read and
written; outputs can only be read.

## Types

Reads return the smallest unsigned type that holds the port, which is also
how Verilator stores it:

| Port width | Julia type |
|---|---|
| 1–8 bits | `UInt8` |
| 9–16 bits | `UInt16` |
| 17–32 bits | `UInt32` |
| 33–64 bits | `UInt64` |
| over 64 bits | `BigInt` |

```@example ports
using VeriJul

dir = joinpath(pkgdir(VeriJul), "examples", "counter")
dut = load_dut([joinpath(dir, "counter.v"), joinpath(dir, "inverter.v")], "counter";
               include_dirs=[joinpath(dir, "include")], build_dir=mktempdir())
settle!(dut)
(typeof(dut.step), typeof(dut.slow_count), typeof(dut.upper), typeof(dut.wide_out))
```

## Writing values

Writes accept any `Integer`, including `Bool`, and are truncated to the port
width like a Verilog assignment. Negative numbers are stored as two's
complement:

```@example ports
dut.step = 300          # 8-bit port: 300 & 0xff
a = dut.step
dut.step = -1
b = dut.step
dut.step = true
c = dut.step
(a, b, c)
```

Writing an output, an unknown port or a non-integer is an error:

```@example ports
try
    dut.count = 1
catch err
    err
end
```

## Ports wider than 64 bits

Wide ports read back as `BigInt` and accept any integer. `wide_out` is the
bitwise inverse of the 100-bit `wide_in`, and `upper` is its top 64 bits:

```@example ports
x = big(2)^99 + big(2)^64 + 0xCAFE
dut.wide_in = x
settle!(dut)
(wide_out = string(dut.wide_out, base=16),
 expected = string((big(2)^100 - 1) ⊻ x, base=16),
 upper = dut.upper)
```

Under the hood a wide port is an array of 32-bit words, lowest word first.
Bit `i` of the value is bit `i` of the port.

## Setting inputs and reading outputs in time

Setting an input doesn't evaluate the design. The new value takes effect at
the next clock edge (when the simulator evaluates the model) or when you call
[`settle!`](@ref). Reading an output right after [`@tick`](@ref) returns gives
its value just after that edge.

```@example ports
destroy!(dut) # hide
nothing # hide
```

## Lower-level access

[`build_dut`](@ref) returns the library path and a generated `bindings.jl`
with one function per port (`set_<port>!`, `get_<port>`) operating on a
[`VerilatedModel`](@ref). See [Lower-level API](@ref).
