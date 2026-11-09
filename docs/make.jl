using Documenter
using VeriJul

makedocs(
    sitename = "VeriJul.jl",
    modules = [VeriJul],
    authors = "Rainer Rodrigues",
    format = Documenter.HTML(prettyurls = get(ENV, "CI", nothing) == "true"),
    pages = [
        "Home" => "index.md",
        "Guide" => "guide.md",
        "API" => "api.md",
    ],
)

deploydocs(repo = "github.com/rainerrodrigues/VeriJul.jl.git", devbranch = "main")
