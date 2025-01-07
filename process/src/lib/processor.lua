

function depositProcessor(msg)
    local data = json.decode(msg.Data)
    amount = amount + data.amount
    sendReply(msg, amount)
    shouldTrade = true
end


function withdrawProcessor(msg)
    local data = json.decode(msg.Data)
    amount = amount - data.amount
    sendReply(msg, amount)
    
end

function getDepositProcessor(msg)
    sendReply(msg, amount)
end

function getOrdersProcessor(msg)
    local orders = getOrders()
    sendReply(msg, orders)
end


function tradeProcessor(msg)
    local data = json.decode(msg.Data)
    currentPrice = data.price
    if shouldTrade == false or amount <= 0 then
        sendReply(msg, "Not trading")
    end

    if not current_price then
        sendReply(msg, "Current price is required")
    end

    local action = should_trade(current_price)
    local quantity = calculate_quantity(action, current_price)
    if quantity <= 0 then
        sendReply(msg, "No quantity to trade")
    end
    local order = {
        id = generate_uuid(),
        action = action,
        price = current_price,
        quantity = quantity,
        timestamp = os.time(),
        status = OrderStatus.PENDING
    }
    -- This is where we would place the order in dexes
    saveOrder(order)
    sendReply(msg, order)
end



