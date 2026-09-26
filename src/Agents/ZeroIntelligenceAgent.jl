# ZeroIntelligenceAgent.jl
# Julia Script

#=
Description: The zero intelligence agent trades randomly with basic constraints. (zia)
Author: matthiasdejong
Date: 22.09.26
=#

const SCRIPT_VERSION = "1.0.0"

@agent struct ZeroIntelligenceAgent(BaseAgentFields) <: BaseAgent
end

"""
    Randomly picks a decision it can execute, a random stock, a random amount and a random price.
"""
function agent_step!(agent::ZeroIntelligenceAgent, sim::Simulation)::ZeroIntelligenceAgent
    book = sim.orderbook
    decision = rand(available_decisions(agent))

    if decision == BUY
        stock = rand(collect(keys(sim.stocks)))
        price = random_price(stock, sim.config.zia_price_range)
        max_quantity = buy_quantity(agent, price, sim.config.trade_fraction)
        if max_quantity == 0; return agent; end

        place_buy_order!(book, rand(1:max_quantity), stock, price, agent)
    elseif decision == SELL
        stock = rand(held_stocks(agent))
        holdings = agent.holdings[stock]
        shares = holdings[1:rand(1:length(holdings))]

        place_sell_order!(book, shares, stock, random_price(stock, sim.config.zia_price_range), agent)
    end

    return agent
end

"""
    Returns an unweighted random price between latest value × (1 ± price_range).
"""
function random_price(stock::Stock, price_range::Float64)::Float64
    return stock.latest_value * (1 - price_range + 2 * price_range * rand())
end
