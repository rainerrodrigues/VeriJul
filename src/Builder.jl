module Builder

using EzXML

export build_dut

# THE MISSING STRUCT
struct HardwarePort
    name::String
    direction::Symbol # :in or :out
    width::Int
end

function extract_ports(xml_path::String, top_module_name::String)
    doc = readxml(xml_path)
    
    # Use XPath to find all variables with a direction inside the top module
    xpath_query = "//netlist/module[@name='$top_module_name']/var[@dir]"
    xml_ports = findall(xpath_query, root(doc))
    
    ports = HardwarePort[]
    
    for p in xml_ports
        name = p["name"]
        
        # Robust check for Verilator 4 ("in") and Verilator 5 ("input")
        dir_attr = p["dir"]
        dir = startswith(dir_attr, "in") ? :in : :out
        
        # Calculate width (e.g., "[31:0]" -> 32 bits)
        width = haskey(p, "left") ? parse(Int, p["left"]) - parse(Int, p["right"]) + 1 : 1
        
        push!(ports, HardwarePort(name, dir, width))
    end
    
    return ports
end

function generate_bindings(ports::Vector{HardwarePort}, module_name::String)
    # Injecting the required C++ headers for VCD Tracing
    cpp_code = "#include <cstdint>\n"
    cpp_code *= "#include <verilated.h>\n"
    cpp_code *= "#include \"verilated_vcd_c.h\"\n"
    cpp_code *= "#include \"V$(module_name).h\"\n\n"
    
    # Global pointer for the tracer
    cpp_code *= "VerilatedVcdC* tfp = nullptr;\n\n"
    
    cpp_code *= "extern \"C\" {\n"
    cpp_code *= "    V$(module_name)* top_create() { return new V$(module_name)(); }\n"
    
    # Trace Initialization
    cpp_code *= "    void top_enable_trace(V$(module_name)* top, const char* filename) {\n"
    cpp_code *= "        Verilated::traceEverOn(true);\n"
    cpp_code *= "        tfp = new VerilatedVcdC;\n"
    cpp_code *= "        top->trace(tfp, 99);\n"
    cpp_code *= "        tfp->open(filename);\n"
    cpp_code *= "    }\n"
    
    # Eval now takes the Julia simulation time
    cpp_code *= "    void top_eval(V$(module_name)* top, uint64_t time) {\n"
    cpp_code *= "        top->eval();\n"
    cpp_code *= "        if (tfp) tfp->dump(time);\n"
    cpp_code *= "    }\n"
    
    # Safely close the trace file on exit
    cpp_code *= "    void top_destroy(V$(module_name)* top) {\n"
    cpp_code *= "        if (tfp) { tfp->close(); delete tfp; }\n"
    cpp_code *= "        delete top;\n"
    cpp_code *= "    }\n"
    
    jl_code = "module AutoBindings\nusing VeriJul.Interop\nusing Libdl\n" 
    
    # Julia Wrapper for the tracer
    jl_code *= """
    function enable_trace!(model::VerilatedModel, filename::String)
        func_ptr = Libdl.dlsym(model.lib_handle, :top_enable_trace)
        ccall(func_ptr, Cvoid, (Ptr{Cvoid}, Cstring), model.ptr, filename)
    end
    """
    
    for port in ports
        ctype = port.width <= 8 ? "uint8_t" : "uint32_t"
        jltype = port.width <= 8 ? "UInt8" : "UInt32"
        
        if port.direction == :in
            # Generate C++ Setter
            cpp_code *= "    void set_$(port.name)(V$(module_name)* top, $ctype val) { top->$(port.name) = val; }\n"
            
            # Generate Julia Wrapper
            jl_code *= """
            function set_$(port.name)!(model::VerilatedModel, val::$jltype)
                func_ptr = Libdl.dlsym(model.lib_handle, :set_$(port.name))
                ccall(func_ptr, Cvoid, (Ptr{Cvoid}, $jltype), model.ptr, val)
            end
            """
        else
            # Generate C++ Getter
            cpp_code *= "    $ctype get_$(port.name)(V$(module_name)* top) { return top->$(port.name); }\n"
            
            # Generate Julia Wrapper
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

function build_dut(verilog_file::String, top_module::String; build_dir::String="./build")
    # 1. Create a clean build directory
    build_dir = abspath(build_dir)
    rm(build_dir, force=true, recursive=true)
    mkdir(build_dir)
    
    println("🚀 Step 1: Running Verilator...")
    run(`verilator -Wno-fatal -Wno-DEPRECATED --trace --cc $verilog_file --top-module $top_module -Mdir $build_dir`)
    run(`verilator -Wno-fatal -Wno-DEPRECATED --trace --xml-only $verilog_file --top-module $top_module -Mdir $build_dir`)
    
    println("🧬 Step 2: Parsing XML and generating bindings...")
    xml_path = joinpath(build_dir, "V$(top_module).xml")
    ports = extract_ports(xml_path, top_module)
    cpp_code, jl_code = generate_bindings(ports, top_module)
    
    # Write files to disk
    wrapper_path = joinpath(build_dir, "wrapper.cpp")
    write(wrapper_path, cpp_code)
    
    jl_binding_path = joinpath(build_dir, "bindings.jl")
    write(jl_binding_path, jl_code)
    
    println("🛠️  Step 3: Compiling the Shared Library...")
    verilator_root = strip(read(`verilator --getenv VERILATOR_ROOT`, String))
    inc_dir = joinpath(verilator_root, "include")
    
    # Dynamically find all V<module_name>*.cpp files generated by Verilator
    generated_cpps = filter(f -> startswith(f, "V$(top_module)") && endswith(f, ".cpp"), readdir(build_dir))
    generated_cpp_paths = [joinpath(build_dir, f) for f in generated_cpps]
    
    thread_file = joinpath(inc_dir, "verilated_threads.cpp")
    vcd_file = joinpath(inc_dir, "verilated_vcd_c.cpp")
    
    core_files = [joinpath(inc_dir, "verilated.cpp")]
    isfile(thread_file) && push!(core_files, thread_file)
    isfile(vcd_file) && push!(core_files, vcd_file)

    # Combine them with our wrapper and generated C++
    cpp_files = [
        wrapper_path,
        generated_cpp_paths...,
        core_files...
    ]
    
    output_so = joinpath(build_dir, "libV$(top_module).so")
    
    # Compile
    compile_cmd = `g++ -O3 -fPIC -shared -I$inc_dir -I$build_dir $cpp_files -o $output_so`
    run(compile_cmd)
    
    println("✅ Build complete! Library generated at: $output_so")
    return output_so, jl_binding_path
end

end
