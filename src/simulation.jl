# simulation.jl
# Julia Script

#=
Description: Runs the simulation and contains the behaviour of each agent.
Author: matthiasdejong
Date: 25.09.26
=#

const SCRIPT_VERSION = "1.3.0"

"""
Config of the simulation.

# Fields

- `shares_per_stock` - how many shares there should be of each stock, ±1%
- `stocks` - how many stock to simulate
- `tick_limit` - how many ticks the simulation will run for, a tick is an order which is put up or a trade which is executed

- `ia` - amount of informed agents, ±1%
- `mma` - amount of market maker agents, ±1%
- `ma` - amount of momentum agents, ±1%
- `rma` - amount of reverse momentum agents, ±1%
- `zia` - amount of zero intelligence agents, ±1%
- `bsa` - amount of biased stochastic agents, ±1%

- `ia_sc` - informed agent starting cash, ±5%
- `mma_sc` - market maker agent starting cash, ±5%
- `ma_sc` - momentum agent starting cash, ±5%
- `rma_sc` - reverse momentum agent starting cash, ±5%
- `zia_sc` - zero intelligence agent starting cash, ±5%
- `bsa_sc` - biased stochastic agent starting cash, ±5%

- `ia_ssp` - informed agent starting share percentage, ±5%
- `mma_ssp` - market maker starting share percentage, ±5%
- `ma_ssp` - momentum agent starting share percentage, ±5%
- `rma_ssp` - reverse momentum agent starting share percentage, ±5%
- `zia_ssp` - zero intelligence agent starting share percentage, ±5%
- `bsa_ssp` - biased stochastic agent starting share percentage, ±5%

- `mma_reprice` - how many ticks it takes for the market maker to set new prices
- `ma_rma_direction` - for how many trades in a row a stock has to go into one direction for them to act

- `ia_noise` - how far the perceived value of the informed agent drifts from the init value, in percent
- `ia_smoothing_rate` - how much weight a fresh reading gets vs. the running estimate of the informed agent
- `bsa_own_weight` - how much the own standard factor of the biased stochastic agent counts vs. the population
- `bsa_factor_std` - the standard deviation of the gaussian the biased stochastic agent draws its factor from
- `zia_price_range` - the zero intelligence agent prices between latest value × (1 ± zia_price_range)

- `trade_fraction` - the fraction of cash / shares an agent uses in a single order
- `order_lifetime` - after how many ticks an open order / loan offer is removed from the orderbook / loan book

- `interest_rate` - the interest a borrower pays on a loan, 0.1 = 10%
- `loan_term` - after how many ticks a loan has to be repaid
- `max_debt_ratio` - an agent can't borrow more than this × its net worth

- `trade_fee` - the fee the buyer and the seller each pay on the volume of a trade, 0.001 = 0.1%
- `loan_fee` - the origination fee a borrower pays on the principal of a loan, 0.01 = 1%
"""
Base.@kwdef struct SimulationConfig
    shares_per_stock::Int = 1_000
    stocks::Int = 10
    tick_limit::Int = 1_000_000

    ia::Int = 1
    mma::Int = 5
    ma::Int = 100
    rma::Int = 100
    zia::Int = 500
    bsa::Int = 200

    ia_sc::Float64 = 500_000.0
    mma_sc::Float64 = 2_000_000.0
    ma_sc::Float64 = 50_000.0
    rma_sc::Float64 = 50_000.0
    zia_sc::Float64 = 10_000.0
    bsa_sc::Float64 = 25_000.0

    ia_ssp::Float64 = 15.0
    mma_ssp::Float64 = 30.0
    ma_ssp::Float64 = 5.0
    rma_ssp::Float64 = 5.0
    zia_ssp::Float64 = 15.0
    bsa_ssp::Float64 = 30.0

    mma_reprice::Int = 20
    ma_rma_direction::Int = 10

    ia_noise::Float64 = 5.0
    ia_smoothing_rate::Float64 = 0.1
    bsa_own_weight::Float64 = 0.5
    bsa_factor_std::Float64 = 0.02
    zia_price_range::Float64 = 0.5

    trade_fraction::Float64 = 0.1
    order_lifetime::Int = 75_000

    interest_rate::Float64 = 0.1
    loan_term::Int = 10_000
    max_debt_ratio::Float64 = 0.5

    trade_fee::Float64 = 0.001
    loan_fee::Float64 = 0.01
