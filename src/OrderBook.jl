# OrderBook.jl
# Julia Script

#=
Description: keeps track of current order and trades. Matches those trades and also checks if they can be placed.
Author: matthiasdejong
Date: 22.09.26
=#

const SCRIPT_VERSION = "1.1.0"

"""
    The buy order is placed buy someone who wants to buy a quantity of items.

# Fields
- `quantity` - how many the buyer wants to buy
- `new_owner` - the buyer of the shares
- `stock` - the stock of which the share should be bought
- `tick` - at which tick the order was placed
- `max_price` - the max price a buyer is willing to pay for one share
"""
mutable struct BuyOrder
    quantity::Int
    new_owner::BaseAgent
    stock::Stock
    tick::Int
    max_price::Float64
end


"""
# Fields
- `shares` - all shares which are sold
- `stock` - The stock of which the shares are from
- `owner` - the current owner of the shares
- `tick` - at which tick the order was placed
- `min_price` - the minimum price the seller wants for one share
"""
mutable struct SellOrder
    shares::Vector{Share}
    stock::Stock
    owner::BaseAgent
    tick::Int
    min_price::Float64
end

"""
# Fields
- `id` - the id of the trade
- `buyer_id` - the id of the buyer of the shares
- `seller_id` - the id of the seller of the items
- `shares` - a list of all shares which were in the trade
- `share_price`- the price of a single share
- `tick` - at which tick the trade occurred
"""
mutable struct Trade
    id::UUID
    buyer_id::Int
    seller_id::Int
    shares::Vector{Share}
    share_price::Float64
    tick::Int
end

"""

# Fields
- `buy_orders` - all open buy orders per stock, sorted by price (highest first), then tick (earliest first)
- `sell_orders` - all open sell orders per stock, sorted by price (lowest first), then tick (earliest first)
- `ticker` - the ingame clock, increments with each order which is put up and each trade which is executed
- `trades` - a list of all trades which happened in the simulation
- `mean_prices` - the price of each stock at every tick it was traded: Dict{Stock, Vector{price}}.
  A tick has at most one trade, so the mean price of a tick is the price of its trade.
- `fee_rate` - the fee the buyer and the seller each pay on the volume of a trade, 0.001 = 0.1%
- `fees_collected` - all trading fees the agents paid, the fees leave the market
"""
mutable struct OrderBook
    buy_orders::Dict{Stock,Vector{BuyOrder}}
    sell_orders::Dict{Stock,Vector{SellOrder}}
    ticker::Int
    trades::Vector{Trade}
    mean_prices::Dict{Stock,Vector{Float64}}
    fee_rate::Float64
    fees_collected::Float64
end

OrderBook(fee_rate::Float64 = 0.0) = OrderBook(
    Dict{Stock,Vector{BuyOrder}}(),
    Dict{Stock,Vector{SellOrder}}(),
    0,
    Trade[],
    Dict{Stock,Vector{Float64}}(),
    fee_rate,
    0.0,
)

"""
    Returns how many shares a buyer can afford at a price, including the trading fee.
"""
affordable_quantity(book::OrderBook, buyer::BaseAgent, price::Float64)::Int = floor(Int, buyer.cash / (price * (1 + book.fee_rate)))

#sort keys: best price first, then earliest tick
buy_order_key(order::BuyOrder) = (-order.max_price, order.tick)
sell_order_key(order::SellOrder) = (order.min_price, order.tick)

"""
    Adds a stock to the orderbook so orders of it can be placed.
    The mean price history starts with the init value of the stock.

# Params
- `book` - the orderbook to add the stock to
- `stock` - the stock to add
"""
function add_stock!(book::OrderBook, stock::Stock)::OrderBook
    book.buy_orders[stock] = BuyOrder[]
    book.sell_orders[stock] = SellOrder[]
    book.mean_prices[stock] = Float64[stock.init_value]

    return book
end

"""
    Returns the best buy order (highest price) from a stock, nothing if there is none

# Params
- `book` - the orderbook which contains the orders
- `stock` - the stock of which to get the order from
"""
function get_cheapest_buy_order(book::OrderBook, stock::Stock)::Union{BuyOrder,Nothing}
    orders = book.buy_orders[stock]
    return isempty(orders) ? nothing : first(orders)
end

