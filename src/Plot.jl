# Plot.jl
# Julia Script

#=
Description: Plots the price of each stock over the ticks of the simulation as interactive plots (PlotlyJS).
The plots are saved as html and opened in the browser, there you can zoom, pan and hover over the prices.
Author: matthiasdejong
Date: 27.09.26
=#

const SCRIPT_VERSION = "1.0.0"

const PlotlyBase = PlotlyJS.PlotlyBase

#shows the tick and price when hovering over a line
const PRICE_HOVER = "tick %{x:,}<br>price %{y:,.2f}<extra>%{fullData.name}</extra>"
const CHANGE_HOVER = "tick %{x:,}<br>change %{y:+,.2f}%<extra>%{fullData.name}</extra>"

"""
    Returns every n-th point of a price history, so the plot stays fast with millions of ticks.
    The last point is always kept.

# Params
- `history` - the ticks and prices of a stock
- `max_points` - the maximum amount of points to plot
"""
function thin_history(history::NamedTuple, max_points::Int)::NamedTuple
    step = max(1, cld(length(history.ticks), max_points))
    indices = collect(1:step:length(history.ticks))
    if last(indices) != length(history.ticks); push!(indices, length(history.ticks)); end

    return (ticks = history.ticks[indices], prices = history.prices[indices])
end

"""
    Opens a file in the default browser.
"""
function open_in_browser(path::String)
    if Sys.isapple()
        run(`open $path`)
    elseif Sys.iswindows()
        run(`cmd /c start "" $path`)
    else
        run(`xdg-open $path`)
    end
end

"""
    Saves an interactive plot as html and opens it in the browser.
    Without a path it is saved to a temporary file.

# Params
- `figure` - the plot to show
- `path` - where to save the plot, has to end with .html
- `open_browser` - if the plot should be opened in the browser
"""
function show_plot(figure::PlotlyBase.Plot, path::Union{String,Nothing}, open_browser::Bool)::PlotlyBase.Plot
    if path === nothing && !open_browser; return figure; end

    file = path === nothing ? tempname() * ".html" : path
    open(file, "w") do io
        PlotlyBase.to_html(io, figure; include_plotlyjs = "cdn")
    end
    if open_browser; open_in_browser(file); end

    return figure
end

"""
    Creates the line of a stock's price over the ticks.

# Params
- `stats` - the stats returned by `run_simulation` / `collect_stats`
- `stock_name` - the name of the stock
- `max_points` - the maximum amount of points to plot
"""
function price_line(stats::NamedTuple, stock_name::String, max_points::Int)::PlotlyBase.GenericTrace
    history = thin_history(stats.price_history[stock_name], max_points)

    return PlotlyJS.scatter(x = history.ticks, y = history.prices, mode = "lines", name = stock_name,
        line_width = 1, hovertemplate = PRICE_HOVER)
end

"""
    Returns the title of a stock plot e.g. "stock1 +12.34%"
"""
function stock_title(stock::NamedTuple)::String
    return "$(stock.name)  $(format_percent(stock.change))"
end

"""
    Plots the price of a single stock over the ticks, with its init value as a dashed line.

# Params
- `stats` - the stats returned by `run_simulation` / `collect_stats`
- `stock_name` - the name of the stock to plot
- `path` - if given, the plot is saved to this file e.g. "stock1.html"
- `open_browser` - if the plot should be opened in the browser
- `max_points` - the maximum amount of points to plot
"""
function plot_stock(stats::NamedTuple, stock_name::String; path::Union{String,Nothing} = nothing,
                    open_browser::Bool = true, max_points::Int = 50_000)::PlotlyBase.Plot
    stock = only(filter(stock -> stock.name == stock_name, stats.stocks))

    layout = PlotlyJS.Layout(title = stock_title(stock), height = 650, showlegend = false, hovermode = "x",
        xaxis = PlotlyJS.attr(title = "tick", tickformat = ","),
        yaxis = PlotlyJS.attr(title = "price", tickformat = ","))
    figure = PlotlyJS.Plot(price_line(stats, stock_name, max_points), layout)
    PlotlyBase.add_hline!(figure, stock.init_value; line_dash = "dash", line_color = "gray", line_width = 1)

    return show_plot(figure, path, open_browser)
