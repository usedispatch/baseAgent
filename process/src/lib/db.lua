local json = require('json')

-- Error handling helper
local function handle_db_error(operation, err)
    local error_msg = string.format("[Database Error] %s failed: %s", operation, err)
    print(error_msg)  -- Basic logging
    return nil, error_msg
end

-- Order Management
function saveOrder(order)
    local success, err = pcall(function()
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
    end)
    
    if not success then
        return handle_db_error("Save order", err)
    end
    
    -- Save updated state after order
    saveStrategyState()
    return true
end

-- Get all orders with optional filtering
function getOrders(filter)
    local query = "SELECT * FROM Orders"
    local params = {}
    
    if filter then
        local conditions = {}
        if filter.status then
            table.insert(conditions, "status = ?")
            table.insert(params, filter.status)
        end
        if filter.action then
            table.insert(conditions, "action = ?")
            table.insert(params, filter.action)
        end
        if #conditions > 0 then
            query = query .. " WHERE " .. table.concat(conditions, " AND ")
        end
    end
    
    query = query .. " ORDER BY timestamp DESC"
    
    local success, result = pcall(function()
        return DbAdmin:exec(query, params)
    end)
    
    if not success then
        return handle_db_error("Get orders", result)
    end
    
    return json.encode(result)
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
    local success, err = pcall(function()
        DbAdmin:apply(
            'UPDATE Orders SET status = ? WHERE id = ?',
            {status, orderId}
        )
    end)
    
    if not success then
        return handle_db_error("Update order status", err)
    end
    
    return true
end

-- State Management
function saveStrategyState()
    local strategy = strategy_manager:get_current_strategy()
    local state = strategy:get_state()
    
    local success, err = pcall(function()
        DbAdmin:apply(
            'UPDATE State SET value = ? WHERE key = ?',
            {json.encode(state), 'strategy_state'}
        )
    end)
    
    if not success then
        return handle_db_error("Save strategy state", err)
    end
    
    return true
end

function getStrategyState()
    local success, result = pcall(function()
        local state = DbAdmin:exec("SELECT value FROM State WHERE key = 'strategy_state'")
        if state and #state > 0 then
            return json.decode(state[1].value)
        end
        return nil
    end)
    
    if not success then
        return handle_db_error("Get strategy state", result)
    end
    
    return result
end

-- Analytics functions
function getTradeStats()
    local success, result = pcall(function()
        return DbAdmin:exec([[
            SELECT 
                action,
                COUNT(*) as count,
                AVG(price) as avg_price,
                AVG(quantity) as avg_quantity,
                SUM(quantity * price) as total_value
            FROM Orders 
            WHERE status = 'FILLED'
            GROUP BY action
        ]])
    end)
    
    if not success then
        return handle_db_error("Get trade stats", result)
    end
    
    return json.encode(result)
end

-- Get performance metrics
function getPerformanceMetrics()
    local success, result = pcall(function()
        return DbAdmin:exec([[
            WITH trade_values AS (
                SELECT 
                    action,
                    price * quantity as trade_value,
                    timestamp
                FROM Orders 
                WHERE status = 'FILLED'
            )
            SELECT 
                COUNT(*) as total_trades,
                SUM(CASE WHEN action = 'BUY' THEN trade_value ELSE 0 END) as total_bought,
                SUM(CASE WHEN action = 'SELL' THEN trade_value ELSE 0 END) as total_sold,
                MIN(timestamp) as first_trade,
                MAX(timestamp) as last_trade
            FROM trade_values
        ]])
    end)
    
    if not success then
        return handle_db_error("Get performance metrics", result)
    end
    
    return json.encode(result)
end

-- Get time-based analysis
function getTimeAnalysis(period)
    local interval = period == 'daily' and '1 day' or 
                    period == 'weekly' and '7 days' or 
                    period == 'monthly' and '30 days'
    
    if not interval then
        return handle_db_error("Get time analysis", "Invalid period")
    end
    
    local success, result = pcall(function()
        return DbAdmin:exec([[
            SELECT 
                datetime(timestamp, 'unixepoch', ?1) as period,
                COUNT(*) as trades,
                AVG(price) as avg_price,
                SUM(quantity) as total_quantity
            FROM Orders 
            WHERE status = 'FILLED'
            GROUP BY period
            ORDER BY period DESC
        ]], {interval})
    end)
    
    if not success then
        return handle_db_error("Get time analysis", result)
    end
    
    return json.encode(result)
end

-- Get strategy performance
function getStrategyPerformance()
    local success, result = pcall(function()
        local state = getStrategyState()
        local stats = json.decode(getTradeStats())
        
        return {
            current_holdings = state.holdings,
            current_balance = state.balance,
            trade_stats = stats,
            total_trades = #json.decode(getOrders())
        }
    end)
    
    if not success then
        return handle_db_error("Get strategy performance", result)
    end
    
    return json.encode(result)
end

-- Error logging table
DbAdmin:exec[[
    CREATE TABLE IF NOT EXISTS ErrorLog (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        operation TEXT NOT NULL,
        error_message TEXT NOT NULL
    );
]]

-- Log errors to database
local function logError(operation, error_message)
    pcall(function()
        DbAdmin:apply(
            'INSERT INTO ErrorLog (timestamp, operation, error_message) VALUES (?, ?, ?)',
            {os.time(), operation, error_message}
        )
    end)
end

return {
    saveOrder = saveOrder,
    getOrders = getOrders,
    getOrdersByStatus = getOrdersByStatus,
    updateOrderStatus = updateOrderStatus,
    saveStrategyState = saveStrategyState,
    getStrategyState = getStrategyState,
    getTradeStats = getTradeStats,
    getPerformanceMetrics = getPerformanceMetrics,
    getTimeAnalysis = getTimeAnalysis,
    getStrategyPerformance = getStrategyPerformance,
    logError = logError
}