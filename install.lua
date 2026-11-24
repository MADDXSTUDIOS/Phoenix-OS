-- Phoenix OS installer.
--   wget run https://raw.githubusercontent.com/MADDXSTUDIOS/Phoenix-OS/main/install.lua dev
-- (main's installer hands over to this one). The computer then keeps updating
-- from the branch it was installed from.
--
-- Shows a full-screen installer: confirm, download with a progress bar, then
-- restart into Phoenix OS. Accounts, settings and user files (/etc, /usr) are kept.
local REPO = "https://raw.githubusercontent.com/MADDXSTUDIOS/Phoenix-OS/"
local branch = ... or "main"
local base = branch:match("^https?://") and branch or (REPO .. branch .. "/")
if base:sub(-1) ~= "/" then base = base .. "/" end

if not term.isColour() then
    printError("Phoenix OS needs an Advanced Computer.")
    return
end

local W, H = term.getSize()
local C = colors

------------------------------------------------------------------ drawing
local palette = {
    [C.cyan] = 0x1F8A9E, [C.orange] = 0xEE7A1C, [C.lightBlue] = 0xBFE3EA, [C.gray] = 0x3B4252,
    [C.lime] = 0x6CC644, [C.red] = 0xD64541, [C.white] = 0xF4F5F7, [C.blue] = 0x2563C9, [C.lightGray] = 0xB4BAC4,
}
for c, rgb in pairs(palette) do term.setPaletteColour(c, rgb) end

local function resetScreen()
    for c in pairs(palette) do term.setPaletteColour(c, term.nativePaletteColour(c)) end
    term.setBackgroundColour(C.black)
    term.setTextColour(C.white)
    term.clear()
    term.setCursorPos(1, 1)
end

local function at(x, y, text, fg, bg)
    term.setCursorPos(x, y)
    if bg then term.setBackgroundColour(bg) end
    if fg then term.setTextColour(fg) end
    term.write(text)
end

local function centre(y, text, fg, bg)
    if #text > W then text = text:sub(1, W) end
    at(math.floor((W - #text) / 2) + 1, y, text, fg, bg)
end

local function fill(y1, y2, bg)
    term.setBackgroundColour(bg)
    for y = y1, y2 do
        term.setCursorPos(1, y)
        term.write((" "):rep(W))
    end
end

local TOP = math.max(1, math.floor((H - 19) / 2) + 1) -- keeps the layout centred on bigger screens

-- The page every screen starts from: background, orange band, footer.
local function page(subtitle)
    term.setCursorBlink(false)
    fill(1, H, C.cyan)
    fill(TOP + 1, TOP + 3, C.orange)
    centre(TOP + 2, "P H O E N I X   O S", C.white, C.orange)
    term.setBackgroundColour(C.cyan)
    if subtitle then centre(TOP + 5, subtitle, C.white) end
    centre(H, "github.com/MADDXSTUDIOS/Phoenix-OS", C.lightBlue, C.cyan)
end

local BAR_W = math.min(41, W - 10)
local BAR_X = math.floor((W - BAR_W) / 2) + 1

local function bar(y, fraction, colour)
    local n = math.floor(BAR_W * fraction + 0.5)
    at(BAR_X, y, (" "):rep(n), nil, colour)
    at(BAR_X + n, y, (" "):rep(BAR_W - n), nil, C.gray)
    term.setBackgroundColour(C.cyan)
end

local function button(x, y, text, primary)
    at(x, y, " " .. text .. " ", primary and C.white or C.black, primary and C.blue or C.lightGray)
    term.setBackgroundColour(C.cyan)
    return { x1 = x, x2 = x + #text + 1, y = y }
end

local function hit(b, x, y) return y == b.y and x >= b.x1 and x <= b.x2 end

-- Something went wrong: say what, wait for a key, leave the computer as it was.
local function fail(title, detail)
    page()
    centre(TOP + 5, title, C.white)
    local y = TOP + 7
    for line in (tostring(detail or "") .. "\n"):gmatch("(.-)\n") do
        while #line > 0 and y < H - 3 do
            centre(y, line:sub(1, W - 4), C.lightBlue)
            line = line:sub(W - 3)
            y = y + 1
        end
    end
    centre(H - 2, "Nothing was changed. Press any key.", C.white)
    os.pullEvent("key")
    resetScreen()
    print("Phoenix OS was not installed.")
end

------------------------------------------------------------------ download helpers
local function fetch(path)
    local res, err = http.get(base .. path, nil, true)
    if not res then return nil, err end
    local body = res.readAll()
    res.close()
    return body
end

local function readFile(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    local data = f.readAll()
    f.close()
    return data
end

------------------------------------------------------------------ 1. file list
page("Connecting...")
centre(TOP + 7, branch:match("^https?://") and branch or ("Branch: " .. branch), C.lightBlue)

if not http then return fail("Can't connect", "The http API is switched off on this server.") end
local manifest, err = fetch("manifest.txt")
if not manifest then return fail("Couldn't reach GitHub", err) end

local files, version = {}, "?"
for line in manifest:gmatch("[^\r\n]+") do
    local v = line:match("^#%s*version%s*=%s*(%S+)")
    if v then version = v end
    if line:match("%S") and not line:match("^#") then files[#files + 1] = line end
end
if #files == 0 then return fail("Nothing to install", "The file list on GitHub is empty.") end

------------------------------------------------------------------ 2. confirm
local installed = (readFile("/system/manifest.txt") or ""):match("#%s*version%s*=%s*(%S+)")
local action = installed and "Reinstall" or "Install"

page(action .. " Phoenix OS " .. version)
if not branch:match("^https?://") then centre(TOP + 6, "from the " .. branch .. " branch", C.lightBlue) end
if installed then
    centre(TOP + 8, "Installed now: " .. installed, C.lightBlue)
    centre(TOP + 9, "Your accounts and files are kept.", C.lightBlue)
else
    centre(TOP + 8, #files .. " files will be downloaded.", C.lightBlue)
    centre(TOP + 9, "This replaces anything that runs at start-up.", C.lightBlue)
end
if branch ~= "main" then centre(TOP + 11, "Development builds are unfinished and may break.", C.yellow) end

local yes = button(math.floor(W / 2) - #action - 3, TOP + 13, action, true)
local no = button(math.floor(W / 2) + 2, TOP + 13, "Cancel", false)
centre(H - 1, "Enter to " .. action:lower() .. ", Esc to cancel", C.lightBlue)

while true do
    local ev, a, b, c = os.pullEvent()
    if (ev == "key" and (a == keys.enter or a == keys.numPadEnter)) or (ev == "mouse_click" and hit(yes, b, c)) then break end
    if (ev == "key" and (a == keys.escape or a == keys.backspace)) or (ev == "mouse_click" and hit(no, b, c)) then
        resetScreen()
        print("Phoenix OS was not installed.")
        return
    end
end

------------------------------------------------------------------ 3. download
page((installed and "Reinstalling" or "Installing") .. " Phoenix OS " .. version)

local function progress(done, label)
    bar(TOP + 8, done / #files, C.orange)
    local count = ("%d of %d files"):format(done, #files)
    local pct = ("%d%%"):format(math.floor(done / #files * 100))
    at(BAR_X, TOP + 9, (" "):rep(BAR_W), nil, C.cyan)
    at(BAR_X, TOP + 9, count, C.white)
    at(BAR_X + BAR_W - #pct, TOP + 9, pct, C.white)
    term.setCursorPos(1, TOP + 11)
    term.clearLine()
    centre(TOP + 11, label, C.lightBlue)
end

-- Download everything before writing anything, so a failed download can't leave half an OS.
local got = {}
for i, path in ipairs(files) do
    progress(i - 1, path)
    local body, e = fetch(path)
    if not body then return fail("Download failed", path .. "\n" .. tostring(e)) end
    got[path] = body
end

progress(#files, "Writing files...")
for path, body in pairs(got) do
    local f = fs.open(path, "wb")
    f.write(body)
    f.close()
end
-- The updater compares against this copy to know what's installed.
local f = fs.open("system/manifest.txt", "w")
f.write(manifest)
f.close()
-- Remember the branch so updates keep coming from the same place.
if not branch:match("^https?://") then
    f = fs.open("etc/update.cfg", "w")
    f.write(textutils.serialize({ branch = branch }))
    f.close()
end

------------------------------------------------------------------ 4. done
bar(TOP + 8, 1, C.lime)
term.setCursorPos(1, TOP + 11)
term.clearLine()
centre(TOP + 11, "Phoenix OS " .. version .. " installed", C.white)
for n = 3, 1, -1 do
    term.setCursorPos(1, TOP + 13)
    term.clearLine()
    centre(TOP + 13, "Restarting in " .. n .. "...", C.lightBlue)
    sleep(1)
end
os.reboot()
