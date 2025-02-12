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