end

"""

# Fields
- `config` - the config of the simulation
- `agents` - all agents in the simulation
- `stocks` - all stocks in the simulation with all their shares
- `agent_types` - all types of agents there are
- `orderbook` - the orderbook used in the simulation
- `loanbook` - the loan book which tracks all loans between agents
- `population_standard_factor` - the average standard factor of all biased stochastic agents
- `starting_wealth` - the net worth of every agent at the start: Dict{agent id, net worth}
- `rounds` - how many rounds were simulated, in a round every agent acts once
"""
mutable struct Simulation
    config::SimulationConfig
    agents::Vector{BaseAgent}
    stocks::Dict{Stock,Vector{Share}}
    agent_types::Vector{Symbol}
    orderbook::OrderBook
    loanbook::LoanBook
    population_standard_factor::Float64
    starting_wealth::Dict{Int,Float64}
    rounds::Int
end

Simulation(config::SimulationConfig) = Simulation(config, BaseAgent[], Dict{Stock,Vector{Share}}(), Symbol[], OrderBook(config.trade_fee),
    LoanBook(config.interest_rate, config.loan_term, config.loan_fee), 1.0, Dict{Int,Float64}(), 0)
Simulation() = Simulation(SimulationConfig())

"""
    Returns a value randomly changed by ± a fraction e.g. vary(100.0, 0.05) returns a value between 95 and 105
"""
vary(value::Float64, fraction::Float64)::Float64 = value * (1 - fraction + 2 * fraction * rand())

"""
    Creates all stocks and their shares.
"""
function init_stocks!(sim::Simulation, sim_conf::SimulationConfig)::Simulation

    for i in (1:sim_conf.stocks)
        starting_value = 1 + 999 * rand()
        stock = Stock("stock$i", starting_value)

        shares = create_list_of_shares!(sim, sim_conf, stock)
        stock.total_shares = length(shares)

        sim.stocks[stock] = shares
        add_stock!(sim.orderbook, stock)
    end

    return sim
end

"""
    Creates all shares of a stock, the amount is shares_per_stock ±1%
"""
function create_list_of_shares!(sim::Simulation, sim_config::SimulationConfig, stock::Stock)::Vector{Share}
    amount = round(Int, vary(Float64(sim_config.shares_per_stock), 0.01))
    shares_for_stock::Vector{Share} = Share[]

    for i in (1:amount)
        share = Share(uuid4(), stock.name, 0)
        push!(shares_for_stock, share)
    end

    return shares_for_stock
end

"""
    Creates all agents of every type, the amount of each type is ±1%, the starting cash ±5%.
"""
function init_agents!(sim::Simulation, sim_conf::SimulationConfig)::Simulation
    next_id = 1

    agent_counts = [
        (:InformedAgent, sim_conf.ia, sim_conf.ia_sc),
        (:MarketMakerAgent, sim_conf.mma, sim_conf.mma_sc),
        (:MomentumAgent, sim_conf.ma, sim_conf.ma_sc),
        (:ReverseMomentumAgent, sim_conf.rma, sim_conf.rma_sc),
        (:ZeroIntelligenceAgent, sim_conf.zia, sim_conf.zia_sc),
        (:BiasedStochasticAgent, sim_conf.bsa, sim_conf.bsa_sc),
    ]

    for (agent_type, count, starting_cash) in agent_counts
        push!(sim.agent_types, agent_type)

        for _ in (1:round(Int, vary(Float64(count), 0.01)))
            agent = create_agent(sim, agent_type, next_id, vary(starting_cash, 0.05))
            push!(sim.agents, agent)
            next_id += 1
        end
    end

    return sim
