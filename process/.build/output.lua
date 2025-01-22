local sqlite3 = require("lsqlite3")
local json = require("json")
DB = DB or sqlite3.open_memory()
DbAdmin = dbAdmin.new(DB)
local amount = 0;
local shouldTrade = false;

function Configure()
    
    DbAdmin:exec[[
        CREATE TABLE IF NOT EXISTS Orders (
            id TEXT PRIMARY KEY,
            action TEXT NOT NULL,
            price REAL NOT NULL,
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



local function should_trade(current_price)
    
end

local function calculate_quantity(action, current_price)
    
end

function saveOrder(order)
    DbAdmin:apply(
        'INSERT INTO Orders (id, action, price, quantity, timestamp, status) VALUES (?, ?, ?, ?, ?, ?)',
        {
            order.id,
            order.action,
            order.price,
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





-- Register handlers
Handlers.add("deposit",depositHandler)
Handlers.add("withdraw",withdrawHandler)
Handlers.add("getBalance",getDepositHandler)
Handlers.add("getOrders",getOrdersHandler)
Handlers.add("trade",tradeHandler)


