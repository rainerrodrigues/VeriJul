using Documenter
using VeriJul

makedocs(
    sitename = "VeriJul.jl",
    modules = [VeriJul],
    authors = "Rainer Rodrigues",
    # DOCS_DRAFT=true skips running the @example blocks (no Verilator needed)
    draft = get(ENV, "DOCS_DRAFT", "false") == "true",
    format = Documenter.HTML(prettyurls = get(ENV, "CI", nothing) == "true"),
    pages = [
        "Home" => "index.md",
        "Tutorials" => [
            "tutorials/getting_started.md",
            "tutorials/testbenches.md",
            "tutorials/build_and_clocks.md",
            "tutorials/ports.md",
        ],
        "Migrating from 0.1" => "guides/migrating.md",
        "API" => "api.md",
    ],
)

deploydocs(repo = "github.com/rainerrodrigues/VeriJul.jl.git", devbranch = "main")
