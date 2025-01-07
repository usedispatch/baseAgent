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

-- DCA Strategy Configuration
local DCA_CONFIG = {
    investment_amount = 100,  -- Fixed amount to invest each time
    min_price_change = 0.02,  -- Minimum price change (2%) to trigger a buy
    max_single_investment = 500  -- Maximum amount for a single investment
}

local last_trade_price = nil

local function should_trade(current_price)
    if not last_trade_price then
        last_trade_price = current_price
        return Action.BUY
    end

    -- Calculate price change percentage
    local price_change = (current_price - last_trade_price) / last_trade_price

    -- Buy when price drops by the minimum threshold
    if price_change <= -DCA_CONFIG.min_price_change then
        last_trade_price = current_price
        return Action.BUY
    end

    return nil
end

local function calculate_quantity(action, current_price)
    if action == Action.BUY then
        -- Calculate quantity based on fixed investment amount
        local investment = math.min(DCA_CONFIG.investment_amount, DCA_CONFIG.max_single_investment)
        return math.floor(investment / current_price * 100) / 100  -- Round to 2 decimal places
    end
    return 0
end