-- Phoenix OS installer.
--   wget run https://raw.githubusercontent.com/MADDXSTUDIOS/Phoenix-OS/main/install.lua
-- Downloads every file listed in manifest.txt, then restarts into Phoenix OS.
-- Accounts, settings and user files (/etc, /usr) are left alone, so running it
-- again updates an existing install.
local BASE = "https://raw.githubusercontent.com/MADDXSTUDIOS/Phoenix-OS/main/"
local base = ... or BASE
if base:sub(-1) ~= "/" then base = base .. "/" end

local function fetch(path)
    local res, err = http.get(base .. path, nil, true)
    if not res then return nil, err end
    local body = res.readAll()
    res.close()
    return body
end

term.clear()
term.setCursorPos(1, 1)
if term.isColour() then term.setTextColour(colours.orange) end
print("Phoenix OS installer")
term.setTextColour(colours.white)

if not term.isColour() then
    printError("Phoenix OS needs an Advanced Computer.")
    return
end
if not http then
    printError("The http API is switched off on this server.")
    return
end

local manifest, err = fetch("manifest.txt")
if not manifest then
    printError("Couldn't download the file list: " .. tostring(err))
    return
end
local files = {}
for line in manifest:gmatch("[^\r\n]+") do
    if line:match("%S") and not line:match("^#") then files[#files + 1] = line end
end

print("Downloading " .. #files .. " files...")
local _, y = term.getCursorPos()
local got = {}
for i, path in ipairs(files) do
    term.setCursorPos(1, y)
    term.clearLine()
    write(("[%d/%d] %s"):format(i, #files, path))
    local body, e = fetch(path)
    if not body then
        print()
        printError("Failed on " .. path .. ": " .. tostring(e))
        print("Nothing was changed.")
        return
    end
    got[path] = body
end

-- Only write once everything has downloaded, so a failed download can't leave half an OS.
for path, body in pairs(got) do
    local f = fs.open(path, "wb")
    f.write(body)
    f.close()
end
print()
if term.isColour() then term.setTextColour(colours.lime) end
print("Phoenix OS installed.")
term.setTextColour(colours.white)
print("Restarting in 3 seconds...")
sleep(3)
os.reboot()
