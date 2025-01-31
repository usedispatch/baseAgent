local strategy_manager = require('lib.strategy_manager')
local json = require('json')
local Logger = require('lib.logger')

function tradeHandler(msg)
    local data = json.decode(msg.Data)
    local current_price = data.price
    
    if not current_price then
        Logger.warn("TradeHandler", "Missing price in trade request", data)
        sendReply(msg, "Current price is required")
        return
    end
    
    Logger.debug("TradeHandler", "Processing trade request", {price = current_price})
    
    local strategy = strategy_manager:get_current_strategy()
    local action = strategy:should_trade(current_price)
    
    if not action then
        sendReply(msg, "No trade needed")
        return
    end
    
    local quantity = strategy:calculate_quantity(action, current_price)
    
    if not strategy:validate_trade(action, quantity, current_price) then
        sendReply(msg, "Trade validation failed")
        return
    end
    
    local order = {
        id = generate_uuid(),
        action = action,
        price = current_price,
        quantity = quantity,
        timestamp = os.time(),
        status = OrderStatus.PENDING
    }
    
    saveOrder(order)
    Logger.info("TradeHandler", "Trade order created", order)
    sendReply(msg, order)
end

function depositHandler(msg)
    local data = json.decode(msg.Data)
    local strategy = strategy_manager:get_current_strategy()
    local current_state = strategy:get_state()
    
    strategy:update_state(
        current_state.holdings,
        current_state.balance + data.amount
    )
    
    sendReply(msg, strategy:get_state())
end

-- Register handlers
Handlers.add("deposit", depositHandler)
Handlers.add("withdraw",withdrawHandler)
Handlers.add("getBalance",getDepositHandler)
Handlers.add("getOrders", getOrdersHandler)
Handlers.add("trade", tradeHandler)


