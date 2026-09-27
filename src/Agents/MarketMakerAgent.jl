# MarketMakerAgent.jl
# Julia Script

#=
Description: The market maker agent has a fixed buy / sell price which is updated al n amount of ticks. (mma)
Author: matthiasdejong
Date: 22.09.26
=#

const SCRIPT_VERSION = "1.0.0"

const MMA_BUY_FACTOR = 0.99
const MMA_SELL_FACTOR = 1.01

"""

#Fields
`buy_price` - the current price the agent buys a share from each stock
`sell_price` - the current price the agent sells a share from each stock
`highest_buy_price` - the highest buy price the agent had for each stock
`lowest_buy_price` - the lowest buy price the agent had for each stock
`highest_sell_price` - the highest sell price the agent had for each stock
`lowest_sell_price` - the lowest sell price each agent had for each stock
`last_reprice` - at which tick the agent put up its prices the last time
"""
@agent struct MarketMakerAgent(BaseAgentFields) <: BaseAgent
    buy_price::Dict{Stock, Float64}
    sell_price::Dict{Stock, Float64}
    highest_buy_price::Dict{Stock, Float64}
    lowest_buy_price::Dict{Stock, Float64}
    highest_sell_price::Dict{Stock, Float64}
    lowest_sell_price::Dict{Stock, Float64}
    last_reprice::Int
end

"""
    If `mma_reprice` ticks passed since its last reprice the market maker cancels all its orders and posts new ones
    for every stock. In between its orders stay at the price they were posted at.
"""
function agent_step!(agent::MarketMakerAgent, sim::Simulation)::MarketMakerAgent
    book = sim.orderbook

    #only reprices if at least n ticks passed since the last time
    if book.ticker - agent.last_reprice < sim.config.mma_reprice; return agent; end

    agent.last_reprice = book.ticker
    cancel_orders!(book, agent)
    for stock in keys(sim.stocks)
        reprice!(agent, sim, stock)
    end

    return agent
end

"""
    Sets a new buy / sell price for a stock based on its latest value and posts the orders.

# Params
- `agent` - the market maker which reprices
- `sim` - the simulation with the orderbook
- `stock` - the stock to reprice
"""
function reprice!(agent::MarketMakerAgent, sim::Simulation, stock::Stock)::MarketMakerAgent
    agent.buy_price[stock] = stock.latest_value * MMA_BUY_FACTOR
    agent.sell_price[stock] = stock.latest_value * MMA_SELL_FACTOR
    update_price_extremes!(agent, stock)

    #the cash is split over all stocks
    fraction = sim.config.trade_fraction / length(sim.stocks)
    quantity = buy_quantity(agent, agent.buy_price[stock], fraction)
    place_buy_order!(sim.orderbook, quantity, stock, agent.buy_price[stock], agent)

    shares = shares_to_sell(agent, stock, sim.config.trade_fraction)
    place_sell_order!(sim.orderbook, shares, stock, agent.sell_price[stock], agent)

    return agent
end

"""
    Records the highest / lowest buy and sell prices of a stock.
"""
function update_price_extremes!(agent::MarketMakerAgent, stock::Stock)::MarketMakerAgent
    buy_price = agent.buy_price[stock]
    sell_price = agent.sell_price[stock]

    agent.highest_buy_price[stock] = max(get(agent.highest_buy_price, stock, buy_price), buy_price)
    agent.lowest_buy_price[stock] = min(get(agent.lowest_buy_price, stock, buy_price), buy_price)
    agent.highest_sell_price[stock] = max(get(agent.highest_sell_price, stock, sell_price), sell_price)
    agent.lowest_sell_price[stock] = min(get(agent.lowest_sell_price, stock, sell_price), sell_price)

    return agent
end

"""
    Together with its reprice the market maker balances its cash: if its cash is below `trade_fraction` × its
    net worth it borrows the difference, otherwise it lends a fraction of its cash.
"""
function loan_step!(agent::MarketMakerAgent, sim::Simulation)::MarketMakerAgent
    conf = sim.config
    book = sim.orderbook

    #only acts when it reprices, agent_step! updates last_reprice afterwards
    if book.ticker - agent.last_reprice < conf.mma_reprice; return agent; end

    target_cash = net_worth(agent) * conf.trade_fraction
    if agent.cash < target_cash
        amount = min(target_cash - agent.cash, borrow_capacity(agent, conf.max_debt_ratio))
        place_borrow_request!(sim.loanbook, amount, agent, book.ticker)
    else
        place_lend_offer!(sim.loanbook, lend_amount(agent, conf.trade_fraction), agent, book.ticker)
    end

    return agent
end
