-- Recycle Bin: deleted things go to the user's bin (/usr/<name>/.trash) instead of
-- disappearing, and can be put back or deleted for good.
--
--   local trash = require("trash")
--   trash.put("/usr/aaron/documents/old.txt")
--   for _, item in ipairs(trash.list()) do print(item.name, item.from) end
--   trash.restore(item.id)   trash.purge(item.id)   trash.empty()
local T = {}

local function bin() return "/usr/" .. phoenix.user() .. "/.trash" end
local function indexPath() return bin() .. "/.index" end

local function readIndex()
    local f = fs.open(indexPath(), "r")
    if not f then return {} end
    local data = textutils.unserialize(f.readAll() or "")
    f.close()
    return type(data) == "table" and data or {}
end

local function writeIndex(index)
    local f = fs.open(indexPath(), "w")
    if not f then return end
    f.write(textutils.serialize(index))
    f.close()
end

-- A name that isn't taken in dir: "notes.txt", then "notes (2).txt", "notes (3).txt"...
function T.freeName(dir, name)
    if not fs.exists(fs.combine(dir, name)) then return name end
    local base, ext = name:match("^(.-)(%.[^.]*)$")
    if not base or base == "" then base, ext = name, "" end
    local n = 2
    while fs.exists(fs.combine(dir, base .. " (" .. n .. ")" .. ext)) do n = n + 1 end
    return base .. " (" .. n .. ")" .. ext
end

-- Move a file or folder into the bin. Returns true, or nil and why not.
function T.put(path)
    path = "/" .. fs.combine(path, "")
    if path == bin() or path:sub(1, #bin() + 1) == bin() .. "/" then return nil, "That's already in the Recycle Bin" end
    if not fs.isDir(bin()) then fs.makeDir(bin()) end
    local id = T.freeName(bin(), fs.getName(path))
    local ok, err = pcall(fs.move, path, fs.combine(bin(), id))
    if not ok then return nil, err end
    local index = readIndex()
    index[id] = { from = path, when = os.epoch("utc") }
    writeIndex(index)
    return true
end

-- What's in the bin, newest first: { { id, name, from, when, dir }, ... }
function T.list()
    local index, out = readIndex(), {}
    if not fs.isDir(bin()) then return out end
    for _, id in ipairs(fs.list(bin())) do
        if id ~= ".index" then
            local info = index[id] or {}
            out[#out + 1] = {
                id = id, name = info.from and fs.getName(info.from) or id, from = info.from,
                when = info.when or 0, dir = fs.isDir(fs.combine(bin(), id)),
            }
        end
    end
    table.sort(out, function(a, b) return a.when > b.when end)
    return out
end

-- Put something back where it came from (with a new name if that's been taken since).
function T.restore(id)
    local index = readIndex()
    local info = index[id]
    local src = fs.combine(bin(), id)
    if not fs.exists(src) then return nil, "It's not in the Recycle Bin any more" end
    local from = info and info.from or ("/usr/" .. phoenix.user() .. "/" .. id)
    local dir = fs.getDir(from)
    if not fs.isDir(dir) then
        local ok, err = pcall(fs.makeDir, dir)
        if not ok then return nil, err end
    end
    local dest = fs.combine(dir, T.freeName(dir, fs.getName(from)))
    local ok, err = pcall(fs.move, src, dest)
    if not ok then return nil, err end
    index[id] = nil
    writeIndex(index)
    return "/" .. dest
end

-- Delete one thing in the bin for good.
function T.purge(id)
    local index = readIndex()
    local ok, err = pcall(fs.delete, fs.combine(bin(), id))
    if not ok then return nil, err end
    index[id] = nil
    writeIndex(index)
    return true
end

-- Delete everything in the bin for good.
function T.empty()
    for _, item in ipairs(T.list()) do T.purge(item.id) end
    writeIndex({})
    return true
end

return T
