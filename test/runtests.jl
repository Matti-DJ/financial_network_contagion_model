using Test
using Random
using Financial_network_contagion_model
const M = Financial_network_contagion_model

#creates an orderbook with one stock and two zero intelligence agents
function test_market()
    book = M.OrderBook()
    stock = M.Stock("stock1", 100.0)
    M.add_stock!(book, stock)

    buyer = M.ZeroIntelligenceAgent(M.base_fields(1, 10_000.0)...)
    seller = M.ZeroIntelligenceAgent(M.base_fields(2, 0.0)...)

    shares = [M.Share(M.uuid4(), stock.name, 2) for _ in 1:10]
    seller.holdings[stock] = copy(shares)

    return book, stock, buyer, seller, shares
end

@testset "Financial_network_contagion_model tests" begin
    @testset "order matching" begin
        book, stock, buyer, seller, shares = test_market()

        #sell order rests, buy order partially fills it at the resting price
        M.place_sell_order!(book, shares, stock, 90.0, seller)
        @test length(book.sell_orders[stock]) == 1
        @test book.ticker == 1
        M.place_buy_order!(book, 4, stock, 95.0, buyer)

        #the buy order and the trade are a tick each
        @test book.ticker == 3
        @test book.trades[1].tick == 3
        @test book.mean_prices[stock] == [100.0, 90.0]

        @test length(book.trades) == 1
        @test stock.latest_value == 90.0
        @test length(buyer.holdings[stock]) == 4
        @test length(seller.holdings[stock]) == 6
        @test all(share -> share.owner_id == buyer.id, buyer.holdings[stock])
        @test buyer.cash ≈ 10_000.0 - 4 * 90.0
        @test seller.cash ≈ 4 * 90.0
        @test length(first(book.sell_orders[stock]).shares) == 6
        @test isempty(book.buy_orders[stock])

        #buy order which is too cheap rests on the book
        M.place_buy_order!(book, 2, stock, 50.0, buyer)
        @test length(book.buy_orders[stock]) == 1

        #self trades are skipped
        M.place_sell_order!(book, buyer.holdings[stock][1:1], stock, 40.0, buyer)
        @test length(book.trades) == 1

        #an order which can't be placed is not a tick, cancelling isn't either
        ticker = book.ticker
        M.place_buy_order!(book, 1_000, stock, 95.0, buyer)
        @test book.ticker == ticker

        #cancel removes all orders of an agent
        M.cancel_orders!(book, buyer)
        @test book.ticker == ticker
        @test isempty(book.buy_orders[stock])
        @test length(book.sell_orders[stock]) == 1
    end

    @testset "price time priority" begin
        book, stock, buyer, seller, shares = test_market()

        M.place_sell_order!(book, shares[1:2], stock, 100.0, seller)
        M.place_sell_order!(book, shares[3:4], stock, 99.0, seller)
        M.place_sell_order!(book, shares[5:6], stock, 99.0, seller)

        orders = book.sell_orders[stock]
        @test [order.min_price for order in orders] == [99.0, 99.0, 100.0]
        @test orders[1].shares == shares[3:4]
    end

    @testset "streak" begin
        @test M.detect_streak([1.0, 2.0, 3.0, 4.0], 3) == :up
        @test M.detect_streak([4.0, 3.0, 2.0, 1.0], 3) == :down
        @test M.detect_streak([1.0, 2.0, 2.0, 3.0], 3) == :none
        @test M.detect_streak([1.0, 2.0], 3) == :none
    end

    @testset "simulation" begin
        Random.seed!(42)
        config = SimulationConfig(shares_per_stock = 200, stocks = 3, tick_limit = 20_000,
            ia = 5, mma = 2, ma = 10, rma = 10, zia = 50, bsa = 20, ma_rma_direction = 3)
        sim = init_simulation(config)

        #every share is owned by at most one agent and the holdings match the owners
        for agent in sim.agents, (stock, shares) in agent.holdings
            @test all(share -> share.owner_id == agent.id, shares)
        end

        total_cash = sum(agent.cash for agent in sim.agents)
        total_shares = sum(length(shares) for agent in sim.agents for shares in values(agent.holdings))

        stats = run_simulation!(sim)
        #the last agent can put up a few orders after the limit is reached, then the simulation stops
        @test 20_000 <= stats.ticks < 20_100
        @test stats.rounds > 1
        @test length(stats.trades) > 0

        #every tick is either an order or a trade, the trades have increasing ticks
        @test issorted([trade.tick for trade in stats.trades])
        @test all(stock -> length(stats.mean_prices[stock.name]) == stock.times_traded + 1, stats.stocks)

        #no cash or shares are created or lost and no agent has negative cash
        @test sum(agent.cash for agent in sim.agents) ≈ total_cash
        @test sum(length(shares) for agent in sim.agents for shares in values(agent.holdings)) == total_shares
        @test all(agent -> agent.cash >= -1e-6, sim.agents)

        #the report prints every stock and agent type
        @test [stock.name for stock in stats.stocks] == ["stock1", "stock2", "stock3"]
        @test length(stats.agents) == 6
        io = IOBuffer()
        print_stats(stats, io)
        report = String(take!(io))
        @test occursin("SIMULATION RESULTS", report)
        @test all(stock -> occursin(stock.name, report), stats.stocks)
        @test occursin("ZeroIntelligenceAgent", report)
        @test M.format_number(1234567.891) == "1,234,567.89"
        @test M.format_number(-0.004) == "0.00"
        @test M.format_percent(-12.346) == "-12.35%"

        #the price history starts at the init value and has a point for every trade
        for stock in stats.stocks
            history = stats.price_history[stock.name]
            @test history.ticks[1] == 0 && history.prices[1] == stock.init_value
            @test length(history.ticks) == stock.times_traded + 1
            @test issorted(history.ticks)
            @test last(history.prices) == stock.latest_value
        end

        #the interactive plots are saved as html without opening the browser
        mktempdir() do dir
            plot_stocks(stats; path = joinpath(dir, "stocks.html"), open_browser = false)
            plot_stock_overview(stats; path = joinpath(dir, "overview.html"), open_browser = false, max_points = 100)
            plot_stock(stats, "stock1"; path = joinpath(dir, "stock1.html"), open_browser = false)
            for file in ("stocks.html", "overview.html", "stock1.html")
                html = read(joinpath(dir, file), String)
                @test occursin("plotly", html)
                @test occursin("stock1", html)
            end
        end

        #every stock gets its own plot with the title of that stock
        figure = plot_stocks(stats; open_browser = false)
        @test length(figure.data) == length(stats.stocks)
        titles = [annotation[:text] for annotation in figure.layout[:annotations] if occursin("stock", string(annotation[:text]))]
        @test titles == [M.stock_title(stock) for stock in stats.stocks]
        thinned = M.thin_history(stats.price_history["stock1"], 50)
        @test length(thinned.ticks) <= 51
        @test last(thinned.ticks) == last(stats.price_history["stock1"].ticks)

        #every share is still owned by exactly the agent which holds it
        owners = Dict{M.Share,Int}()
        for agent in sim.agents, (stock, shares) in agent.holdings, share in shares
            @test !haskey(owners, share)
            owners[share] = agent.id
            @test share.owner_id == agent.id
        end
    end
end
