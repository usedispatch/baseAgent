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


