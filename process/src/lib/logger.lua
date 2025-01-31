local json = require('json')

local Logger = {}
Logger.__index = Logger

local LOG_LEVELS = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4
}

local current_log_level = LOG_LEVELS.INFO

function Logger.setLogLevel(level)
    if LOG_LEVELS[level] then
        current_log_level = LOG_LEVELS[level]
    end
end

local function formatMessage(level, component, message, data)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local formatted = string.format("[%s] [%s] [%s] %s", 
        timestamp, level, component, message)
    
    if data then
        if type(data) == "table" then
            formatted = formatted .. "\nData: " .. json.encode(data)
        else
            formatted = formatted .. "\nData: " .. tostring(data)
        end
    end
    
    return formatted
end

local function shouldLog(level)
    return LOG_LEVELS[level] >= current_log_level
end

function Logger.debug(component, message, data)
    if shouldLog("DEBUG") then
        print(formatMessage("DEBUG", component, message, data))
    end
end

function Logger.info(component, message, data)
    if shouldLog("INFO") then
        print(formatMessage("INFO", component, message, data))
    end
end

function Logger.warn(component, message, data)
    if shouldLog("WARN") then
        print(formatMessage("WARN", component, message, data))
    end
end

function Logger.error(component, message, data)
    if shouldLog("ERROR") then
        print(formatMessage("ERROR", component, message, data))
        -- Also log to database
        if DbAdmin then
            pcall(function()
                DbAdmin:apply(
                    'INSERT INTO ErrorLog (timestamp, operation, error_message) VALUES (?, ?, ?)',
                    {os.time(), component, formatMessage("ERROR", component, message, data)}
                )
            end)
        end
    end
end

return Logger 