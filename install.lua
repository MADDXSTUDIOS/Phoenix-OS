-- Phoenix OS installer (public placeholder).
-- Phoenix OS is still being built, so this only shows a notice and installs nothing.
-- Development builds: wget run https://raw.githubusercontent.com/MADDXSTUDIOS/Phoenix-OS/main/install.lua dev
local arg = ...

if arg == "dev" then
    local res, err = http.get("https://raw.githubusercontent.com/MADDXSTUDIOS/Phoenix-OS/dev/install.lua")
    if not res then
        printError("Couldn't download the development installer: " .. tostring(err))
        return
    end
    local code = res.readAll()
    res.close()
    local fn, e = load(code, "@install.lua", "t", _ENV)
    if not fn then printError(e) return end
    return fn("dev")
end

local w, h = term.getSize()
local colour = term.isColour()

local function centre(y, text, fg)
    if colour and fg then term.setTextColour(fg) end
    term.setCursorPos(math.floor((w - #text) / 2) + 1, y)
    term.write(text)
end

if colour then
    -- Phoenix colours for the splash; put back to normal afterwards.
    term.setPaletteColour(colours.cyan, 0x1F8A9E)
    term.setPaletteColour(colours.orange, 0xEE7A1C)
    term.setPaletteColour(colours.lightBlue, 0xBFE3EA)
    term.setBackgroundColour(colours.cyan)
    term.setTextColour(colours.white)
end
term.clear()

local top = math.max(1, math.floor(h / 2) - 4)
if colour then
    term.setBackgroundColour(colours.orange)
    for y = top, top + 2 do
        term.setCursorPos(1, y)
        term.write((" "):rep(w))
    end
end
centre(top + 1, "P H O E N I X   O S", colours.white)
if colour then term.setBackgroundColour(colours.cyan) end
centre(top + 4, "Under development", colours.white)
centre(top + 6, "Phoenix OS isn't ready to install yet.", colours.lightBlue)
centre(top + 7, "Check back soon!", colours.lightBlue)
centre(h, "Press any key", colours.white)

os.pullEvent("key")
if colour then
    for _, c in ipairs({ colours.cyan, colours.orange, colours.lightBlue }) do
        term.setPaletteColour(c, term.nativePaletteColour(c))
    end
    term.setBackgroundColour(colours.black)
    term.setTextColour(colours.white)
end
term.clear()
term.setCursorPos(1, 1)
print("Nothing was installed.")
