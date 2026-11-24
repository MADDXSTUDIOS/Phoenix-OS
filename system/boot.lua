-- Phoenix OS boot: check the computer, load the system and start the kernel.
local VERSION = "0.1.2-dev"
local EDITION = "Standard"
local MIN_W, MIN_H = 51, 19

local native = term.native()
local w, h = native.getSize()

-- Phoenix OS needs an advanced computer. Anything else gets a plain message and CraftOS.
if not native.isColour() or turtle or pocket or w < MIN_W or h < MIN_H then
    term.clear()
    term.setCursorPos(1, 1)
    print("Phoenix OS " .. VERSION)
    print()
    print("This computer is not compatible with Phoenix OS.")
    print()
    print("Phoenix OS needs an Advanced Computer with a")
    print("colour screen of at least " .. MIN_W .. "x" .. MIN_H .. " characters.")
    print()
    print("A command-line edition for standard computers")
    print("is planned.")
    return
end

local function readConfig()
    local cfg = { recovery = true }
    if fs.exists("/etc/system.cfg") then
        local f = fs.open("/etc/system.cfg", "r")
        local data = textutils.unserialize(f.readAll() or "")
        f.close()
        if type(data) == "table" then for k, v in pairs(data) do cfg[k] = v end end
    end
    return cfg
end
local config = readConfig()

local function centre(y, text, colour)
    native.setTextColour(colour)
    native.setCursorPos(math.floor((w - #text) / 2) + 1, y)
    native.write(text)
end

local function resetScreen()
    for i = 0, 15 do native.setPaletteColour(2 ^ i, term.nativePaletteColour(2 ^ i)) end
    term.setBackgroundColour(colors.black)
    term.setTextColour(colors.white)
    term.setCursorBlink(false)
    term.clear()
    term.setCursorPos(1, 1)
end

-- Start-up screen. Pressing F8 here leaves for CraftOS (while recovery is switched on).
native.setBackgroundColour(colors.black)
native.clear()
native.setCursorBlink(false)
centre(math.floor(h / 2) - 1, "P H O E N I X   O S", colors.orange)
centre(math.floor(h / 2) + 1, "Starting...", colors.lightGray)
if config.recovery then
    centre(h, "Press F8 for recovery", colors.gray)
    local timer = os.startTimer(0.8)
    while true do
        local ev, a = os.pullEventRaw()
        if ev == "timer" and a == timer then break end
        if ev == "key" and a == keys.f8 then
            resetScreen()
            print("Phoenix OS recovery: you are in CraftOS.")
            print("Type 'reboot' to start Phoenix OS again.")
            return
        end
    end
end

local sys = { version = VERSION, edition = EDITION, native = native, config = config }
local kenv = setmetatable({ sys = sys }, { __index = _G })

local function module(path)
    local fn, err = loadfile(path, nil, kenv)
    if not fn then error(err, 0) end
    return fn()
end

local ok, err = xpcall(function()
    sys.theme = module("/system/theme.lua")
    sys.sha256 = module("/lib/sha256.lua")
    sys.ui = module("/lib/ui.lua")
    sys.users = module("/system/users.lua")
    sys.shelllib = module("/system/shelllib.lua")
    sys.kernel = module("/system/kernel.lua")
    sys.wm = module("/system/wm.lua")
    sys.desktop = module("/system/desktop.lua")
    sys.login = module("/system/login.lua")
    sys.kernel.main()
end, function(e) return tostring(e) .. "\n" .. debug.traceback() end)

-- Only reached if the system itself failed. Put CraftOS back and say what happened.
if sys.kernel then pcall(sys.kernel.unpatch) end
term.redirect(native)
resetScreen()
pcall(function()
    fs.makeDir("/etc")
    local f = fs.open("/etc/crash.log", "a")
    f.write(os.date("%Y-%m-%d %H:%M:%S") .. " Phoenix OS " .. VERSION .. "\n" .. tostring(err) .. "\n\n")
    f.close()
end)
term.setTextColour(colors.red)
print("Phoenix OS has stopped")
term.setTextColour(colors.white)
print()
print(tostring(err))
print()
term.setTextColour(colors.lightGray)
print("Saved to /etc/crash.log")
print("R = restart" .. (config.recovery and "    C = CraftOS" or ""))
while true do
    local ev, a = os.pullEventRaw()
    if ev == "key" and a == keys.r then os.reboot() end
    if ev == "key" and a == keys.c and config.recovery then
        term.clear()
        term.setCursorPos(1, 1)
        return
    end
end
