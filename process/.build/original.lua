local sqlite3 = require("lsqlite3")
local json = require("json")
local bint = require(".bint")(4096)  -- gives us 1234 digits for safe calculations

DB = DB or sqlite3.open_memory()
DbAdmin = require('@rakis/DbAdmin').new(DB)
local shouldTrade = false;
local QUOTE_TOKEN_PROCESS = "susX6iEMMuxJSUnVGXaiEu9PwOeFpIwx4mj1k4YiEBk";
local BONDING_CURVE_PROCESS;
DCA_OWNER = nil;


-- DCA Strategy Configuration
DCA_CONFIG = {
    investment_amount = bint(0),  -- Fixed amount to invest each time
    interval_seconds = bint(0),  -- Default to daily (24 * 60 * 60 seconds)
    total_orders = bint(0),        -- Total number of orders to execute
    orders_executed = bint(0),      -- Track number of orders executed
    last_order_time = bint(0),      -- Track last order timestamp
}

-- Helper function to convert string to bint with proper denomination
local function toBint(amount)
    if type(amount) == "string" then
        return bint.new(amount)
    elseif type(amount) == "number" then
        return bint.new(tostring(amount))
    else
        return amount
    end
end

-- Helper function to compare bint values
local function isGreaterOrEqual(a, b)
    a = toBint(a)
    b = toBint(b)
    return a >= b
end

local function isLessThan(a, b)
    a = toBint(a)
    b = toBint(b)
    return a < b
end

local function isLessOrEqual(a, b)
    a = toBint(a)
    b = toBint(b)
    return a <= b
end

-- Helper function to validate and convert amount
local function validateAmount(amount)
    if not amount then return nil, "Amount is required" end
    local bintAmount = toBint(amount)
    if isLessOrEqual(bintAmount, 0) then
        return nil, "Amount must be greater than 0"
    end
    return bintAmount, nil
end

-- Helper function to validate configuration
local function validateConfig()
    if not DCA_OWNER then
        return false, "DCA owner not set"
    end
    if not BONDING_CURVE_PROCESS then
        return false, "Bonding curve process not set"
    end
    if isLessOrEqual(DCA_CONFIG.investment_amount, 0) then
        return false, "Invalid investment amount"
    end
    if isLessOrEqual(DCA_CONFIG.total_orders, 0) then
        return false, "Invalid total orders"
    end
    if isLessOrEqual(DCA_CONFIG.interval_seconds, 0) then
        return false, "Invalid interval"
    end
    return true, nil
end

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

