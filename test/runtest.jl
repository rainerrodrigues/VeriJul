using Test
using VeriJul

@testset "VeriJul.jl Integration Tests" begin
    println("--- Running CI Hardware Tests ---")
    
    # Running the exact script we just built
    include("test_run.jl")
    
    # If the script finishes without crashing, the test passes!
    @test true 
end
