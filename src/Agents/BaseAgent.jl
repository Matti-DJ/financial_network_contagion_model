# BaseAgent.jl
# Julia Script

#=
Description: The base agent acts like structure for all other agents.
It does not trade and does not have any behaviour.
All agents inherit its fields.
Author: matthiasdejong
Date: 19.09.26
=#

const SCRIPT_VERSION = "1.1.0"

"""
    the market decisions every agent can make
"""
@enum Decision BUY SELL HOLD

"""
    the loan decisions every agent can make, pass = neither borrow nor lend
"""
@enum LoanDecision BORROW LEND PASS

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
- `debtors:` how much money each debtor owes the agent: `Dict{debtor id, amount}`
- `lenders:` how much money the agent borrowed from each lender: `Dict{lender id, amount}`
- `fees_paid:` all trading and loan fees the agent paid
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
    debtors::Dict{Int,Float64}
    lenders::Dict{Int,Float64}
    fees_paid::Float64
end

"""
    Returns the values of the base fields for a new agent, so they can be splatted into the constructor
    of every agent type e.g. `MomentumAgent(base_fields(id, cash)..., ticks_to_act)`

# Params
- `id` - the id of the new agent
- `cash` - the starting cash of the new agent
"""
function base_fields(id::Int, cash::Float64)::Tuple
    return (id, cash, Dict{Stock,Vector{Share}}(), 0, 0, 0.0, 0.0, 0, 0, Dict{Int,Float64}(), Dict{Int,Float64}(), 0.0)
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
    Takes a fee from the cash of the agent.
"""
function pay_fee!(agent::BaseAgent, fee::Float64)::BaseAgent
    agent.cash -= fee
    agent.fees_paid += fee

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
    Returns the wealth of the agent: cash + the value of all shares it holds + what it lent - what it borrowed.
    The interest only counts once a loan is repaid.

# Params
- `agent` - the agent to calculate the net worth for
"""
function net_worth(agent::BaseAgent)::Float64
    share_value = 0.0
    for (stock, shares) in agent.holdings
        share_value += length(shares) * stock.latest_value
    end

    return agent.cash + share_value + total_lent(agent) - total_borrowed(agent)
end

"""
    Returns how much money the debtors of the agent still owe it, without interest.
"""
total_lent(agent::BaseAgent)::Float64 = sum(values(agent.debtors); init = 0.0)

"""
    Returns how much money the agent still owes its lenders, without interest.
"""
total_borrowed(agent::BaseAgent)::Float64 = sum(values(agent.lenders); init = 0.0)

"""
    Returns how much more the agent may borrow: its total debt can't be more than `max_debt_ratio` × its net worth.

# Params
- `agent` - the agent which wants to borrow
- `max_debt_ratio` - the maximum debt relative to the net worth
"""
function borrow_capacity(agent::BaseAgent, max_debt_ratio::Float64)::Float64
    return max(0.0, max_debt_ratio * net_worth(agent) - total_borrowed(agent))
end

"""
    Returns all loan decisions the agent is able to execute right now.
    no cash -> no lend, no borrow capacity -> no borrow, pass is always possible.

# Params
- `agent` - the agent which wants to make a decision
- `max_debt_ratio` - the maximum debt relative to the net worth
"""
function available_loan_decisions(agent::BaseAgent, max_debt_ratio::Float64)::Vector{LoanDecision}
    decisions = LoanDecision[PASS]

    if agent.cash >= MIN_LOAN; push!(decisions, LEND); end
    if borrow_capacity(agent, max_debt_ratio) >= MIN_LOAN; push!(decisions, BORROW); end

    return decisions
end

"""
    Returns how much the agent lends with a fraction of its cash.
"""
lend_amount(agent::BaseAgent, fraction::Float64)::Float64 = agent.cash * fraction

"""
    Returns how much the agent borrows: a fraction of its net worth, at most its borrow capacity.
"""
function borrow_amount(agent::BaseAgent, fraction::Float64, max_debt_ratio::Float64)::Float64
    return min(borrow_capacity(agent, max_debt_ratio), max(0.0, net_worth(agent) * fraction))
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

"""
    The loan behaviour of an agent in a tick, it decides to borrow, lend or pass. The base agent does nothing,
    every agent type has its own method which uses the same algorithm it trades with.
"""
function loan_step!(agent::BaseAgent, sim)::BaseAgent
    return agent
end