end

"""
    Creates a single agent of a type.

# Params
- `sim` - the simulation the agent is created for
- `agent_type` - the type of the agent
- `id` - the id of the agent
- `cash` - the starting cash of the agent
"""
function create_agent(sim::Simulation, agent_type::Symbol, id::Int, cash::Float64)::BaseAgent
    conf = sim.config
    base = base_fields(id, cash)

    if agent_type == :InformedAgent
        predicted_high = Dict(stock => stock.init_value * (1 + conf.ia_noise / 100) for stock in keys(sim.stocks))
        predicted_low = Dict(stock => stock.init_value * (1 - conf.ia_noise / 100) for stock in keys(sim.stocks))
        arm_reward = Dict(stock => Dict(arm => 0.0 for arm in instances(Decision)) for stock in keys(sim.stocks))
        arm_visits = Dict(stock => Dict(arm => 0 for arm in instances(Decision)) for stock in keys(sim.stocks))
        loan_arm_reward = Dict(arm => 0.0 for arm in instances(LoanDecision))
        loan_arm_visits = Dict(arm => 0 for arm in instances(LoanDecision))

        return InformedAgent(base..., predicted_high, predicted_low, conf.ia_smoothing_rate, conf.ia_noise,
            arm_reward, arm_visits, 0, cash, HOLD, nothing, loan_arm_reward, loan_arm_visits, 0, cash, nothing)
    elseif agent_type == :MarketMakerAgent
        return MarketMakerAgent(base..., Dict{Stock,Float64}(), Dict{Stock,Float64}(), Dict{Stock,Float64}(),
            Dict{Stock,Float64}(), Dict{Stock,Float64}(), Dict{Stock,Float64}(), -conf.mma_reprice)
    elseif agent_type == :MomentumAgent
        return MomentumAgent(base..., conf.ma_rma_direction)
    elseif agent_type == :ReverseMomentumAgent
        return ReverseMomentumAgent(base...)
    elseif agent_type == :ZeroIntelligenceAgent
        return ZeroIntelligenceAgent(base...)
    elseif agent_type == :BiasedStochasticAgent
        return BiasedStochasticAgent(base..., 1.0, 1.0, conf.bsa_own_weight, 0)
    end

    error("unknown agent type $agent_type")
end

"""
    Distributes the shares of every stock among the agents. Each agent type gets its starting share percentage ±5%
    of every stock, those shares are split randomly among the agents of that type.
    Shares which are left over stay unowned and are not part of the market.
"""
function distribute_shares!(sim::Simulation, sim_conf::SimulationConfig)::Simulation
    share_percentages = Dict(
        :InformedAgent => sim_conf.ia_ssp,
        :MarketMakerAgent => sim_conf.mma_ssp,
        :MomentumAgent => sim_conf.ma_ssp,
        :ReverseMomentumAgent => sim_conf.rma_ssp,
        :ZeroIntelligenceAgent => sim_conf.zia_ssp,
        :BiasedStochasticAgent => sim_conf.bsa_ssp,
    )

    #groups the agents by type
    agents_by_type = Dict(agent_type => BaseAgent[] for agent_type in sim.agent_types)
    for agent in sim.agents
        push!(agents_by_type[nameof(typeof(agent))], agent)
    end

    for (stock, shares) in sim.stocks
        remaining_shares = shuffle(shares)

        for agent_type in sim.agent_types
            agents = agents_by_type[agent_type]
            if isempty(agents); continue; end

            amount = round(Int, vary(share_percentages[agent_type], 0.05) / 100 * length(shares))
            amount = min(amount, length(remaining_shares))

            for share in splice!(remaining_shares, 1:amount)
                agent = rand(agents)
                assign_new_owner!(share, agent.id)
                push!(get!(agent.holdings, stock, Share[]), share)
            end
        end
    end

    return sim
end

