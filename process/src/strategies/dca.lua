local BaseStrategy = require('strategies.base')
local Logger = require('lib.logger')

local DCAStrategy = setmetatable({}, { __index = BaseStrategy })
DCAStrategy.__index = DCAStrategy

function DCAStrategy.new(config)
    local self = BaseStrategy.new(config)
    setmetatable(self, DCAStrategy)
    
    -- Initialize DCA specific state
    self.last_trade_price = nil
    self.last_trade_time = 0
    
    return self
end

function DCAStrategy:should_trade(current_price)
    if not self.last_trade_price then
        Logger.debug("DCAStrategy", "First trade, setting initial price", {price = current_price})
        self.last_trade_price = current_price
        return Action.BUY
    end

    local price_change = (current_price - self.last_trade_price) / self.last_trade_price
    Logger.debug("DCAStrategy", "Calculating price change", {
        current_price = current_price,
        last_price = self.last_trade_price,
        change = price_change
    })

    if math.abs(price_change) >= self.config.min_price_change then
        local action = price_change < 0 and Action.BUY or Action.SELL
        Logger.info("DCAStrategy", "Trade condition met", {
            price_change = price_change,
            action = action
        })
        return action
    end
    
    return nil
end

function DCAStrategy:calculate_quantity(action, current_price)
    local quantity = self.config.investment_amount / current_price
    
    if action == Action.BUY then
        quantity = math.min(quantity, self.config.max_single_investment / current_price)
    end
    
    Logger.debug("DCAStrategy", "Calculated trade quantity", {
        action = action,
        price = current_price,
        quantity = quantity
    })
    
    return math.floor(quantity * 100) / 100
end

function DCAStrategy:validate_trade(action, quantity, price)
    local state = self:get_state()
    if action == Action.BUY then
        return state.balance >= quantity * price
    else
        return state.holdings >= quantity
    end
end

return DCAStrategy 