# BiasedStochasticAgent.jl
# Julia Script

#=
Description: The biased stochastic agent chooses a viable option based on it's constraints. (bsa)
Author: matthiasdejong
Date: 22.09.26
=#

const SCRIPT_VERSION = "1.0.0"

"""

#Fields
- `factor` - the factor which the latest value will be multiplied with
- `agent_standard_factor` - all factors of the agent combined make it's standard factor (the average)
- `own_weight` - how much it's own standard factor counts to making the factor
- `factor_count` - how many factors the agent has drawn, used for the average
"""
@agent struct BiasedStochasticAgent(BaseAgentFields) <: BaseAgent
    factor::Float64
    agent_standard_factor::Float64
    own_weight::Float64
    factor_count::Int
end

"""
    Picks a decision it can execute, draws a factor from a gaussian around its standard factor
    and places the order at latest value × factor.
"""
function agent_step!(agent::BiasedStochasticAgent, sim::Simulation)::BiasedStochasticAgent
    book = sim.orderbook
    decision = rand(available_decisions(agent))
    if decision == HOLD; return agent; end

    draw_factor!(agent, sim.population_standard_factor, sim.config.bsa_factor_std)

    if decision == BUY
        stock = rand(collect(keys(sim.stocks)))
        price = stock.latest_value * agent.factor
        quantity = buy_quantity(agent, price, sim.config.trade_fraction)
        place_buy_order!(book, quantity, stock, price, agent)
    elseif decision == SELL
        stock = rand(held_stocks(agent))
        shares = shares_to_sell(agent, stock, sim.config.trade_fraction)
        place_sell_order!(book, shares, stock, stock.latest_value * agent.factor, agent)
    end

    return agent
end

"""
    Draws a new factor from a gaussian centred on the standard factor, which blends the own
    standard factor with the population standard factor.

# Params
- `agent` - the agent which draws the factor
- `population_standard_factor` - the average standard factor of all biased stochastic agents
- `factor_std` - the standard deviation of the gaussian
"""
function draw_factor!(agent::BiasedStochasticAgent, population_standard_factor::Float64, factor_std::Float64)::BiasedStochasticAgent
    standard_factor = agent.own_weight * agent.agent_standard_factor + (1 - agent.own_weight) * population_standard_factor

    #the factor can't be negative
    agent.factor = max(0.01, standard_factor + factor_std * randn())
    update_standard_factor!(agent)

    return agent
end

"""
    Updates the average factor of the agent with the latest drawn factor.
"""
function update_standard_factor!(agent::BiasedStochasticAgent)::BiasedStochasticAgent
    agent.factor_count += 1
    agent.agent_standard_factor += (agent.factor - agent.agent_standard_factor) / agent.factor_count

    return agent
end

"""
    Picks a loan decision it can execute, the amount is scaled with its latest factor:
    a factor above 1 makes it borrow / lend more, below 1 less.
"""
function loan_step!(agent::BiasedStochasticAgent, sim::Simulation)::BiasedStochasticAgent
    conf = sim.config
    decision = rand(available_loan_decisions(agent, conf.max_debt_ratio))

    if decision == BORROW
        capacity = borrow_capacity(agent, conf.max_debt_ratio)
        amount = min(capacity, borrow_amount(agent, conf.trade_fraction, conf.max_debt_ratio) * agent.factor)
        place_borrow_request!(sim.loanbook, amount, agent, sim.orderbook.ticker)
    elseif decision == LEND
        amount = min(agent.cash, lend_amount(agent, conf.trade_fraction) * agent.factor)
        place_lend_offer!(sim.loanbook, amount, agent, sim.orderbook.ticker)
    end

    return agent
end
