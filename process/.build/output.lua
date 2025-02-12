local sqlite3 = require("lsqlite3")
local json = require("json")
DB = DB or sqlite3.open_memory()
DbAdmin = require('@rakis/DbAdmin').new(DB)
local shouldTrade = false;
QUOTE_TOKEN_PROCESS = "susX6iEMMuxJSUnVGXaiEu9PwOeFpIwx4mj1k4YiEBk";
ISSUED_TOKEN_PROCESS = nil;
DCA_OWNER = nil;
-- DCA Strategy Configuration
DCA_CONFIG = {
    investment_amount = 0,  -- Fixed amount to invest each time
    interval_seconds = 0,  -- Default to daily (24 * 60 * 60 seconds)
    total_orders = 0,        -- Total number of orders to execute
    orders_executed = 0,      -- Track number of orders executed
    last_order_time = 0,      -- Track last order timestamp
}

function Configure()
    
    DbAdmin:exec[[
        CREATE TABLE IF NOT EXISTS Orders (
            id TEXT PRIMARY KEY,
            action TEXT NOT NULL,
            quantity REAL NOT NULL,
            timestamp INTEGER NOT NULL,
            status TEXT NOT NULL
        );
        ]]

    Configured = true
end

if not Configured then Configure() end

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




-- Helper function to generate UUID-like strings
local function generate_uuid()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

-- Validate order based on current state
local function validate_order(state, action, quantity, price)
    if action == Action.BUY then
        return state.balance >= quantity * price
    elseif action == Action.SELL then
        return state.holdings >= quantity
    end
    return false
end





function saveOrder(order)
    DbAdmin:apply(
        'INSERT INTO Orders (id, action, quantity, timestamp, status) VALUES (?, ?, ?, ?, ?)',
        {
            order.id,
            order.action,
            order.quantity,
            order.timestamp,
            order.status
        }
    )
end

-- Get all orders
function getOrders()
    local results = DbAdmin:exec("SELECT * FROM Orders ORDER BY timestamp DESC;")
    return json.encode(results)
end

-- Get orders by status
function getOrdersByStatus(status)
    local results = DbAdmin:exec(
        "SELECT * FROM Orders WHERE status = ? ORDER BY timestamp DESC;",
        {status}
    )
    return json.encode(results)
end

-- Update order status
function updateOrderStatus(orderId, status)
    DbAdmin:apply(
        'UPDATE Orders SET status = ? WHERE id = ?',
        {status, orderId}
    )
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



 function createBuyOrder(quantity, issued_token,sender)
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




-- Register handlers
Handlers.add("deposit",
function(msg)
    return Handlers.utils.hasMatchingTag('Action', 'Credit-Notice') and
        msg.Tags["From-Process"] == QUOTE_TOKEN_PROCESS and
        msg.Tags["X-Action"] == "deposit"
  end,
depositHandler)
Handlers.add("withdraw",withdrawHandler)
Handlers.add("getBalance",getBalanceHandler)
Handlers.add("getOrders",getOrdersHandler)
Handlers.add("trade",tradeHandler)
