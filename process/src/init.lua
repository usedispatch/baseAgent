local sqlite3 = require("lsqlite3")
local json = require("json")
DB = DB or sqlite3.open_memory()
DbAdmin = require('DbAdmin').new(DB)
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