"""
    Initialises the whole simulation: stocks, shares, agents and distributes the shares.
"""
function init_simulation(sim_conf::SimulationConfig = SimulationConfig())::Simulation
    sim = Simulation(sim_conf)

    init_stocks!(sim, sim_conf)
    init_agents!(sim, sim_conf)
    distribute_shares!(sim, sim_conf)

    #the wealth is measured after the agents got their shares
    for agent in sim.agents
        sim.starting_wealth[agent.id] = net_worth(agent)
        if agent isa InformedAgent
            agent.latest_wealth = net_worth(agent)
            agent.latest_loan_wealth = net_worth(agent)
        end
    end

    return sim
end

"""
    Updates the average standard factor of all biased stochastic agents.
"""
function update_population_standard_factor!(sim::Simulation)::Simulation
    factors = [agent.agent_standard_factor for agent in sim.agents if agent isa BiasedStochasticAgent]
    if !isempty(factors); sim.population_standard_factor = mean(factors); end

    return sim
end

"""
    Runs a single round: removes old orders and loan offers, shuffles the agents so no agent type gets a systematic
    advantage and lets every agent act once. An agent first decides to borrow / lend and then trades.
    Loans which are due are settled before every agent acts. The ticker is not advanced here, it increases in the
    orderbook with every order which is put up and every trade which is executed, loans don't advance it.
    The round stops as soon as the tick limit is reached.
"""
function simulation_step!(sim::Simulation)::Simulation
    book = sim.orderbook
    loans = sim.loanbook

    sim.rounds += 1
    remove_expired_orders!(book, sim.config.order_lifetime)
    remove_expired_loan_offers!(loans, book.ticker, sim.config.order_lifetime)
    update_population_standard_factor!(sim)

    shuffle!(sim.agents)
    for agent in sim.agents
        if book.ticker >= sim.config.tick_limit; break; end
        settle_due_loans!(loans, book.ticker)
        loan_step!(agent, sim)
        agent_step!(agent, sim)
    end

    return sim
end

"""
    Runs the simulation until the tick limit is reached and returns the collected stats.
    Stops early if a whole round passes without a single tick, then nobody can trade anymore.
"""
function run_simulation!(sim::Simulation)::NamedTuple
    book = sim.orderbook

    runtime = @elapsed while book.ticker < sim.config.tick_limit
        ticker_before = book.ticker
        simulation_step!(sim)
        if book.ticker == ticker_before; break; end
    end

    return merge(collect_stats(sim), (runtime = runtime,))
end

"""
    Initialises and runs a simulation with a config.
"""
run_simulation(sim_conf::SimulationConfig = SimulationConfig())::NamedTuple = run_simulation!(init_simulation(sim_conf))

