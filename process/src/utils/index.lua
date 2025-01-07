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

-- Value Averaging Strategy Configuration
local VA_CONFIG = {
    target_monthly_increase = 1000,  -- Target value increase per month in dollars
    max_single_investment = 5000,    -- Maximum single investment
    min_single_investment = 100,     -- Minimum single investment
}

-- Strategy state
local start_time = nil
local holdings = 0
local last_check_time = 0

-- Helper functions
local function get_target_value()
    if not start_time then
        start_time = os.time()
        return VA_CONFIG.target_monthly_increase
    end
    
    local current_time = os.time()
    local elapsed_seconds = current_time - start_time
    local months_elapsed = math.floor(elapsed_seconds / (30 * 24 * 60 * 60))
    
    return VA_CONFIG.target_monthly_increase * (months_elapsed + 1)
end

local function get_current_value(current_price)
    return holdings * current_price
end

local function should_trade(current_price)
    local current_time = os.time()
    
    -- Check at least once per day
    if current_time - last_check_time < 24 * 60 * 60 then
        return nil
    end
    
    last_check_time = current_time
    
    -- Calculate the difference between target and current value
    local target_value = get_target_value()
    local current_value = get_current_value(current_price)
    local value_difference = target_value - current_value
    
    -- Only trade if the difference is significant
    if math.abs(value_difference) < VA_CONFIG.min_single_investment then
        return nil
    end
    
    return value_difference > 0 and "BUY" or "SELL"
end

local function calculate_quantity(action, current_price)
    local target_value = get_target_value()
    local current_value = get_current_value(current_price)
    local value_difference = math.abs(target_value - current_value)
    
    -- Limit the investment size
    value_difference = math.min(value_difference, VA_CONFIG.max_single_investment)
    
    local quantity = value_difference / current_price
    
    if action == "SELL" then
        -- Don't sell more than we have
        quantity = math.min(quantity, holdings)
    end
    
    -- Update holdings
    if action == "BUY" then
        holdings = holdings + quantity
    else
        holdings = holdings - quantity
    end
    
    -- Round to 2 decimal places
    return math.floor(quantity * 100) / 100
end