using Test
using Aqua
using VeriJul
using VeriJul.Builder: extract_ports, generate_bindings, verilator_version, verilator_cmd,
                       prepare_build_dir, claim_build_dir, clear_build_dir, cached_build,
                       cxx_cmd, build_cache, clear_build_cache, BUILD_MARKER, BUILD_LOCK, BUILD_RECORD
using VeriJul.Interop: words_to_int, int_to_words

include("mock.jl")

have_toolchain() = (try verilator_cmd(); cxx_cmd(); true catch; false end)

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

    @testset "Build directories never delete user files" begin
        root = mktempdir()
        new = joinpath(root, "new", "nested")
        prepare_build_dir(new)
        @test isfile(joinpath(new, BUILD_MARKER))

        empty_dir = mkpath(joinpath(root, "empty"))
        prepare_build_dir(empty_dir)
        @test isfile(joinpath(empty_dir, BUILD_MARKER))

        users = mkpath(joinpath(root, "users"))
        write(joinpath(users, "notes.txt"), "keep me")
        err = try prepare_build_dir(users); nothing catch e; e end
        @test err isa ErrorException && occursin("Refusing", err.msg)
        @test read(joinpath(users, "notes.txt"), String) == "keep me"

        # A directory VeriJul created is emptied and reused
        write(joinpath(new, "old_build.o"), "stale")
        prepare_build_dir(new)
        @test readdir(new) == [BUILD_MARKER]

        # Clearing keeps the marker and the lock file
        write(joinpath(new, BUILD_LOCK), "")
        write(joinpath(new, "lib.so"), "x")
        clear_build_dir(new)
        @test sort(readdir(new)) == sort([BUILD_MARKER, BUILD_LOCK])

        # Only a complete build for the same key counts as cached
        @test cached_build(new, "abc") === nothing
        write(joinpath(new, "libVx_1.so"), "x"); write(joinpath(new, "bindings.jl"), "")
        write(joinpath(new, BUILD_RECORD), "abc\nlibVx_1.so\n")
        @test cached_build(new, "abc") == (joinpath(new, "libVx_1.so"), joinpath(new, "bindings.jl"))
        @test cached_build(new, "other") === nothing
        rm(joinpath(new, "libVx_1.so"))
        @test cached_build(new, "abc") === nothing

        @test isdir(build_cache())
        @test startswith(build_cache(), first(DEPOT_PATH))
    end

    @testset "Toolchain lookup" begin
        withenv("VERIJUL_VERILATOR" => "/no/such/verilator") do
            err = try verilator_cmd(); nothing catch e; e end
            @test err isa ErrorException && occursin("VERIJUL_VERILATOR", err.msg)
        end
        withenv("VERIJUL_VERILATOR" => nothing, "PATH" => "") do
            err = try verilator_cmd(); nothing catch e; e end
            @test err isa ErrorException && occursin("apt install verilator", err.msg)
        end
        withenv("CXX" => "no-such-compiler-xyz") do
            err = try cxx_cmd(); nothing catch e; e end
            @test err isa ErrorException && occursin("C++17", err.msg)
        end
        sh = Sys.which("sh")
        withenv("CXX" => "$sh -c") do
            @test cxx_cmd() == `$sh -c`        # multi-word CXX, e.g. "ccache g++"
        end
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
        @test sim.clk_val == 0x00                                # lower-level API field
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

    @testset "Clock and reset inputs must be 1 bit (mock design)" begin
        dut = MockDesign.make_dut()
        sim = Simulator(dut)
        err = try add_clock!(sim, :wide_in); nothing catch e; e end
        @test err isa ErrorException && occursin("100 bits wide", err.msg)
        @test_throws ErrorException add_clock!(sim, :step)          # 8 bits
        @test_throws ErrorException Simulator(dut; clock=:step)
        start_clock!(sim)
        @test_throws ErrorException reset!(sim, :wide_in)
        @test_throws ErrorException reset!(sim, :step)
        stop_clock!(sim)
    end

    @testset "Adding a clock later never rewinds time (mock design)" begin
        dut = MockDesign.make_dut()
        sim = Simulator(dut)
        start_clock!(sim)
        @tick sim 5
        stop_clock!(sim)
        t_stop = sim.time
        @test t_stop > 0
        @test_throws ArgumentError add_clock!(sim, :clk_slow; phase=-1)
        add_clock!(sim, :clk_slow; half_period=7)
        start_clock!(sim)
        times = Int[]
        for _ in 1:6
            @tick sim edge=:rising clock=:clk_slow
            push!(times, sim.time)
        end
        stop_clock!(sim)
        @test first(times) > t_stop
        @test issorted(times) && allunique(times)
        @test all(diff(times) .== 14)                # rising edges one period apart
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
        @testset "Hardware: lower-level API (filter.v)" begin
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
