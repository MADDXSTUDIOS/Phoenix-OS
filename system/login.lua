-- Phoenix OS sign-in, lock and first-run setup screens.
local sys = sys
local ui, theme = sys.ui, sys.theme
local L = {}

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Show a full-screen system screen. build(form, W, H) adds the widgets.
local function show(build)
    local WM = sys.wm
    local W, H = WM.size()
    local ov, form
    ov = WM.newOverlay(function(name, a, b, c)
        if name == "terminate" then return end
        form:event(name, a, b, c)
        if WM.overlay == ov then form:draw() end
    end)
    form = ui.form(ov.term, { bg = theme.desktop, fg = colors.white })
    build(form, W, H)
    ov.resize = function() show(build) end
    WM.overlay = ov
    form:draw()
    WM.invalidate()
    return form
end

-- The parts every system screen shares: title, white panel, edition line, computer name.
local function chrome(form, W, H, px, py, pw, ph)
    form.paint = function(t)
        local title = "P H O E N I X   O S"
        t.setBackgroundColour(theme.desktop)
        t.setTextColour(colors.white)
        t.setCursorPos(math.floor((W - #title) / 2) + 1, py - 3)
        t.write(title)
        local sub = sys.edition .. " Edition"
        t.setTextColour(theme.desktopText)
        t.setCursorPos(math.floor((W - #sub) / 2) + 1, py - 2)
        t.write(sub)
        t.setBackgroundColour(colors.white)
        for y = py, py + ph - 1 do
            t.setCursorPos(px, y)
            t.write((" "):rep(pw))
        end
        t.setBackgroundColour(theme.desktop)
        t.setTextColour(theme.desktopText)
        local foot = "Phoenix OS " .. sys.edition .. " " .. sys.version
        t.setCursorPos(math.floor((W - #foot) / 2) + 1, H)
        t.write(foot)
        local host = sys.kernel.hostname()
        t.setCursorPos(W - #host, 1)
        t.write(host)
    end
end

local function powerButtons(form, H)
    form:add(ui.button({ x = 2, y = H - 1, text = "Shut down", bg = colors.gray, fg = colors.white,
        onClick = function() sys.kernel.power("shutdown") end }))
    form:add(ui.button({ x = 14, y = H - 1, text = "Restart", bg = colors.gray, fg = colors.white,
        onClick = function() sys.kernel.power("reboot") end }))
end

local function field(form, px, y, label, w, mask)
    form:add(ui.label({ x = px + 2, y = y, text = label, fg = colors.black, bg = colors.white }))
    return form:add(ui.input({ x = px + 13, y = y, w = w, mask = mask, maxLen = 32 }))
end

------------------------------------------------------------------ first run
function L.setup()
    show(function(form, W, H)
        local pw, ph = 37, 12
        local px, py = math.floor((W - pw) / 2) + 1, 5
        chrome(form, W, H, px, py, pw, ph)
        form:add(ui.label({ x = px + 2, y = py + 1, text = "Welcome to Phoenix OS.", fg = colors.black, bg = colors.white }))
        form:add(ui.label({ x = px + 2, y = py + 2, text = "Create the administrator account:", fg = colors.gray, bg = colors.white }))
        local user = field(form, px, py + 4, "Username", 21)
        local pass = field(form, px, py + 6, "Password", 21, "\7")
        local again = field(form, px, py + 8, "Confirm", 21, "\7")
        local msg = form:add(ui.label({ x = px + 2, y = py + 9, w = pw - 4, text = "", fg = colors.red, bg = colors.white }))
        local function create()
            local name = trim(user.value):lower()
            local ok, err = sys.users.validName(name)
            if not ok then msg.text = err form:setFocus(user) return end
            if #pass.value < 1 then msg.text = "Enter a password" form:setFocus(pass) return end
            if pass.value ~= again.value then
                msg.text = "The passwords don't match"
                again:set("")
                form:setFocus(again)
                return
            end
            ok, err = sys.users.add(name, pass.value, true)
            if not ok then msg.text = err return end
            sys.kernel.log("INFO", "Setup finished: administrator " .. name .. " created")
            sys.kernel.startSession(sys.users.get(name))
        end
        user.onEnter = function() form:setFocus(pass) end
        pass.onEnter = function() form:setFocus(again) end
        again.onEnter = create
        form:add(ui.button({ x = px + pw - 18, y = py + 10, w = 16, text = "Create account", bg = colors.blue, fg = colors.white, onClick = create }))
        form:setFocus(user)
    end)
end

------------------------------------------------------------------ sign in
function L.show()
    if sys.users.count() == 0 then return L.setup() end
    show(function(form, W, H)
        local pw, ph = 33, 9
        local px, py = math.floor((W - pw) / 2) + 1, math.floor((H - ph) / 2) + 2
        chrome(form, W, H, px, py, pw, ph)
        form:add(ui.label({ x = px + 2, y = py + 1, text = "Sign in", fg = colors.gray, bg = colors.white }))
        local user = field(form, px, py + 3, "Username", 17)
        local pass = field(form, px, py + 5, "Password", 17, "\7")
        local msg = form:add(ui.label({ x = px + 2, y = py + 6, w = pw - 4, text = "", fg = colors.red, bg = colors.white }))
        local function signIn()
            local name = trim(user.value):lower()
            local account = sys.users.verify(name, pass.value)
            if account then
                sys.kernel.startSession(account)
            else
                sys.kernel.log("WARN", "Failed sign-in for '" .. name:sub(1, 16) .. "'")
                msg.text = "Wrong username or password"
                pass:set("")
                form:setFocus(pass)
            end
        end
        user.onEnter = function() form:setFocus(pass) end
        pass.onEnter = signIn
        form:add(ui.button({ x = px + pw - 13, y = py + 7, w = 11, text = "Sign in", bg = colors.blue, fg = colors.white, onClick = signIn }))
        powerButtons(form, H)
        form:setFocus(user)
    end)
end

------------------------------------------------------------------ lock
-- Programs keep running behind the lock screen; only the keyboard and mouse are held.
function L.lock()
    local K = sys.kernel
    local name = K.session.name
    K.log("INFO", name .. " locked the computer")
    show(function(form, W, H)
        local pw, ph = 33, 9
        local px, py = math.floor((W - pw) / 2) + 1, math.floor((H - ph) / 2) + 2
        chrome(form, W, H, px, py, pw, ph)
        form:add(ui.label({ x = px + 2, y = py + 1, text = "Locked", fg = colors.gray, bg = colors.white }))
        form:add(ui.label({ x = px + 2, y = py + 3, text = "\2 " .. name, fg = colors.black, bg = colors.white }))
        local pass = field(form, px, py + 5, "Password", 17, "\7")
        local msg = form:add(ui.label({ x = px + 2, y = py + 6, w = pw - 4, text = "", fg = colors.red, bg = colors.white }))
        local function unlock()
            if sys.users.verify(name, pass.value) then
                sys.wm.overlay = nil
                sys.wm.invalidate()
            else
                K.log("WARN", "Failed unlock for " .. name)
                msg.text = "Wrong password"
                pass:set("")
            end
        end
        pass.onEnter = unlock
        form:add(ui.button({ x = px + pw - 12, y = py + 7, w = 10, text = "Unlock", bg = colors.blue, fg = colors.white, onClick = unlock }))
        form:add(ui.button({ x = px + 2, y = py + 7, w = 10, text = "Sign out", onClick = function() K.power("logoff") end }))
        form:setFocus(pass)
    end)
end

return L
