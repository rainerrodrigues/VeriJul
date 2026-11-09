# Integration test for load_dut / DUT / multi-clock simulation on real Verilator builds.

examples = joinpath(dirname(@__DIR__), "examples")
counter_srcs = [joinpath(examples, "counter", "counter.v"), joinpath(examples, "counter", "inverter.v")]
counter_inc = [joinpath(examples, "counter", "include")]
build_root = mktempdir()

@testset "Build options and caching" begin
    dir = joinpath(build_root, "counter")
    dut = load_dut(counter_srcs, "counter"; build_dir=dir, include_dirs=counter_inc)
    lib = getfield(dut, :lib_path)
    mtime1 = mtime(lib)

    # Unchanged design: no rebuild
    lib2, _ = build_dut(counter_srcs, "counter"; build_dir=dir, include_dirs=counter_inc)
    @test lib2 == lib && mtime(lib2) == mtime1

    # force=true rebuilds under the same key
    lib3, _ = build_dut(counter_srcs, "counter"; build_dir=dir, include_dirs=counter_inc, force=true)
    @test lib3 == lib && isfile(lib3)

    # Parameters and defines change the build
    dut12 = load_dut(counter_srcs, "counter"; build_dir=joinpath(build_root, "counter12"),
                     include_dirs=counter_inc, parameters=Dict("WIDTH" => 12),
                     defines=Dict("INIT_VAL" => "8'd42"))
    @test Dict(p.name => p.width for p in ports(dut12))["count"] == 12
    settle!(dut); settle!(dut12)
    @test dut.init_val == 7
    @test dut12.init_val == 42

    @test_throws ErrorException build_dut(counter_srcs, "counter"; build_dir=dir)  # missing include dir
    destroy!(dut12)
    destroy!(dut)
end

@testset "Ports, clocks, reset and waveforms" begin
    dut = load_dut(counter_srcs, "counter"; build_dir=joinpath(build_root, "counter"),
                   include_dirs=counter_inc)
    vcd = joinpath(build_root, "counter.vcd")
    enable_trace!(dut, vcd)

    sim = Simulator(dut)
    add_clock!(sim, :clk_slow; half_period=15)
    start_clock!(sim)
    reset!(sim)
    @test dut.count == 0 && dut.slow_count == 0

    dut.step = 3
    @tick sim 4
    @test dut.count == 12

    before = dut.slow_count
    @tick sim 3 clock=:clk_slow
    @test dut.slow_count == before + 3

    x = big(2)^99 + big(2)^70 + 0xabcdef
    dut.wide_in = x
    @tick sim
    @test dut.wide_in == x
    @test dut.wide_out == (big(2)^100 - 1) ⊻ x
    @test dut.upper === UInt64(x >> 36)

    @test_throws ErrorException dut.count = 1
    stop_clock!(sim)
    destroy!(dut)
    @test filesize(vcd) > 0
end

@testset "Two designs at once" begin
    filt = load_dut(joinpath(examples, "filter.v"), "filter"; build_dir=joinpath(build_root, "filter"))
    cnt = load_dut(counter_srcs, "counter"; build_dir=joinpath(build_root, "counter"),
                   include_dirs=counter_inc)
    fsim, csim = Simulator(filt), Simulator(cnt)
    start_clock!(fsim); start_clock!(csim)
    reset!(csim)
    filt.in_data = 0xFF
    cnt.step = 1
    @tick fsim 6
    @tick csim 2
    @test filt.out_data == 0xFF
    @test cnt.count >= 2
    stop_clock!(fsim); stop_clock!(csim)
    destroy!(filt); destroy!(cnt)
end

@testset "Reloading and duplicate models" begin
    # Each model has its own context, so a second model of the same design can
    # be created while the first is mid-simulation (and after it is destroyed,
    # even where the OS keeps the library loaded).
    args = (counter_srcs, "counter")
    kw = (build_dir=joinpath(build_root, "counter"), include_dirs=counter_inc)
    a = load_dut(args...; kw...)
    asim = Simulator(a); start_clock!(asim); reset!(asim)
    a.step = 1
    @tick asim 3
    stop_clock!(asim)
    @test a.count == 3 && asim.time > 0

    # Created while `a` is alive at a non-zero time
    b = load_dut(args...; kw...)
    bsim = Simulator(b); start_clock!(bsim); reset!(bsim)
    b.step = 2
    @tick bsim 2
    stop_clock!(bsim)
    @test b.count == 4
    @test a.count == 3                              # independent state
    destroy!(a); destroy!(b)

    c = load_dut(args...; kw...)
    @test c.count isa UInt8
    destroy!(c)
end
