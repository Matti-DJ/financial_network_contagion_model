# MomentumAgent.jl
# Julia Script

#=
Description: The momentum agent buys if the Stock goes up n amount of ticks. (ma)
Author: matthiasdejong
Date: 22.09.26
=#

const SCRIPT_VERSION = "1.0.0"

"""

#Fields
`ticks_to_act` - for how many ticks the stock has to go in 1 direction before the agent acts
"""
@agent struct MomentumAgent(BaseAgentFields) <: BaseAgent
    ticks_to_act::Int
end

"""
    Buys a stock if its price went up on each of its last `ticks_to_act` trades,
    sells it if it went down. The order is placed at the latest value.
"""
function agent_step!(agent::MomentumAgent, sim::Simulation)::MomentumAgent
    book = sim.orderbook

    for stock in keys(sim.stocks)
        streak = detect_streak(book.mean_prices[stock], agent.ticks_to_act)

        if streak == :up
            quantity = buy_quantity(agent, stock.latest_value, sim.config.trade_fraction)
            place_buy_order!(book, quantity, stock, stock.latest_value, agent)
        elseif streak == :down
            shares = shares_to_sell(agent, stock, sim.config.trade_fraction)
            place_sell_order!(book, shares, stock, stock.latest_value, agent)
        end
    end

    return agent
end
