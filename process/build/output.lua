local sqlite3 = require("lsqlite3")
local json = require("json")
DB = DB or sqlite3.open_memory()
DbAdmin = require('DbAdmin').new(DB)
local amount = 0;

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

-- Add new todo
function testProcessor(msg)
    local uuid = generate_uuid()
    sendReply(msg, uuid)
end

function depositProcessor(msg)
    local data = json.decode(msg.Data)
    amount = amount + data.amount
    sendReply(msg, amount)
end


function withdrawProcessor(msg)
    local data = json.decode(msg.Data)
    amount = amount - data.amount
    sendReply(msg, amount)
end



-- -- Get all todos
-- function getTodosProcessor(msg)
--     local data = getTodos()
--     print(data)
--     sendReply(msg, data)
-- end

-- -- Update todo
-- function updateTodoProcessor(msg)
--     local data = json.decode(msg.Data)
--     updateTodo(data)
--     sendReply(msg, data)
-- end

-- -- Delete todo
-- function deleteTodoProcessor(msg)
--     local data = json.decode(msg.Data)
--     deleteTodo(data.id)
--     sendReply(msg, {success = true})
-- end

-- Register handlers
Handlers.add("Test", testProcessor)
Handlers.add("deposit",depositProcessor)
Handlers.add("withdraw",withdrawProcessor)