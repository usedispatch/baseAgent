local function readFile(path)
    local file = assert(io.open(path, "r"))
    local content = file:read("*all")
    file:close()
    return content
end

local function writeFile(path, content)
    local file = assert(io.open(path, "w"))
    file:write(content)
    file:close()
end

local outputPath = "process/.build/output.lua"
local dbAdminPath = "process/src/external/dbAdmin.lua"
local content = readFile(outputPath)
local dbAdminContent = readFile(dbAdminPath)

-- Restore the original line
local newContent = string.gsub(
    content,
    "DbAdmin = dbAdmin%.new%(DB%)",
    "DbAdmin = require('DbAdmin').new(DB)"
)

-- Restore the return dbAdmin line at the end
local newDbAdminContent = dbAdminContent
if not string.match(dbAdminContent, "return%s+dbAdmin%s*\n*$") then
    newDbAdminContent = dbAdminContent .. "\nreturn dbAdmin\n"
end

writeFile(outputPath, newContent)
writeFile(dbAdminPath, newDbAdminContent)
print("Restoration complete in " .. outputPath)
print("Restoration complete in " .. dbAdminPath)