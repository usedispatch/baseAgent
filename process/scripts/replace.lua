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

-- Replace the specific lines
local newContent = string.gsub(
    content,
    "DbAdmin = require%('DbAdmin'%)%.new%(DB%)",
    "DbAdmin = dbAdmin.new(DB)"
)

-- Remove the return dbAdmin line
newDbAdminContent = string.gsub(dbAdminContent, "return%s+dbAdmin%s*\n*$", "")

writeFile(outputPath, newContent)
writeFile(dbAdminPath, newDbAdminContent)
print("Replacement complete in " .. outputPath)
print("Replacement complete in " .. dbAdminPath)
