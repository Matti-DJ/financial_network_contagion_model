# LoanBook.jl
# Julia Script

#=
Description: keeps track of lend offers, borrow requests and loans between agents. Matches offers with requests
and settles the loans when they are due. The interest rate is fixed, so offers are matched by time only.
Author: matthiasdejong
Date: 27.09.26
=#

const SCRIPT_VERSION = "1.0.0"

#loans smaller than this are not made
const MIN_LOAN = 1.0

"""
    An open lend offer or borrow request of an agent.

# Fields
- `amount` - how much cash the agent wants to lend / borrow
- `agent` - the agent who placed the offer
- `tick` - at which tick the offer was placed
"""
mutable struct LoanOffer
    amount::Float64
    agent::BaseAgent
    tick::Int
end

"""
# Fields
- `id` - the id of the loan
- `lender` - the agent who lent the cash
- `borrower` - the agent who borrowed the cash
- `principal` - how much cash was lent
- `interest_rate` - the interest the borrower pays on the principal, 0.1 = 10%
- `tick` - at which tick the loan was made
- `due_tick` - at which tick the loan has to be repaid
- `repaid` - how much cash the borrower paid back
- `seized` - the value of the shares the lender took because the borrower couldn't pay in cash
- `defaulted` - how much of the loan was lost because the borrower couldn't pay at all
- `settled` - if the loan was settled
"""
mutable struct Loan
    id::UUID
    lender::BaseAgent
    borrower::BaseAgent
    principal::Float64
    interest_rate::Float64
    tick::Int
    due_tick::Int
    repaid::Float64
    seized::Float64
    defaulted::Float64
    settled::Bool
end

"""
    The amount the borrower has to pay back: principal + interest.
"""
amount_due(loan::Loan)::Float64 = loan.principal * (1 + loan.interest_rate)

"""
# Fields
- `lend_offers` - all open lend offers, oldest first
- `borrow_requests` - all open borrow requests, oldest first
- `active_loans` - all loans which aren't settled yet, sorted by due tick
- `settled_loans` - all loans which were settled
- `interest_rate` - the interest of every loan, 0.1 = 10%
- `loan_term` - after how many ticks a loan has to be repaid
"""
mutable struct LoanBook
    lend_offers::Vector{LoanOffer}
    borrow_requests::Vector{LoanOffer}
    active_loans::Vector{Loan}
    settled_loans::Vector{Loan}
    interest_rate::Float64
    loan_term::Int
end

LoanBook(interest_rate::Float64, loan_term::Int) = LoanBook(LoanOffer[], LoanOffer[], Loan[], Loan[], interest_rate, loan_term)
LoanBook() = LoanBook(0.1, 10_000)

"""
    Makes a loan: moves the cash from the lender to the borrower and records the debt on both sides.

# Params
- `loans` - the loan book which tracks the loan
- `lender` - the agent who lends the cash
- `borrower` - the agent who borrows the cash
- `amount` - how much cash is lent
- `tick` - at which tick the loan is made
"""
function execute_loan!(loans::LoanBook, lender::BaseAgent, borrower::BaseAgent, amount::Float64, tick::Int)::LoanBook
    lender.cash -= amount
    borrower.cash += amount

    lender.debtors[borrower.id] = get(lender.debtors, borrower.id, 0.0) + amount
    borrower.lenders[lender.id] = get(borrower.lenders, lender.id, 0.0) + amount

    loan = Loan(uuid4(), lender, borrower, amount, loans.interest_rate, tick, tick + loans.loan_term, 0.0, 0.0, 0.0, false)
    push!(loans.active_loans, loan)

    return loans
end

"""
    Places a lend offer and matches it directly against the open borrow requests, oldest first.
    Whatever can't be matched is added to the loan book. An agent only has one open offer at a time,
    placing a new one cancels its old ones.

# Params
- `loans` - the loan book
- `amount` - how much cash the agent wants to lend
- `lender` - the agent who lends
- `tick` - the current tick
"""
function place_lend_offer!(loans::LoanBook, amount::Float64, lender::BaseAgent, tick::Int)::LoanBook
    if amount < MIN_LOAN || lender.cash < amount; return loans; end
    cancel_loan_offers!(loans, lender)

    offer = LoanOffer(amount, lender, tick)
    requests = loans.borrow_requests

    i = 1
    while offer.amount >= MIN_LOAN && i <= length(requests)
        request = requests[i]

        #an agent doesn't lend to itself
        if request.agent.id == lender.id; i += 1; continue; end

        amount = min(offer.amount, request.amount)
        execute_loan!(loans, lender, request.agent, amount, tick)
        offer.amount -= amount
        request.amount -= amount

        #deletes fulfilled borrow request
        if request.amount < MIN_LOAN; deleteat!(requests, i); end
    end

    if offer.amount >= MIN_LOAN; push!(loans.lend_offers, offer); end

    return loans
end

