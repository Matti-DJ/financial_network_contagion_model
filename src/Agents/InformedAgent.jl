# InformedAgent.jl
# Julia Script

#=
Description: The informed agent uses UCB1 to decide which action to do. (ia)
Author: matthiasdejong
Date: 22.09.26
=#

const SCRIPT_VERSION = "1.0.0"

"""

#Fields
`predicted_high` - the predicted high of each stock: Dict{Stock, price}
`predicted_low` - the predicted low of each stock: Dict{Stock, price}
`smoothing_rate`- how much weight a fresh reading gets vs. the running estimate
`noise` - how far the predicted high / lows are allowed to drift from init_value, in percent
`arm_reward` - how much reward each arm yields per stock: Dict{Stock, Dict{arm, reward}}
`arm_visits` -  how often each arm is visited per stock: Dict{Stock, Dict{arm, visits}}
`total_pulls` - total pulls across all arms
`latest_wealth` - latest wealth of the agent
`last_arm` - which arm was pulled last
`last_stock` - which stock was chosen last, nothing before the first pull
"""
@agent struct InformedAgent(BaseAgentFields) <: BaseAgent
    predicted_high::Dict{Stock, Float64}
    predicted_low::Dict{Stock, Float64}
    smoothing_rate::Float64
    noise::Float64
    arm_reward::Dict{Stock, Dict{Decision, Float64}}
    arm_visits::Dict{Stock, Dict{Decision, Int}}
    total_pulls::Int
    latest_wealth::Float64
    last_arm::Decision
    last_stock::Union{Stock, Nothing}
end

"""
    Cancels its open orders, updates its fair value estimates, scores the last decision,
    picks an arm via UCB1 for a random stock and executes it if the fair value agrees.
"""
function agent_step!(agent::InformedAgent, sim::Simulation)::InformedAgent
    book = sim.orderbook

    cancel_orders!(book, agent)

    for stock in keys(sim.stocks)
        update_fair_value!(agent, stock)
    end

    score_last_arm!(agent)

    stock = rand(collect(keys(sim.stocks)))
    arm = choose_arm(agent, stock)

    if band_agrees(agent, stock, arm)
        if arm == BUY
            price = agent.predicted_low[stock]
            quantity = buy_quantity(agent, price, sim.config.trade_fraction)
            place_buy_order!(book, quantity, stock, price, agent)
        elseif arm == SELL
            shares = shares_to_sell(agent, stock, sim.config.trade_fraction)
            place_sell_order!(book, shares, stock, agent.predicted_high[stock], agent)
        end
    end

    #records everything for the next scoring step
    agent.total_pulls += 1
    agent.last_arm = arm
    agent.last_stock = stock
    agent.latest_wealth = net_worth(agent)

    return agent
end

"""
    Reads the init value of a stock with noise and folds it into the running estimate via exponential smoothing.
"""
function update_fair_value!(agent::InformedAgent, stock::Stock)::InformedAgent
    noise = rand() * agent.noise / 100
    perceived_low = stock.init_value * (1 - noise)
    perceived_high = stock.init_value * (1 + noise)

    rate = agent.smoothing_rate
    agent.predicted_low[stock] = rate * perceived_low + (1 - rate) * agent.predicted_low[stock]
    agent.predicted_high[stock] = rate * perceived_high + (1 - rate) * agent.predicted_high[stock]

    return agent
end

"""
    Scores the decision of the last tick with the relative change in wealth since then
    and updates the visits / reward of that (stock, arm) pair.
"""
function score_last_arm!(agent::InformedAgent)::InformedAgent
    if agent.last_stock === nothing || agent.latest_wealth <= 0; return agent; end

    reward = (net_worth(agent) - agent.latest_wealth) / agent.latest_wealth

    agent.arm_visits[agent.last_stock][agent.last_arm] += 1
    agent.arm_reward[agent.last_stock][agent.last_arm] += reward

    return agent
end

"""
    Chooses an arm for a stock via UCB1. An unvisited arm is chosen automatically,
    otherwise the arm with the best score: mean_reward + 2 * sqrt(log(total_pulls + 1) / visits)
"""
function choose_arm(agent::InformedAgent, stock::Stock)::Decision
    visits = agent.arm_visits[stock]
    rewards = agent.arm_reward[stock]

    best_arm = HOLD
    best_score = -Inf

    for arm in instances(Decision)
        if visits[arm] == 0; return arm; end

        score = rewards[arm] / visits[arm] + 2 * sqrt(log(agent.total_pulls + 1) / visits[arm])
        if score > best_score
            best_score = score
            best_arm = arm
        end
    end

    return best_arm
end

"""
    Checks if the fair value band agrees with the chosen arm.
    buy -> the latest value is at or below the predicted low
    sell -> the latest value is at or above the predicted high
"""
function band_agrees(agent::InformedAgent, stock::Stock, arm::Decision)::Bool
    if arm == BUY; return stock.latest_value <= agent.predicted_low[stock]; end
    if arm == SELL; return stock.latest_value >= agent.predicted_high[stock]; end

    return false
end
