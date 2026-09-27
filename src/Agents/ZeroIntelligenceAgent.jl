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

"""
    Randomly picks a loan decision it can execute and a random amount.
"""
function loan_step!(agent::ZeroIntelligenceAgent, sim::Simulation)::ZeroIntelligenceAgent
    conf = sim.config
    decision = rand(available_loan_decisions(agent, conf.max_debt_ratio))

    if decision == BORROW
        amount = rand() * borrow_amount(agent, conf.trade_fraction, conf.max_debt_ratio)
        place_borrow_request!(sim.loanbook, amount, agent, sim.orderbook.ticker)
    elseif decision == LEND
        amount = rand() * lend_amount(agent, conf.trade_fraction)
        place_lend_offer!(sim.loanbook, amount, agent, sim.orderbook.ticker)
    end

    return agent
end