"""
    Places a borrow request and matches it directly against the open lend offers, oldest first.
    Whatever can't be matched is added to the loan book. An agent only has one open offer at a time,
    placing a new one cancels its old ones.

# Params
- `loans` - the loan book
- `amount` - how much cash the agent wants to borrow
- `borrower` - the agent who borrows
- `tick` - the current tick
"""
function place_borrow_request!(loans::LoanBook, amount::Float64, borrower::BaseAgent, tick::Int)::LoanBook
    if amount < MIN_LOAN; return loans; end
    cancel_loan_offers!(loans, borrower)

    request = LoanOffer(amount, borrower, tick)
    offers = loans.lend_offers

    i = 1
    while request.amount >= MIN_LOAN && i <= length(offers)
        offer = offers[i]

        #an agent doesn't borrow from itself
        if offer.agent.id == borrower.id; i += 1; continue; end

        #the cash of the lender isn't reserved, it can only lend what it still has
        amount = min(request.amount, offer.amount, offer.agent.cash)

        #deletes the lend offer if the lender can't afford it anymore
        if amount < MIN_LOAN; deleteat!(offers, i); continue; end

        execute_loan!(loans, offer.agent, borrower, amount, tick)
        request.amount -= amount
        offer.amount -= amount

        #deletes fulfilled lend offer
        if offer.amount < MIN_LOAN; deleteat!(offers, i); end
    end

    if request.amount >= MIN_LOAN; push!(loans.borrow_requests, request); end

    return loans
end

"""
    Cancels all open lend offers and borrow requests of an agent.
"""
function cancel_loan_offers!(loans::LoanBook, agent::BaseAgent)::LoanBook
    filter!(offer -> offer.agent.id != agent.id, loans.lend_offers)
    filter!(request -> request.agent.id != agent.id, loans.borrow_requests)

    return loans
end

"""
    Removes all lend offers and borrow requests which are older than the lifetime of an order.

# Params
- `loans` - the loan book
- `tick` - the current tick
- `order_lifetime` - how many ticks an offer stays in the loan book
"""
function remove_expired_loan_offers!(loans::LoanBook, tick::Int, order_lifetime::Int)::LoanBook
    oldest_tick = tick - order_lifetime

    filter!(offer -> offer.tick > oldest_tick, loans.lend_offers)
    filter!(request -> request.tick > oldest_tick, loans.borrow_requests)

    return loans
end

"""
    Takes shares of the borrower and gives them to the lender until their value (at the latest value of the stock)
    covers the amount. Only whole shares are taken, so the last share can be worth more than what is left.
    Returns the value of the seized shares.

# Params
- `lender` - the agent who gets the shares
- `borrower` - the agent who gives up the shares
- `amount` - the value which should be covered
"""
function seize_shares!(lender::BaseAgent, borrower::BaseAgent, amount::Float64)::Float64
    seized = 0.0

    for (stock, shares) in borrower.holdings
        while seized < amount && !isempty(shares)
            share = pop!(shares)
            assign_new_owner!(share, lender.id)
            push!(get!(lender.holdings, stock, Share[]), share)
            seized += stock.latest_value
        end
        if seized >= amount; break; end
    end

    return seized
end

"""
    Settles a loan: the borrower pays back principal + interest in cash. If it hasn't got enough cash the lender
    seizes shares of the borrower for the rest, whatever still isn't covered is lost (a default).

# Params
- `loan` - the loan to settle
"""
function settle_loan!(loan::Loan)::Loan
    lender = loan.lender
    borrower = loan.borrower
    due = amount_due(loan)

    loan.repaid = min(max(borrower.cash, 0.0), due)
    borrower.cash -= loan.repaid
    lender.cash += loan.repaid

    rest = due - loan.repaid
    if rest > 0
        loan.seized = seize_shares!(lender, borrower, rest)
        loan.defaulted = max(0.0, rest - loan.seized)
    end

    #removes the debt from both sides
    remove_debt!(lender.debtors, borrower.id, loan.principal)
    remove_debt!(borrower.lenders, lender.id, loan.principal)
    loan.settled = true

    return loan
end

"""
    Lowers the debt of an agent in a debt dict, the entry is removed once it's paid off.
"""
function remove_debt!(debts::Dict{Int,Float64}, id::Int, amount::Float64)::Dict{Int,Float64}
    remaining = get(debts, id, 0.0) - amount
    if remaining > 1e-9
        debts[id] = remaining
    else
        delete!(debts, id)
    end

    return debts
end

"""
    Settles all loans which are due at the current tick.

# Params
- `loans` - the loan book
- `tick` - the current tick
"""
function settle_due_loans!(loans::LoanBook, tick::Int)::LoanBook
    #all loans have the same term, so the active loans are sorted by due tick
    while !isempty(loans.active_loans) && first(loans.active_loans).due_tick <= tick
        push!(loans.settled_loans, settle_loan!(popfirst!(loans.active_loans)))
    end

    return loans
end