"""
    Returns the best sell order (lowest price) from a Stock, nothing if there is none

# Params
- `book` - the orderbook which contains the orders
- `stock` - the stock of which to get the order from
"""
function get_most_expensive_sell_order(book::OrderBook, stock::Stock)::Union{SellOrder,Nothing}
    orders = book.sell_orders[stock]
    return isempty(orders) ? nothing : first(orders)
end

"""
Tracks a trade to keep track of all trades which have happened.

# Fields
- `book` - the orderbook to track
- `buyer_id` - the id of who bought the shares
- `seller_id` - the id of who sold the shares
- `shares` - a list of shares which were sold
- `share_price` - the price of a single share
- `tick` - the tick at which the trade occurred
"""
function track_trade!(book::OrderBook, buyer_id::Int, seller_id::Int, shares::Vector{Share}, share_price::Float64, tick::Int)::OrderBook
    trade = Trade(uuid4(), buyer_id, seller_id, shares, share_price, tick)
    push!(book.trades, trade)

    return book
end

"""
    Executes a trade between a buyer and a seller. Every trade is a tick. Updates the stock price,
    records the trade on both agents, charges both of them the trading fee and tracks it.

# Params
- `book` - the orderbook in which the trade happens
- `buyer` - the agent who buys the shares
- `seller` - the agent who sells the shares
- `shares` - the shares which are traded
- `stock` - the stock of the shares
- `price` - the price of a single share
"""
function execute_trade!(book::OrderBook, buyer::BaseAgent, seller::BaseAgent, shares::Vector{Share}, stock::Stock, price::Float64)::OrderBook
    book.ticker += 1

    #updates the stock price
    record_latest_value!(stock, price)
    push!(book.mean_prices[stock], price)

    #records the orders on the agent sides
    _ , sold_shares = record_sell_order!(seller, shares, stock)
    record_buy_order!(buyer, sold_shares, stock)

    #the buyer and the seller each pay the fee on the volume of the trade
    fee = length(sold_shares) * price * book.fee_rate
    pay_fee!(buyer, fee)
    pay_fee!(seller, fee)
    book.fees_collected += 2 * fee

    #tracks trade
    track_trade!(book, buyer.id, seller.id, sold_shares, price, book.ticker)

    return book
end

"""
adds a buy order to the orderbook. It tries to match it directly against the open sell orders,
whatever can't be matched is added to the order book. It also directly updates the stock price

# Fields
- `book` - the order book which contains the orders
- `quantity` - how many shares of the stock to buy
- `stock` - the stock which the agent wants to buy the shares from
- `max_price` - the maximum price the agent wants to pay for a single share
- `buyer` - the agent who placed the order
"""
function place_buy_order!(book::OrderBook, quantity::Int, stock::Stock, max_price::Float64, buyer::BaseAgent)::OrderBook
    #checks if buyer can afford the shares and the fee
    if quantity <= 0 || max_price <= 0 || buyer.cash < max_price * quantity * (1 + book.fee_rate); return book; end

    #putting up an order is a tick
    book.ticker += 1
    order = BuyOrder(quantity, buyer, stock, book.ticker, max_price)
    sell_orders = book.sell_orders[stock]

    i = 1
    while order.quantity > 0 && i <= length(sell_orders)
        sell_order = sell_orders[i]

        #orders are sorted, if this one is too expensive all following ones are too
        if sell_order.min_price > order.max_price; break; end

        #skips own orders
        if sell_order.owner.id == buyer.id; i += 1; continue; end

        #removes shares the seller doesn't own anymore
        filter!(share -> share.owner_id == sell_order.owner.id, sell_order.shares)
        if isempty(sell_order.shares); deleteat!(sell_orders, i); continue; end

        #the trade happens at the price of the resting order
        price = sell_order.min_price
        amount = min(order.quantity, length(sell_order.shares), affordable_quantity(book, buyer, price))
        if amount == 0; break; end

        traded_shares = splice!(sell_order.shares, 1:amount)
        execute_trade!(book, buyer, sell_order.owner, traded_shares, stock, price)
        order.quantity -= amount

        #deletes fulfilled sell order
        if isempty(sell_order.shares); deleteat!(sell_orders, i); end
    end

    #add the rest of the order to the buy orders
    if order.quantity > 0
        buy_orders = book.buy_orders[stock]
        insert!(buy_orders, searchsortedlast(buy_orders, order; by = buy_order_key) + 1, order)
    end

    return book
end

