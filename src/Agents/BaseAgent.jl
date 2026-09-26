# BaseAgent.jl
# Julia Script

#=
Description: The base agent acts like structure for all other agents.
It does not trade and does not have any behaviour.
All agents inherit its fields.
Author: matthiasdejong
Date: 19.09.26
=#

const SCRIPT_VERSION = "1.0.0"

"""
    the market decisions every agent can make
"""
@enum Decision BUY SELL HOLD

abstract type BaseAgent <: AbstractAgent end

"""
    Holds the fields every agent inherits. The `id::Int` is added by `NoSpaceAgent`.

# Fields
- `id:` the id of the agent
- `cash:` how much cash the agent has on hand
- `holdings:` which shares the agent has of what stock: `Dict{Stock, Vector{Share}}`
- `shares_bought:` how many shares the agent has bought
- `shares_sold:` how many shares the agent has sold
- `volume_bought:` the value of all bought shares
- `volume_sold:` the value of all sold shares
- `buy_orders:` how many buy orders the agent has made
- `sell_orders:` how many sell orders the agent has made
"""
@agent struct BaseAgentFields(NoSpaceAgent) <: BaseAgent
    cash::Float64
    holdings::Dict{Stock,Vector{Share}}
    shares_bought::Int
    shares_sold::Int
    volume_bought::Float64
    volume_sold::Float64
    buy_orders::Int
    sell_orders::Int
end

"""
    Returns the values of the base fields for a new agent, so they can be splatted into the constructor
    of every agent type e.g. `MomentumAgent(base_fields(id, cash)..., ticks_to_act)`

# Params
- `id` - the id of the new agent
- `cash` - the starting cash of the new agent
"""
function base_fields(id::Int, cash::Float64)::Tuple
    return (id, cash, Dict{Stock,Vector{Share}}(), 0, 0, 0.0, 0.0, 0, 0)
end

"""
Records a buy order on the agent side.
Adds all the shares to the correct stock and makes the agent the new owner.

# Params
- `agent` the agent which bought the items
- `shares` - a list of all shares which were bought
- `stock` - the stock which the shares are bought from
"""
function record_buy_order!(agent::BaseAgent, shares::Vector{Share}, stock::Stock)::BaseAgent
    order_volume = (length(shares) * stock.latest_value)

    agent.cash -= order_volume
    agent.volume_bought += order_volume
    agent.shares_bought += length(shares)
    agent.buy_orders += 1

    #appends all shares to the correct stock and assigns the new owner
    for share in shares
        assign_new_owner!(share, agent.id)
    end
    append!(get!(agent.holdings, stock, Share[]), shares)

    return agent
end

"""
    records a sell order on the agent side and removes the items from the
    holdings of the agent.

# Params
- `agent` - the agent who sold the shares
- `shares` - a list of all items which were sold
- `stock` of which stock the shares were sold
"""
function record_sell_order!(agent::BaseAgent, shares::Vector{Share}, stock::Stock)::Tuple{BaseAgent,Vector{Share}}
    holdings = get!(agent.holdings, stock, Share[])

    #only shares the agent actually holds can be sold
    to_sell = Set(shares)
    sold_items = filter(share -> share in to_sell, holdings)

    #removes the sold shares from the holdings of the agent
    filter!(share -> !(share in to_sell), holdings)

    order_volume = length(sold_items) * stock.latest_value

    agent.cash += order_volume
    agent.volume_sold += order_volume
    agent.shares_sold += length(sold_items)
    agent.sell_orders += 1

    return agent, sold_items
end

"""
    Returns the wealth of the agent: cash + the value of all shares it holds.

# Params
- `agent` - the agent to calculate the net worth for
"""
function net_worth(agent::BaseAgent)::Float64
    share_value = 0.0
    for (stock, shares) in agent.holdings
        share_value += length(shares) * stock.latest_value
    end

    return agent.cash + share_value
end

"""
    Returns all decisions the agent is able to execute right now.
    no cash -> no buy, no shares -> no sell, hold is always possible.

# Params
- `agent` - the agent which wants to make a decision
"""
function available_decisions(agent::BaseAgent)::Vector{Decision}
    decisions = Decision[HOLD]

    if agent.cash > 0; push!(decisions, BUY); end
    if any(!isempty, values(agent.holdings)); push!(decisions, SELL); end

    return decisions
end

"""
    Returns how many shares the agent can buy for a price with a fraction of its cash.
    Buys at least 1 share if the agent can afford it.

# Params
- `agent` - the agent who wants to buy
- `price` - the price of a single share
- `fraction` - the fraction of the cash the agent wants to spend
"""
function buy_quantity(agent::BaseAgent, price::Float64, fraction::Float64)::Int
    if price <= 0 || agent.cash < price; return 0; end

    return max(1, floor(Int, agent.cash * fraction / price))
end

"""
    Returns the shares the agent wants to sell of a stock, a fraction of its holdings of that stock.
    Sells at least 1 share if the agent has one.

# Params
- `agent` - the agent who wants to sell
- `stock` - the stock of which the shares are sold
- `fraction` - the fraction of the holdings the agent wants to sell
"""
function shares_to_sell(agent::BaseAgent, stock::Stock, fraction::Float64)::Vector{Share}
    holdings = get(agent.holdings, stock, Share[])
    if isempty(holdings); return Share[]; end

    amount = clamp(floor(Int, length(holdings) * fraction), 1, length(holdings))
    return holdings[1:amount]
end

"""
    Returns all stocks of which the agent holds at least one share.
"""
function held_stocks(agent::BaseAgent)::Vector{Stock}
    return [stock for (stock, shares) in agent.holdings if !isempty(shares)]
end

"""
    The behaviour of an agent in a tick. The base agent does nothing,
    every agent type has its own method.
"""
function agent_step!(agent::BaseAgent, sim)::BaseAgent
    return agent
end
