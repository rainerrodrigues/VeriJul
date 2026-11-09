using Test
using Aqua
using VeriJul
using VeriJul.Builder: extract_ports, generate_bindings, verilator_version
using VeriJul.Interop: words_to_int, int_to_words

include("mock.jl")

have_toolchain() = Sys.which("verilator") !== nothing &&
                   Sys.which(get(ENV, "CXX", Sys.isapple() ? "c++" : "g++")) !== nothing

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
                 HardwarePort("wide", :out, 41), HardwarePort("huge", :in, 100)]
        cpp, jl = generate_bindings(ports, "dut")
        @test occursin("#include \"Vdut.h\"", cpp)
        @test occursin("void set_word(Handle* h, uint16_t val)", cpp)
        @test occursin("uint16_t get_word(Handle* h)", cpp)          # inputs are readable too
        @test occursin("uint64_t get_wide(Handle* h)", cpp)
        @test !occursin("set_wide", cpp)                             # outputs have no setter
        @test occursin("void set_huge(Handle* h, const uint32_t* in)", cpp)
        @test occursin("void get_huge(Handle* h, uint32_t* out)", cpp)
        @test occursin("void top_settle(Handle* h)", cpp)
        @test occursin("double sc_time_stamp()", cpp)
        @test occursin("new VerilatedContext", cpp)          # one context per model
        @test Meta.parse(jl) isa Expr
        @test occursin("set_huge!(model::VerilatedModel, val::Integer)", jl)
    end

    @testset "Wide value conversion" begin
        x = big(2)^99 + big(2)^64 + 0xdeadbeef
        @test int_to_words(x, 100) == UInt32[0xdeadbeef, 0, 1, 0x8]
        @test words_to_int(int_to_words(x, 100)) == x
        @test words_to_int(int_to_words(-1, 100)) == big(2)^100 - 1   # two's complement
        @test words_to_int(int_to_words(big(2)^100, 100)) == 0       # truncated
    end

    @testset "Macros" begin
        ex = @macroexpand @testbench function my_tb(sim) end
        @test occursin("launch_my_tb", string(ex))
        @test_throws Exception @eval @testbench 42
        @test occursin("tick", string(@macroexpand @tick sim 3 clock=:b))
        @test_throws Exception @eval @macroexpand @tick sim clock=:b 3
    end

    @testset "DUT port access (mock design)" begin
        dut = MockDesign.make_dut()
        @test propertynames(dut) == (:clk, :clk_slow, :rst, :step, :wide_in, :wide_out, :count, :slow_count)
        @test length(ports(dut)) == 8
        dut.step = 0x1ff                       # truncated to 8 bits
        @test dut.step === 0xff
        dut.step = -1
        @test dut.step === 0xff
        dut.step = true
        @test dut.step === 0x01
        x = big(2)^99 + 12345
        dut.wide_in = x
        @test dut.wide_in == x
        @test dut.wide_out == (big(2)^100 - 1) ⊻ x
        @test_throws ErrorException dut.count = 1        # output
        @test_throws ErrorException dut.nope             # unknown port
        @test_throws ArgumentError dut.step = 1.5
        @test occursin("DUT(mock, 8 ports)", sprint(show, dut))
        @test occursin("input   wide_in          100 bits", sprint(show, MIME"text/plain"(), dut))
    end

    @testset "Simulator (mock design)" begin
        dut = MockDesign.make_dut()
        sim = Simulator(dut)
        add_clock!(sim, :clk_slow; half_period=15)
        @test_throws ErrorException add_clock!(sim, :clk_slow)   # duplicate
        @test_throws ErrorException add_clock!(sim, :count)      # not an input
        @test_throws ClockStopped tick(sim)                      # not started

        start_clock!(sim)
        @test_throws ErrorException start_clock!(sim)

        reset!(sim)
        @test dut.rst == 0 && dut.count == 0 && dut.slow_count == 0

        dut.step = 3
        @tick sim 4
        @test dut.count == 12

        before = dut.slow_count
        @tick sim 3 clock=:clk_slow
        @test dut.slow_count == before + 3

        @tick sim edge=:falling
        @test sim.clk_val == 0x00                                # 0.1 compatibility field
        t0 = sim.time
        @tick sim
        @test sim.time > t0 && sim.time % 10 == 0                # rising edges at multiples of 10

        @test_throws TickTimeout tick(sim, 10^9; timeout=0.2)
        @tick sim                                                # still usable after a timeout

        # A waiting task gets ClockStopped instead of hanging
        waiter = @async try
            tick(sim, 10^9)
            :finished
        catch e
            e
        end
        yield()
        stop_clock!(sim)
        @test fetch(waiter) isa ClockStopped
        @test_throws ClockStopped tick(sim)

        # Clocks can be restarted
        start_clock!(sim, 2)
        @tick sim 2
        stop_clock!(sim)
        @test sim.clock_task === nothing
    end

    @testset "@testbench with a DUT (mock design)" begin
        dut = MockDesign.make_dut()
        sim = Simulator(dut)
        @testbench function count_to(sim)
            reset!(sim; cycles=1)
            sim.dut.step = 1
            @tick sim 5
            return sim.dut.count
        end
        start_clock!(sim)
        @test fetch(launch_count_to(sim)) == 5
        stop_clock!(sim)
    end

    @testset "Aqua quality checks" begin
        Aqua.test_all(VeriJul)
    end

    if have_toolchain()
        @testset "Hardware: VeriJul 0.1 API (filter.v)" begin
            @test verilator_version() >= v"4.200"
            include("test_run.jl")
        end
        @testset "Hardware: DUT API (counter)" begin
            include("test_dut.jl")
        end
    else
        @warn "verilator or a C++ compiler not found; skipping hardware integration tests"
    end
end