"""
    Collects all information of the simulation.

# Returns
- `ticks` - how many ticks were simulated
- `rounds` - how many rounds were simulated
- `trades` - all trades which happened
- `shares_traded` - how many shares were traded in total
- `mean_prices` - the price of every stock at every tick it was traded: Dict{stock name, Vector{price}}
- `price_history` - the ticks and prices of every stock, starting with the init value at tick 0:
  Dict{stock name, (ticks = Vector{tick}, prices = Vector{price})}
- `stocks` - the stats of every stock, sorted by stock number
- `agents` - the stats of every agent type
- `wealth_per_type` - the average net worth of each agent type
- `loans` - the stats of all loans, see `collect_loan_stats`
- `fees` - the fee rates and all fees the agents paid for trades and loans
"""
function collect_stats(sim::Simulation)::NamedTuple
    book = sim.orderbook

    mean_prices = Dict(stock.name => prices for (stock, prices) in book.mean_prices)

    #the price of every stock at the tick of each of its trades
    price_history = Dict(stock.name => (ticks = Int[0], prices = Float64[stock.init_value]) for stock in keys(sim.stocks))
    for trade in book.trades
        if isempty(trade.shares); continue; end

        history = price_history[first(trade.shares).stock_name]
        push!(history.ticks, trade.tick)
        push!(history.prices, trade.share_price)
    end

    stocks = [(name = stock.name, init_value = stock.init_value, latest_value = stock.latest_value,
               highest_value = stock.highest_value, lowest_value = stock.lowest_value,
               change = (stock.latest_value - stock.init_value) / stock.init_value * 100,
               total_shares = stock.total_shares, times_traded = stock.times_traded) for stock in keys(sim.stocks)]

    #sorts by the number of the stock so stock10 comes after stock9
    sort!(stocks; by = stock -> parse(Int, replace(stock.name, "stock" => "")))

    agents = NamedTuple[]
    wealth_per_type = Dict{Symbol,Float64}()
    for agent_type in sim.agent_types
        agents_of_type = [agent for agent in sim.agents if nameof(typeof(agent)) == agent_type]
        if isempty(agents_of_type); continue; end

        starting_wealth = mean(sim.starting_wealth[agent.id] for agent in agents_of_type)
        wealth = mean(net_worth(agent) for agent in agents_of_type)
        wealth_per_type[agent_type] = wealth

        push!(agents, (type = agent_type, count = length(agents_of_type),
                       starting_wealth = starting_wealth, wealth = wealth,
                       change = (wealth - starting_wealth) / starting_wealth * 100,
                       cash = mean(agent.cash for agent in agents_of_type),
                       lent = mean(total_lent(agent) for agent in agents_of_type),
                       borrowed = mean(total_borrowed(agent) for agent in agents_of_type),
                       fees_paid = mean(agent.fees_paid for agent in agents_of_type),
                       shares_bought = sum(agent.shares_bought for agent in agents_of_type),
                       shares_sold = sum(agent.shares_sold for agent in agents_of_type)))
    end

    shares_traded = sum(length(trade.shares) for trade in book.trades; init = 0)

    fees = (trade_fee = book.fee_rate, loan_fee = sim.loanbook.fee_rate, trading = book.fees_collected,
            loans = sim.loanbook.fees_collected, total = book.fees_collected + sim.loanbook.fees_collected)

    return (ticks = book.ticker, rounds = sim.rounds, trades = book.trades, shares_traded = shares_traded, mean_prices = mean_prices,
            price_history = price_history,
            stocks = stocks, agents = agents, wealth_per_type = wealth_per_type, loans = collect_loan_stats(sim.loanbook),
            fees = fees)
end

"""
    Collects the stats of all loans.

# Returns
- `count` - how many loans were made
- `volume` - the principal of all loans
- `active` - how many loans aren't due yet
- `outstanding` - the principal of all loans which aren't due yet
- `settled` - how many loans were settled
- `repaid_in_full` - how many settled loans were fully paid back in cash
- `repaid` - the cash all borrowers paid back
- `interest_paid` - the cash borrowers paid on top of the principal
- `seized` - the value of the shares lenders took from borrowers who couldn't pay in cash
- `defaults` - how many loans weren't fully covered by cash and shares
- `defaulted` - the amount lenders lost in those defaults
- `fees` - the origination fees borrowers paid
- `interest_rate` - the interest of every loan
"""
function collect_loan_stats(loans::LoanBook)::NamedTuple
    settled = loans.settled_loans
    all_loans = Iterators.flatten((settled, loans.active_loans))

    return (count = length(settled) + length(loans.active_loans),
            volume = sum(loan.principal for loan in all_loans; init = 0.0),
            active = length(loans.active_loans),
            outstanding = sum(loan.principal for loan in loans.active_loans; init = 0.0),
            settled = length(settled),
            repaid_in_full = count(loan -> loan.repaid >= amount_due(loan) - 1e-9, settled),
            repaid = sum(loan.repaid for loan in settled; init = 0.0),
            interest_paid = sum(max(0.0, loan.repaid - loan.principal) for loan in settled; init = 0.0),
            seized = sum(loan.seized for loan in settled; init = 0.0),
            defaults = count(loan -> loan.defaulted > 0, settled),
            defaulted = sum(loan.defaulted for loan in settled; init = 0.0),
            fees = loans.fees_collected,
            interest_rate = loans.interest_rate)
end
