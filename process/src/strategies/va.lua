local BaseStrategy = require('strategies.base')
local Logger = require('lib.logger')

local VAStrategy = setmetatable({}, { __index = BaseStrategy })
VAStrategy.__index = VAStrategy

function VAStrategy.new(config)
    local self = BaseStrategy.new(config)
    setmetatable(self, VAStrategy)
    
    -- Initialize VA specific state
    self.start_time = os.time()
    self.months_elapsed = 0
    self.last_check_time = 0
    
    return self
end

function VAStrategy:get_target_value()
    return self.config.target_monthly_increase * self.months_elapsed
end

function VAStrategy:calculate_investment_needed(current_price)
    local target_value = self:get_target_value()
    local current_value = self:get_state().holdings * current_price
    return target_value - current_value
end

function VAStrategy:should_trade(current_price)
    local current_time = os.time()
    self.months_elapsed = math.floor((current_time - self.start_time) / (30 * 24 * 60 * 60))
    
    local investment_needed = self:calculate_investment_needed(current_price)
    
    Logger.debug("VAStrategy", "Calculating trade need", {
        months_elapsed = self.months_elapsed,
        investment_needed = investment_needed,
        current_price = current_price
    })
    
    if math.abs(investment_needed) < self.config.min_single_investment then
        Logger.debug("VAStrategy", "Investment needed below minimum", {
            min_investment = self.config.min_single_investment
        })
        return nil
    end
    
    local action = investment_needed > 0 and Action.BUY or Action.SELL
    Logger.info("VAStrategy", "Trade decision made", {
        action = action,
        investment_needed = investment_needed
    })
    
    return action
end

function VAStrategy:calculate_quantity(action, current_price)
    local investment_needed = self:calculate_investment_needed(current_price)
    local quantity
    
    if action == Action.BUY then
        investment_needed = math.min(math.abs(investment_needed), self.config.max_single_investment)
        quantity = investment_needed / current_price
    else
        investment_needed = math.min(math.abs(investment_needed), self.config.max_single_investment)
        quantity = investment_needed / current_price
    end
    
    return math.floor(quantity * 100) / 100
end

function VAStrategy:validate_trade(action, quantity, price)
    local state = self:get_state()
    if action == Action.BUY then
        return state.balance >= quantity * price
    else
        return state.holdings >= quantity
    end
end

return VAStrategy 