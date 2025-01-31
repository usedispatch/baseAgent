local Logger = require('lib.logger')
local strategy_manager = require('lib.strategy_manager')
local db = require('lib.db')

function depositHandler(msg)
    local data = json.decode(msg.Data)
    amount = amount + data.amount
    sendReply(msg, amount)
    shouldTrade = true
end


function withdrawHandler(msg)
    local data = json.decode(msg.Data)
    amount = amount - data.amount
    sendReply(msg, amount)
    
end

function getDepositHandler(msg)
    sendReply(msg, amount)
end

function getOrdersHandler(msg)
    local orders = getOrders()
    sendReply(msg, orders)
end


function tradeHandler(msg)
    local data = json.decode(msg.Data)
    local current_price = data.price
    
    if not current_price then
        Logger.warn("Processor", "Missing price in trade request", data)
        return sendReply(msg, "Current price is required")
    end

    Logger.info("Processor", "Processing trade request", {price = current_price})
    
    local strategy = strategy_manager:get_current_strategy()
    local action = strategy:should_trade(current_price)
    
    if not action then
        Logger.debug("Processor", "No trade needed at current price")
        return sendReply(msg, "No trade needed")
    end
    
    local quantity = strategy:calculate_quantity(action, current_price)
    
    if not strategy:validate_trade(action, quantity, current_price) then
        Logger.warn("Processor", "Trade validation failed", {
            action = action,
            quantity = quantity,
            price = current_price
        })
        return sendReply(msg, "Trade validation failed")
    end
    
    local order = {
        id = generate_uuid(),
        action = action,
        price = current_price,
        quantity = quantity,
        timestamp = os.time(),
        status = OrderStatus.PENDING
    }
    
    local success = db.saveOrder(order)
    if not success then
        Logger.error("Processor", "Failed to save order", order)
        return sendReply(msg, "Failed to save order")
    end
    
    Logger.info("Processor", "Trade order created successfully", order)
    sendReply(msg, order)
end



