local function readFile(path)
    local file = assert(io.open(path, "r"))
    local content = file:read("*all")
    file:close()
    return content
end

local output = {}

-- Add the content of each file

if os.execute("test -f process/src/init.lua") then table.insert(output, readFile("process/src/init.lua")) end
if os.execute("test -f process/src/utils/index.lua") then table.insert(output, readFile("process/src/utils/index.lua")) end
if os.execute("test -f process/src/lib/db.lua") then table.insert(output, readFile("process/src/lib/db.lua")) end
if os.execute("test -f process/src/lib/patterns.lua") then table.insert(output, readFile("process/src/lib/patterns.lua")) end
if os.execute("test -f process/src/lib/processor.lua") then table.insert(output, readFile("process/src/lib/processor.lua")) end
if os.execute("test -f process/src/lib/handlers.lua") then table.insert(output, readFile("process/src/lib/handlers.lua")) end
-- Write the combined content to output.lua
local dir = "process/build"
if not os.execute("ls process/build") then
    print("Creating build directory")
    os.execute("mkdir -p " .. dir)
end
local outFile = assert(io.open("process/build/output.lua", "w"))
outFile:write(table.concat(output, "\n\n"))
outFile:close()

-- Run the replace script to update DbAdmin line
print("Running replace script...")
dofile("process/scripts/replace.lua")

print("Build complete. Output written to output.lua")