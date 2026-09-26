# Share.jl
# Julia Script

#=
Description: The share is a part of the stock which is traded among the agents. The share itself does not have a
value, only the Stock has.

Author: matthiasdejong
Date: 19.09.26
=#

const SCRIPT_VERSION = "1.0.0"

"""
# Fields
- `id` - the id of the share
- `stock_name` - the name of the stock this share belongs to
- `owner_id` - the id of the agent currently holding this share, 0 if nobody owns it
"""
mutable struct Share
    id::UUID
    stock_name::String
    owner_id::Int
end

Share() = Share(uuid4(), "", 0)

"""
    assigns a new_owner to the share
"""
function assign_new_owner!(share::Share, new_owner_id::Int)::Share
    share.owner_id = new_owner_id
    return share
end

"""
    assigns a stock to the share
"""
function assign_stock_name!(share::Share, stock_name::String)::Share
    share.stock_name = stock_name
    return share
end
