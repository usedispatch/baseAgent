

function depositHandler(msg)
    local data = json.decode(msg.Data)
    local amount = msg.Tags["Quantity"]
    if(amount <= 0) then
        sendReply(msg, "Invalid amount")
        return
    end
    DCA_CONFIG.investment_amount = amount
    DCA_CONFIG.total_orders = data.orders
    DCA_CONFIG.interval_seconds = data.interval
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
    local data = json.decode(msg.Data)
    
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
        timestamp = os.time(),
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



 function createBuyOrder(quantity, bonding_curve,sender)
    -- Validate inputs
    assert(type(quantity) == 'number' and quantity > 0, "Quantity must be a positive number")
    assert(bonding_curve, "Bonding curve is required")
    assert(sender, "Sender is required")

    ao.send({
        Target = bonding_curve,
        Action = "Transfer",
        Recipient = sender,
        Quantity = quantity,
        ["X-Action"] = 'Curve-Buy'
    })
end


