local Action = {
    BUY = "BUY",
    SELL = "SELL"
}

local OrderStatus = {
    PENDING = "PENDING",
    FILLED = "FILLED",
    CANCELLED = "CANCELLED"
}

local function sendReply(msg, data)
    msg.reply({Data = data, Action = msg.Action .. "Response"})
end

function depositHandler(msg)
    local amount = tonumber(msg.Tags["Quantity"])
    ao.log(amount)
    if not amount or amount <= 0 then
        sendReply(msg, "Invalid amount")
        return
    end

    local orders = tonumber(msg.Tags["X-Orders"]) 
    local interval = tonumber(msg.Tags["X-Interval"]) 

    DCA_CONFIG.investment_amount = amount
    DCA_CONFIG.total_orders = orders
    DCA_CONFIG.interval_seconds = interval
    shouldTrade = true
    DCA_OWNER = msg.Tags.Sender
    sendReply(msg, "Successfully configured")
end

-- now that i think more on this withdraw is not required cause the investment amount is going to be converted to the quote token on trade and get fully used.
-- function withdrawHandler(msg)
--     local data = json.decode(msg.Data)
--     if msg.Tags.Sender ~= DCA_OWNER then
--         sendReply(msg, "Only owner can withdraw")
--         return
--     end
--     sendReply(msg, amount)
    
-- end

function getBalanceHandler(msg)
    sendReply(msg, DCA_CONFIG.investment_amount)
end

function getOrdersHandler(msg)
    local orders = getOrders()
    sendReply(msg, orders)
end


function tradeHandler(msg)
    if not shouldTrade then
        sendReply(msg, "Trading is disabled")
        return
    end

    -- Check DCA conditions
    if DCA_CONFIG.orders_executed >= DCA_CONFIG.total_orders then
        sendReply(msg, "DCA: All orders completed")
        return
    end

    local current_time = os.time()
    if current_time - DCA_CONFIG.last_order_time < DCA_CONFIG.interval_seconds then
        sendReply(msg, "DCA: Waiting for next interval")
        return
    end
    
    local quantity = DCA_CONFIG.investment_amount
    if quantity <= 0 then
        sendReply(msg, "Invalid investment amount")
        return
    end

    local order = {
        id = generate_uuid(),
        action = "BUY",
        quantity = quantity,
        timestamp = current_time,
        status = OrderStatus.FILLED
    }

    -- This is where we would place the order in dexes
    createBuyOrder(quantity, ISSUED_TOKEN_PROCESS, msg.Tags.Sender)
    -- Update DCA tracking
    DCA_CONFIG.last_order_time = current_time
    DCA_CONFIG.orders_executed = DCA_CONFIG.orders_executed + 1
    saveOrder(order)
    sendReply(msg, order)
end



 function createBuyOrder(quantity, issued_token, sender)
    -- Validate inputs
    assert(type(quantity) == 'number' and quantity > 0, "Quantity must be a positive number")
    local BONDING_CURVE_PROCESS = "KKhElSLcvqeP49R96qXaRokb1bu1qPBKx2MyFsRxIl4"

    ao.send({
        Target = issued_token,
        Action = "Transfer",
        Recipient = BONDING_CURVE_PROCESS,
        Quantity = quantity,
        ["X-Action"] = 'Curve-Buy'
    })
end
