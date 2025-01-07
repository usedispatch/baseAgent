local Action = {
    BUY = "BUY",
    SELL = "SELL"
}

-- Value Averaging Strategy Configuration
local VA_CONFIG = {
    target_monthly_increase = 1000,  -- Target value increase per month in dollars
    max_single_investment = 5000,    -- Maximum single investment
    min_single_investment = 100,     -- Minimum single investment
    check_interval = 30 * 24 * 60 * 60,  -- Check every 30 days (in seconds)
}

-- Strategy state
local state = {
    start_time = nil,
    holdings = 0,          -- Current quantity held
    months_elapsed = 0,    -- Number of months since start
    last_check_time = 0,   -- Last time we checked for trading
}

-- Helper functions
local function get_target_value()
    if not state.start_time then
        state.start_time = os.time()
        return VA_CONFIG.target_monthly_increase
    end
    
    -- Calculate months elapsed since start
    local current_time = os.time()
    local elapsed_seconds = current_time - state.start_time
    local new_months = math.floor(elapsed_seconds / (30 * 24 * 60 * 60))
    
    -- Update state
    if new_months > state.months_elapsed then
        state.months_elapsed = new_months
    end
    
    -- Target value increases linearly each month
    return VA_CONFIG.target_monthly_increase * (state.months_elapsed + 1)
end

local function get_current_value(current_price)
    return state.holdings * current_price
end

local function calculate_investment_needed(current_price)
    local target_value = get_target_value()
    local current_value = get_current_value(current_price)
    return target_value - current_value
end

-- Strategy Implementation
local strategy = {
    should_trade = function(current_price)
        local current_time = os.time()
        
        -- Only check at specified intervals
        if current_time - state.last_check_time < VA_CONFIG.check_interval then
            return nil
        end
        
        state.last_check_time = current_time
        local investment_needed = calculate_investment_needed(current_price)
        
        -- Determine if we need to buy or sell
        if math.abs(investment_needed) < VA_CONFIG.min_single_investment then
            return nil
        elseif investment_needed > 0 then
            return Action.BUY
        else
            return Action.SELL
        end
    end,
    
    calculate_quantity = function(action, current_price)
        local investment_needed = calculate_investment_needed(current_price)
        local quantity
        
        if action == Action.BUY then
            -- Limit maximum investment
            investment_needed = math.min(investment_needed, VA_CONFIG.max_single_investment)
            quantity = investment_needed / current_price
        else  -- SELL
            -- Convert negative investment needed to positive quantity
            investment_needed = math.abs(investment_needed)
            investment_needed = math.min(investment_needed, VA_CONFIG.max_single_investment)
            quantity = investment_needed / current_price
            
            -- Don't sell more than we have
            quantity = math.min(quantity, state.holdings)
        end
        
        -- Update holdings
        if action == Action.BUY then
            state.holdings = state.holdings + quantity
        else
            state.holdings = state.holdings - quantity
        end
        
        -- Round to 2 decimal places
        return math.floor(quantity * 100) / 100
    end,
    
    -- Additional helper functions for external use
    get_state = function()
        return {
            holdings = state.holdings,
            months_elapsed = state.months_elapsed,
            target_value = get_target_value(),
            start_time = state.start_time
        }
    end,
    
    reset = function()
        state = {
            start_time = nil,
            holdings = 0,
            months_elapsed = 0,
            last_check_time = 0
        }
    end
}

return strategy