local function sendReply(msg, data)
    msg.reply({Data = data, Action = msg.Action .. "Response"})
end




-- Helper function to generate UUID-like strings
local function generate_uuid()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

-- Validate order based on current state
local function validate_order(state, action, quantity, price)
    if action == Action.BUY then
        return state.balance >= quantity * price
    elseif action == Action.SELL then
        return state.holdings >= quantity
    end
    return false
end



