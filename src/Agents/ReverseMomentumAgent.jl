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

"""
    Borrows if a stock went down on each of its last `ma_rma_direction` trades, so it has more cash to buy it,
    lends if a stock went up, the cash from selling isn't needed.
"""
function loan_step!(agent::ReverseMomentumAgent, sim::Simulation)::ReverseMomentumAgent
    conf = sim.config
    book = sim.orderbook
    streaks = [detect_streak(book.mean_prices[stock], sim.config.ma_rma_direction) for stock in keys(sim.stocks)]

    if :down in streaks
        place_borrow_request!(sim.loanbook, borrow_amount(agent, conf.trade_fraction, conf.max_debt_ratio), agent, book.ticker)
    elseif :up in streaks
        place_lend_offer!(sim.loanbook, lend_amount(agent, conf.trade_fraction), agent, book.ticker)
    end

    return agent
end
