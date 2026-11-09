using Test
using Aqua
using VeriJul
using VeriJul.Builder: HardwarePort, extract_ports, generate_bindings, verilator_version

@testset "VeriJul.jl" begin
    @testset "Port extraction" begin
        ports = extract_ports(joinpath(@__DIR__, "fixtures", "Vports.h"))
        @test ports == [
            HardwarePort("clk", :in, 1),
            HardwarePort("in_data", :in, 8),
            HardwarePort("word", :in, 16),
            HardwarePort("bus", :in, 4),
            HardwarePort("wide", :out, 41),
            HardwarePort("out_data", :out, 8),   # pre-4.200 style without `&`
            HardwarePort("huge", :out, 100),
        ]
        empty_header = tempname()
        write(empty_header, "class Vnothing {};")
        @test_throws ErrorException extract_ports(empty_header)
    end

    @testset "Binding generation" begin
        ports = [HardwarePort("clk", :in, 1), HardwarePort("word", :in, 16),
                 HardwarePort("wide", :out, 41)]
        cpp, jl = generate_bindings(ports, "dut")
        @test occursin("#include \"Vdut.h\"", cpp)
        @test occursin("void set_word(Handle* h, uint16_t val)", cpp)
        @test occursin("uint64_t get_wide(Handle* h)", cpp)
        @test occursin("void top_destroy(Handle* h)", cpp)
        @test occursin("double sc_time_stamp()", cpp)
        # Generated Julia must parse and mask narrow inputs
        @test Meta.parse(jl) isa Expr
        @test occursin("(val % UInt8) & 0x1", jl)
        @test occursin("(val % UInt16))", jl)
        @test_throws ErrorException generate_bindings([HardwarePort("x", :in, 65)], "dut")
    end

    @testset "@testbench macro" begin
        ex = @macroexpand @testbench function my_tb(sim) end
        @test occursin("launch_my_tb", string(ex))
        @test_throws Exception @eval @testbench 42
    end

    @testset "Aqua quality checks" begin
        Aqua.test_all(VeriJul)
    end

    if Sys.which("verilator") !== nothing && Sys.which(get(ENV, "CXX", Sys.isapple() ? "c++" : "g++")) !== nothing
        @testset "Hardware integration (filter.v)" begin
            @test verilator_version() >= v"4.200"
            include("test_run.jl")
        end
    else
        @warn "verilator or a C++ compiler not found; skipping hardware integration tests"
    end
end
