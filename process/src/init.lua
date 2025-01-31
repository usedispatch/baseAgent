local sqlite3 = require("lsqlite3")
local json = require("json")
local strategy_manager = require("lib.strategy_manager")

-- Initialize database
DB = DB or sqlite3.open_memory()
DbAdmin = require('DbAdmin').new(DB)

-- Constants
Action = {
    BUY = "BUY",
    SELL = "SELL"
}

OrderStatus = {
    PENDING = "PENDING",
    FILLED = "FILLED",
    CANCELLED = "CANCELLED"
}

-- Database initialization
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

        CREATE TABLE IF NOT EXISTS State (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
    ]]

    -- Initialize state if needed
    local state = DbAdmin:exec("SELECT * FROM State WHERE key = 'strategy_state'")
    if not state or #state == 0 then
        DbAdmin:apply(
            'INSERT INTO State (key, value) VALUES (?, ?)',
            {'strategy_state', json.encode({holdings = 0, balance = 0})}
        )
    end

    Configured = true
end

-- Initialize if not already done
if not Configured then Configure() end

-- Load saved state into strategy
local function loadStrategyState()
    local state = DbAdmin:exec("SELECT value FROM State WHERE key = 'strategy_state'")
    if state and #state > 0 then
        local saved_state = json.decode(state[1].value)
        local strategy = strategy_manager:get_current_strategy()
        strategy:update_state(saved_state.holdings, saved_state.balance)
    end
end

-- Save strategy state to database
local function saveStrategyState()
    local strategy = strategy_manager:get_current_strategy()
    local state = strategy:get_state()
    DbAdmin:apply(
        'UPDATE State SET value = ? WHERE key = ?',
        {json.encode(state), 'strategy_state'}
    )
end

-- Initialize strategy with saved state
loadStrategyState()

-- Export functions that need to be globally available
function sendReply(msg, data)
    msg.reply({Data = data, Action = msg.Action .. "Response"})
end

function generate_uuid()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

-- Clean up old utility files that are now part of strategies
if package.loaded['utils.dca'] then package.loaded['utils.dca'] = nil end
if package.loaded['utils.va'] then package.loaded['utils.va'] = nil end

-- Load handlers
require('lib.handlers')

