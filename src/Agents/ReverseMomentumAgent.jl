# ReverseMomentumAgent.jl
# Julia Script

#=
Description: The reverse momentum trader buys if the market goes down. (rma)
Author: matthiasdejong
Date: 22.09.26
=#

const SCRIPT_VERSION = "1.0.0"

@agent struct ReverseMomentumAgent(BaseAgentFields) <: BaseAgent
end

"""
    Buys a stock if its price went down on each of its last `ma_rma_direction` trades,
    sells it if it went up. The order is placed at the latest value.
"""
function agent_step!(agent::ReverseMomentumAgent, sim::Simulation)::ReverseMomentumAgent
    book = sim.orderbook

    for stock in keys(sim.stocks)
        streak = detect_streak(book.mean_prices[stock], sim.config.ma_rma_direction)

        if streak == :down
            quantity = buy_quantity(agent, stock.latest_value, sim.config.trade_fraction)
            place_buy_order!(book, quantity, stock, stock.latest_value, agent)
        elseif streak == :up
            shares = shares_to_sell(agent, stock, sim.config.trade_fraction)
            place_sell_order!(book, shares, stock, stock.latest_value, agent)
        end
    end

    return agent
end
