# Report.jl
# Julia Script

#=
Description: Prints the collected stats of a simulation as a structured report.
Author: matthiasdejong
Date: 26.09.26
=#

const SCRIPT_VERSION = "1.0.0"

const REPORT_WIDTH = 96

"""
    Formats a number with thousand separators e.g. 1234567.891 -> "1,234,567.89"

# Params
- `value` - the number to format
- `digits` - how many decimals to show
"""
function format_number(value::Real; digits::Int = 2)::String
    scaled = round(Int, abs(value) * 10^digits)
    whole, fraction = divrem(scaled, 10^digits)

    whole_text = replace(string(whole), r"(?<=\d)(?=(\d{3})+$)" => ",")
    fraction_text = digits > 0 ? "." * lpad(string(fraction), digits, '0') : ""
    sign = (value < 0 && scaled > 0) ? "-" : ""

    return sign * whole_text * fraction_text
end

"""
    Formats a percentage with a sign e.g. 12.346 -> "+12.35%"
"""
function format_percent(value::Real)::String
    return (value >= 0 ? "+" : "") * format_number(value) * "%"
end

"""
    Formats a duration in seconds e.g. 75.3 -> "1 min 15.3 s"
"""
function format_duration(seconds::Real)::String
    if seconds < 60; return string(round(seconds; digits = 2), " s"); end

    minutes, rest = divrem(seconds, 60)
    return string(Int(minutes), " min ", round(rest; digits = 1), " s")
end

"""
    Prints a title with a line under it.
"""
function print_section(io::IO, title::String)
    println(io)
    println(io, " ", title)
    println(io, " ", "─"^(REPORT_WIDTH - 1))
end

"""
    Prints a table, the first column is aligned left, all others right.

# Params
- `io` - where to print to
- `header` - the names of the columns
- `rows` - the cells of every row, already formatted as text
"""
function print_table(io::IO, header::Vector{String}, rows::Vector{Vector{String}})
    widths = [maximum(length, [header[i]; [row[i] for row in rows]]) for i in eachindex(header)]

    format_row(cells) = join([i == 1 ? rpad(cell, widths[i]) : lpad(cell, widths[i]) for (i, cell) in enumerate(cells)], "   ")

    println(io, " ", format_row(header))
    println(io, " ", join(["─"^width for width in widths], "   "))
    for row in rows
        println(io, " ", format_row(row))
    end
end

"""
    Prints the collected stats of a simulation as a structured report with an overview,
    a table of all stocks and a table of all agent types.

# Params
- `stats` - the stats returned by `run_simulation` / `collect_stats`
- `io` - where to print to, the terminal by default
"""
function print_stats(stats::NamedTuple, io::IO = stdout)
    println(io, "═"^REPORT_WIDTH)
    println(io, " SIMULATION RESULTS")
    println(io, "═"^REPORT_WIDTH)

    #overview
    print_section(io, "OVERVIEW")
    overview = [
        ("ticks", format_number(stats.ticks; digits = 0)),
        ("rounds", format_number(stats.rounds; digits = 0)),
        ("stocks", format_number(length(stats.stocks); digits = 0)),
        ("agents", format_number(sum(agent.count for agent in stats.agents; init = 0); digits = 0)),
        ("trades", format_number(length(stats.trades); digits = 0)),
        ("shares traded", format_number(stats.shares_traded; digits = 0)),
        ("ticks per round", format_number(stats.ticks / max(stats.rounds, 1))),
        ("trades per round", format_number(length(stats.trades) / max(stats.rounds, 1))),
    ]
    if haskey(stats, :runtime)
        push!(overview, ("runtime", format_duration(stats.runtime)))
        push!(overview, ("time per round", string(format_number(stats.runtime / max(stats.rounds, 1) * 1000), " ms")))
    end

    label_width = maximum(length(label) for (label, _) in overview)
    for (label, value) in overview
        println(io, " ", rpad(label, label_width), "   ", value)
    end

    #stocks
    print_section(io, "STOCKS")
    stock_rows = [[stock.name,
                   format_number(stock.total_shares; digits = 0),
                   format_number(stock.init_value),
                   format_number(stock.latest_value),
                   format_percent(stock.change),
                   format_number(stock.lowest_value),
                   format_number(stock.highest_value),
                   format_number(stock.times_traded; digits = 0)] for stock in stats.stocks]
    print_table(io, ["stock", "shares", "init", "latest", "change", "lowest", "highest", "trades"], stock_rows)

    #agents
    print_section(io, "AGENTS")
    agent_rows = [[string(agent.type),
                   format_number(agent.count; digits = 0),
                   format_number(agent.starting_wealth),
                   format_number(agent.wealth),
                   format_percent(agent.change),
                   format_number(agent.cash),
                   format_number(agent.shares_bought; digits = 0),
                   format_number(agent.shares_sold; digits = 0)] for agent in stats.agents]
    print_table(io, ["type", "count", "start wealth", "end wealth", "change", "cash", "bought", "sold"], agent_rows)

    println(io)
    println(io, " wealth / cash = average per agent, bought / sold = total shares of all agents of that type")
    println(io, "═"^REPORT_WIDTH)

    return nothing
end
