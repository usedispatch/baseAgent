local config = require('config')
local DCAStrategy = require('strategies.dca')
local VAStrategy = require('strategies.va')

local StrategyManager = {}
StrategyManager.__index = StrategyManager

function StrategyManager.new()
    local self = setmetatable({}, StrategyManager)
    self.strategies = {
        dca = DCAStrategy,
        va = VAStrategy
    }
    self:init_strategy()
    return self
end

function StrategyManager:init_strategy()
    local strategy_name = config.current_strategy
    local strategy_config = config.strategies[strategy_name]
    
    if not strategy_config then
        error("Invalid strategy configuration")
    end
    
    local StrategyClass = self.strategies[strategy_name]
    if not StrategyClass then
        error("Strategy " .. strategy_name .. " not found")
    end
    
    self.current_strategy = StrategyClass.new(strategy_config)
end

function StrategyManager:get_current_strategy()
    return self.current_strategy
end

-- Global instance
local strategy_manager = StrategyManager.new()
return strategy_manager 