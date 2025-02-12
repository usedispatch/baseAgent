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



local last_trade_price = nil

local function should_trade(current_price)
    -- Check if we've reached the total number of orders
    if DCA_CONFIG.orders_executed >= DCA_CONFIG.total_orders then
        return nil
    end

    -- Check if enough time has passed since last order
    local current_time = os.time()
    if current_time - DCA_CONFIG.last_order_time < DCA_CONFIG.interval_seconds then
        return nil
    end

    -- Update last trade time and increment order count
    DCA_CONFIG.last_order_time = current_time
    DCA_CONFIG.orders_executed = DCA_CONFIG.orders_executed + 1
    return Action.BUY
end

local function calculate_quantity(action, current_price)
    if action == Action.BUY then
        -- Calculate quantity based on fixed investment amount
        local investment = math.min(DCA_CONFIG.investment_amount, DCA_CONFIG.max_single_investment)
        return math.floor(investment / current_price * 100) / 100  -- Round to 2 decimal places
    end
    return 0
end