function saveOrder(order)
    DbAdmin:apply(
        'INSERT INTO Orders (id, action, quantity, timestamp, status) VALUES (?, ?, ?, ?, ?)',
        {
            order.id,
            order.action,
            tostring(order.quantity),
            tostring(order.timestamp),
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
    local amount, amountErr = validateAmount(msg.Tags["Quantity"])
    if amountErr then
        sendReply(msg, "Error: " .. amountErr)
        return
    end

    local orders = tonumber(msg.Tags["X-Orders"])
    if not orders or orders <= 0 then
        sendReply(msg, "Error: Invalid number of orders")
        return
    end

    local interval = tonumber(msg.Tags["X-Interval"])
    if not interval or interval <= 0 then
        sendReply(msg, "Error: Invalid interval")
        return
    end
    
    BONDING_CURVE_PROCESS = msg.Tags["X-Bonding-Curve"]
    if not BONDING_CURVE_PROCESS then
        sendReply(msg, "Error: Missing bonding curve process")
        return
    end

    DCA_CONFIG.investment_amount = amount
    DCA_CONFIG.total_orders = bint(orders)
    DCA_CONFIG.interval_seconds = bint(interval)
    DCA_CONFIG.orders_executed = bint(0)
    DCA_CONFIG.last_order_time = bint(0)
    shouldTrade = true
    DCA_OWNER = msg.Tags.Sender
    
    local isValid, configErr = validateConfig()
    if not isValid then
        sendReply(msg, "Error: " .. configErr)
        return
    end

    sendReply(msg, json.encode({
        status = "success",
        message = "DCA strategy configured successfully",
        config = {
            investment_amount = tostring(amount),
            total_orders = orders,
            interval_seconds = interval
        }
    }))
end

function getBalanceHandler(msg)
    local config = {
        dca_config = {
            investment_amount = tostring(DCA_CONFIG.investment_amount),
            interval_seconds = tostring(DCA_CONFIG.interval_seconds),
            total_orders = tostring(DCA_CONFIG.total_orders),
            orders_executed = tostring(DCA_CONFIG.orders_executed),
            last_order_time = tostring(DCA_CONFIG.last_order_time)
        },
        bonding_curve = BONDING_CURVE_PROCESS,
        quote_token = QUOTE_TOKEN_PROCESS,
        owner = DCA_OWNER,
        trading_enabled = shouldTrade
    }
    sendReply(msg, json.encode(config))
end

function getOrdersHandler(msg)
    local orders = getOrders()
    sendReply(msg, orders)
end

function tradeHandler(msg)
    local isValid, configErr = validateConfig()
    if not isValid then
        sendReply(msg, "Error: " .. configErr)
        return
    end

    if not shouldTrade then
        sendReply(msg, "Error: Trading is disabled")
        return
    end

    if isGreaterOrEqual(DCA_CONFIG.orders_executed, DCA_CONFIG.total_orders) then
        sendReply(msg, json.encode({
            status = "complete",
            message = "DCA: All orders completed",
            total_orders = tostring(DCA_CONFIG.total_orders),
            orders_executed = tostring(DCA_CONFIG.orders_executed)
        }))
        return
    end

    local current_time = toBint(os.time())
    local time_since_last = current_time - DCA_CONFIG.last_order_time
    if isLessThan(time_since_last, DCA_CONFIG.interval_seconds) then
        local wait_time = DCA_CONFIG.interval_seconds - time_since_last
        sendReply(msg, json.encode({
            status = "waiting",
            message = "DCA: Waiting for next interval",
            wait_seconds = tostring(wait_time)
        }))
        return
    end
    
    -- Divide investment amount by total orders using bint division
    local quantity = bint.udiv(DCA_CONFIG.investment_amount , DCA_CONFIG.total_orders)
    -- print("quantity",quantity);
    if isLessOrEqual(quantity, 0) then
        sendReply(msg, "Error: Invalid investment amount")
        return
    end
        
    local order = {
        id = generate_uuid(),
        action = Action.BUY,
        quantity = tostring(quantity),
        timestamp = tostring(current_time),
        status = OrderStatus.PENDING
    }

    -- Save order before execution
    saveOrder(order)

    -- Execute the order
    createBuyOrder(quantity, QUOTE_TOKEN_PROCESS)
    
    -- Update order status and DCA tracking
    updateOrderStatus(order.id, OrderStatus.FILLED)
    DCA_CONFIG.orders_executed = toBint(tostring(DCA_CONFIG.orders_executed)) + toBint("1")
    DCA_CONFIG.last_order_time = current_time

    sendReply(msg, json.encode({
        status = "success",
        message = "Order executed successfully",
        order = order,
        dca_progress = {
            orders_executed = tostring(DCA_CONFIG.orders_executed),
            total_orders = tostring(DCA_CONFIG.total_orders),
            next_order_time = tostring(current_time + DCA_CONFIG.interval_seconds)
        }
    }))
end

function createBuyOrder(quantity, issued_token)
    print("Creating buy order for " .. tostring(quantity) .. " " .. issued_token)
    
    ao.send({
        Target = issued_token,
        Action = "Transfer",
        Recipient = BONDING_CURVE_PROCESS,
        Quantity = tostring(quantity),
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
Handlers.add("getBalance",getBalanceHandler)
Handlers.add("getOrders",getOrdersHandler)
Handlers.add("cron",Handlers.utils.hasMatchingTag('Action', 'Cron'),tradeHandler)