end

"""
    Plots the price of every stock, each stock in its own plot with its init value as a dashed line.

# Params
- `stats` - the stats returned by `run_simulation` / `collect_stats`
- `path` - if given, the plot is saved to this file e.g. "stocks.html"
- `open_browser` - if the plot should be opened in the browser
- `max_points` - the maximum amount of points to plot per stock
"""
function plot_stocks(stats::NamedTuple; path::Union{String,Nothing} = nothing,
                     open_browser::Bool = true, max_points::Int = 10_000)::PlotlyBase.Plot
    columns = ceil(Int, sqrt(length(stats.stocks)))
    rows = ceil(Int, length(stats.stocks) / columns)

    #plotly places the titles row by row but reads the matrix column by column,
    #so the titles are put into the matrix in the order they are placed. Empty places get no title
    title_list = Union{Missing,String}[i <= length(stats.stocks) ? stock_title(stats.stocks[i]) : missing for i in 1:(rows * columns)]
    titles = reshape(title_list, rows, columns)

    subplots = PlotlyJS.make_subplots(rows = rows, cols = columns, subplot_titles = titles,
        vertical_spacing = 0.3 / rows, horizontal_spacing = 0.2 / columns)
    for (i, stock) in enumerate(stats.stocks)
        PlotlyJS.add_trace!(subplots, price_line(stats, stock.name, max_points); row = cld(i, columns), col = mod1(i, columns))
    end

    figure = subplots.plot
    for (i, stock) in enumerate(stats.stocks)
        PlotlyBase.add_hline!(figure, stock.init_value; row = cld(i, columns), col = mod1(i, columns),
            line_dash = "dash", line_color = "gray", line_width = 1)
    end

    PlotlyBase.relayout!(figure; height = 330 * rows, showlegend = false, title = "price of every stock")
    PlotlyBase.update_xaxes!(figure; tickformat = ",")
    PlotlyBase.update_yaxes!(figure; tickformat = ",")

    return show_plot(figure, path, open_browser)
end

"""
    Plots all stocks in one plot as the change in percent from their init value,
    so stocks with very different prices can be compared.
    Clicking a stock in the legend hides / shows it, double clicking shows only that stock.

# Params
- `stats` - the stats returned by `run_simulation` / `collect_stats`
- `path` - if given, the plot is saved to this file e.g. "overview.html"
- `open_browser` - if the plot should be opened in the browser
- `max_points` - the maximum amount of points to plot per stock
"""
function plot_stock_overview(stats::NamedTuple; path::Union{String,Nothing} = nothing,
                             open_browser::Bool = true, max_points::Int = 10_000)::PlotlyBase.Plot
    lines = PlotlyBase.GenericTrace[]
    for stock in stats.stocks
        history = thin_history(stats.price_history[stock.name], max_points)
        change = (history.prices ./ stock.init_value .- 1) .* 100
        push!(lines, PlotlyJS.scatter(x = history.ticks, y = change, mode = "lines", name = stock.name,
            line_width = 1, hovertemplate = CHANGE_HOVER))
    end

    layout = PlotlyJS.Layout(title = "change of all stocks", height = 650,
        xaxis = PlotlyJS.attr(title = "tick", tickformat = ","),
        yaxis = PlotlyJS.attr(title = "change from init value in %", tickformat = ","))
    figure = PlotlyJS.Plot(lines, layout)
    PlotlyBase.add_hline!(figure, 0.0; line_dash = "dash", line_color = "gray", line_width = 1)

    return show_plot(figure, path, open_browser)
end
