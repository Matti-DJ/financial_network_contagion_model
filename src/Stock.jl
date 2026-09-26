# Stock.jl
# Julia Script

#=
Description: The stock is the tradeable instrument in this simulation. Each Share of a stock is traded.
Author: matthiasdejong
Date: 19.09.26
=#

const SCRIPT_VERSION = "1.0.0"

"""
- `id:` the unique id of the stock
- `name:` stock numbered `1...n`
- `total_shares:` how many shares of this stock exist in the simulation
- `init_value:` the initial value of a single share of that stock
- `latest_value:` the latest value of a single share of a stock
- `highest_value:` the highest value a single share of that stock reached
- `lowest_value:` the lowest value a single share of that stock had
- `times_traded:` how often the shares of that stock were traded
"""
mutable struct Stock
    id::UUID
    name::String
    total_shares::Int
    init_value::Float64
    latest_value::Float64
    highest_value::Float64
    lowest_value::Float64
    times_traded::Int
end

Stock() = Stock(uuid4(), "", 0, 0.0, 0.0, 0.0, 0.0, 0)

"""
    creates a stock, all values start at the init_value
"""
Stock(name::String, init_value::Float64) = Stock(uuid4(), name, 0, init_value, init_value, init_value, init_value, 0)

"""
    records latest value and checks for highest / lowest values.
"""
function record_latest_value!(stock::Stock, value::Float64)::Stock
    stock.latest_value = value
    stock.times_traded += 1

    #record highest value
    stock.highest_value = max(stock.highest_value, value)

    #record lowest value
    stock.lowest_value = min(stock.lowest_value, value)

    return stock
end
