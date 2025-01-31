-- Base Strategy Interface
local BaseStrategy = {}
BaseStrategy.__index = BaseStrategy

function BaseStrategy.new(config)
    local self = setmetatable({}, BaseStrategy)
    self.config = config
    return self
end

-- Required interface methods that all strategies must implement
function BaseStrategy:should_trade(current_price)
    error("should_trade must be implemented by strategy")
end

function BaseStrategy:calculate_quantity(action, current_price)
    error("calculate_quantity must be implemented by strategy")
end

function BaseStrategy:validate_trade(action, quantity, price)
    error("validate_trade must be implemented by strategy")
end

-- Common utility methods available to all strategies
function BaseStrategy:get_state()
    return {
        holdings = self.holdings or 0,
        balance = self.balance or 0
    }
end

function BaseStrategy:update_state(holdings, balance)
    self.holdings = holdings
    self.balance = balance
end

return BaseStrategy 