"""
The function places a sell order and tries to match it directly against the open buy orders,
if the seller is able to place that order. Whatever can't be matched is added to the order book.
It updates the stock price.

# Fields
- `book`- the book in which the order should be matched
- `shares` - the shares to sell
- `stock` - the stock of which the shares are
- `min_price` - the minimum price for one share
- `seller` - the agent who sold the item
"""
function place_sell_order!(book::OrderBook, shares::Vector{Share}, stock::Stock, min_price::Float64, seller::BaseAgent)::OrderBook
    if isempty(shares) || min_price <= 0; return book; end

    #checks if the seller owns the shares he wants to place
    for share in shares
         share.owner_id == seller.id ? continue : return book
    end

    #putting up an order is a tick
    book.ticker += 1

    #copies the shares so the order doesn't share the vector with the holdings of the agent
    order = SellOrder(copy(shares), stock, seller, book.ticker, min_price)
    buy_orders = book.buy_orders[stock]

    i = 1
    while !isempty(order.shares) && i <= length(buy_orders)
        buy_order = buy_orders[i]

        #orders are sorted, if this one is too cheap all following ones are too
        if buy_order.max_price < order.min_price; break; end

        #skips own orders
        if buy_order.new_owner.id == seller.id; i += 1; continue; end

        #the trade happens at the price of the resting order
        price = buy_order.max_price
        amount = min(buy_order.quantity, length(order.shares), affordable_quantity(book, buy_order.new_owner, price))

        #deletes the buy order if the buyer can't afford it anymore
        if amount == 0; deleteat!(buy_orders, i); continue; end

        traded_shares = splice!(order.shares, 1:amount)
        execute_trade!(book, buy_order.new_owner, seller, traded_shares, stock, price)
        buy_order.quantity -= amount

        #deletes fulfilled buy order
        if buy_order.quantity == 0; deleteat!(buy_orders, i); end
    end

    #puts the rest of the order into waiting
    if !isempty(order.shares)
        sell_orders = book.sell_orders[stock]
        insert!(sell_orders, searchsortedlast(sell_orders, order; by = sell_order_key) + 1, order)
    end

    return book
end

"""
    Cancels all open orders of an agent.

# Params
- `book` - the orderbook which contains the orders
- `agent` - the agent whose orders are cancelled
"""
function cancel_orders!(book::OrderBook, agent::BaseAgent)::OrderBook
    for stock in keys(book.buy_orders)
        cancel_orders!(book, agent, stock)
    end

    return book
end

"""
    Cancels all open orders of an agent for one stock.

# Params
- `book` - the orderbook which contains the orders
- `agent` - the agent whose orders are cancelled
- `stock` - the stock of which the orders are cancelled
"""
function cancel_orders!(book::OrderBook, agent::BaseAgent, stock::Stock)::OrderBook
    filter!(order -> order.new_owner.id != agent.id, book.buy_orders[stock])
    filter!(order -> order.owner.id != agent.id, book.sell_orders[stock])

    return book
end

"""
    Removes all orders which are older than the lifetime of an order.

# Params
- `book` - the orderbook which contains the orders
- `order_lifetime` - how many ticks an order stays in the orderbook
"""
function remove_expired_orders!(book::OrderBook, order_lifetime::Int)::OrderBook
    oldest_tick = book.ticker - order_lifetime

    for stock in keys(book.buy_orders)
        filter!(order -> order.tick > oldest_tick, book.buy_orders[stock])
        filter!(order -> order.tick > oldest_tick, book.sell_orders[stock])
    end

    return book
end

"""
    Returns the latest mean price of a stock.

# Params
- `book` - the orderbook which contains the mean prices
- `stock` - the stock to get the mean price of
"""
function get_mean_price(book::OrderBook, stock::Stock)::Float64
    return last(book.mean_prices[stock])
end

"""
    Checks if the prices went into one direction for the last n ticks the stock was traded.
    A trade where the price is unchanged breaks the streak.

    Returns `:up` if the price strictly increased on each of the last n trades,
    `:down` if it strictly decreased and `:none` otherwise.

# Params
- `prices` - the prices of a stock, one for every tick it was traded
- `n` - for how many ticks the price has to go into one direction
"""
function detect_streak(prices::Vector{Float64}, n::Int)::Symbol
    if n <= 0 || length(prices) < n + 1; return :none; end

    last_prices = @view prices[end-n:end]
    diffs = diff(last_prices)

    if all(>(0), diffs); return :up; end
    if all(<(0), diffs); return :down; end

    return :none
end
