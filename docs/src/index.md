```@meta
CurrentModule = VeriJul
```

# VeriJul.jl

VeriJul lets you write hardware testbenches in Julia. It compiles a Verilog
design with [Verilator](https://www.veripool.org/verilator/), gives you its
ports as ordinary Julia properties, and drives the simulation from Julia
tasks, so you can check hardware against reference models, random stimulus
and everything else in the Julia ecosystem.

```julia
using VeriJul

dut = load_dut("filter.v", "filter")      # build (cached) and load
sim = Simulator(dut)                      # drives the `clk` input
start_clock!(sim)

dut.in_data = 0xFF
@tick sim 6                               # wait for 6 rising edges
dut.out_data                              # 0xff
```

## Features

- **One-call builds** with build caching, multiple source files, include
  directories, `` `define``s and parameter overrides.
- **Named port access**: `dut.port = value` and `dut.port`, for any width,
  including ports wider than 64 bits (as `BigInt`).
- **Clocks and time**: multiple clocks with their own periods and phases,
  `@tick sim n`, reset helpers, and timeouts so a stuck testbench fails
  instead of hanging.
- **Waveforms**: VCD tracing you can open in GTKWave or Surfer.

## Requirements

- Julia 1.10 or newer
- Verilator 4.200 or newer on your `PATH`
- A C++17 compiler (`g++` or `clang++`; set `CXX` to pick one)

VeriJul is tested on Linux and macOS. Windows is not supported yet.

```bash
# Ubuntu / Debian
sudo apt-get install verilator g++
# macOS
brew install verilator
```

## Installation

```julia
using Pkg
Pkg.add("VeriJul")
```

## Where to go next

1. [Getting started](@ref) walks through building, driving and tracing a
   small filter.
2. [Self-checking testbenches](@ref) shows how to compare a design against
   a Julia reference model with `Test`.
3. [Build options and multiple clocks](@ref) covers multi-file designs,
   parameters, defines and clock domains.
4. [Ports and wide signals](@ref) explains port types, truncation and ports
   wider than 64 bits.

Upgrading from VeriJul 0.1? See [Migrating from 0.1](@ref).
