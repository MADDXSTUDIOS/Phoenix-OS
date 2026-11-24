-- Settings: system information, how the desktop looks, and user accounts.
local ui = require("ui")
local t = term.current()
local user, admin = phoenix.user()
local form = ui.form(t)
local pages = { "System", "Personalise", "Users", "Updates" }
local page = 1
local startWith = ... -- "update": opened from the update notification
if startWith == "update" then page = 4 end
local NAV = 13
local rebuild

local function human(n)
    if type(n) ~= "number" then return "?" end
    if n >= 1048576 then return ("%.1fM"):format(n / 1048576) end
    return ("%dK"):format(n / 1024)
end

local function uptime(s)
    s = math.floor(s)
    if s >= 3600 then return ("%dh %dm"):format(s / 3600, s % 3600 / 60) end
    if s >= 60 then return ("%dm %ds"):format(s / 60, s % 60) end
    return s .. "s"
end

local function heading(x, text)
    form:add(ui.label({ x = x, y = 2, text = text, fg = colors.blue }))
end

local build = {}

build[1] = function(x, w)
    local i = phoenix.system.info()
    heading(x, "System")
    local rows = {
        { "Edition", i.edition .. " " .. i.version },
        { "Computer", "#" .. i.id .. "  " .. (i.label or "(no name)") },
        { "Screen", i.width .. " x " .. i.height },
        { "Storage", human(i.free) .. " free of " .. human(i.capacity) },
        { "Uptime", uptime(i.uptime) },
        { "User", user .. (admin and " (admin)" or "") },
    }
    for n, row in ipairs(rows) do
        form:add(ui.label({ x = x, y = 3 + n, text = row[1], fg = colors.gray }))
        form:add(ui.label({ x = x + 10, y = 3 + n, w = w - 10, text = row[2] }))
    end
    if admin then
        form:add(ui.button({ x = x, y = 11, text = "Rename computer", onClick = function()
            local name = ui.prompt(t, "Rename computer", "Computer name:", i.label or "")
            if name then
                local ok, err = phoenix.system.setLabel(name:match("%S") and name or nil)
                if not ok then ui.message(t, "Settings", err) end
                rebuild()
            end
        end }))
    end
end

local light = { [colors.white] = true, [colors.yellow] = true, [colors.lightGray] = true, [colors.lime] = true,
    [colors.pink] = true, [colors.lightBlue] = true, [colors.orange] = true }

build[2] = function(x)
    heading(x, "Personalise")
    form:add(ui.label({ x = x, y = 4, text = "Desktop colour" }))
    -- A two-row block of the sixteen colours; click one to use it.
    form:add({
        x = x, y = 5, w = 24, h = 2,
        hit = function(self, px, py) return px >= self.x and px < self.x + 24 and py >= self.y and py < self.y + 2 end,
        draw = function(self, tt)
            local current = phoenix.settings.get("desktop.colour", colors.cyan)
            for n = 0, 15 do
                local c = 2 ^ n
                tt.setCursorPos(self.x + (n % 8) * 3, self.y + math.floor(n / 8))
                tt.setBackgroundColor(c)
                tt.setTextColor(light[c] and colors.black or colors.white)
                tt.write(c == current and " \7 " or "   ")
            end
        end,
        click = function(self, _, px, py)
            phoenix.settings.set("desktop.colour", 2 ^ (math.floor((px - self.x) / 3) + (py - self.y) * 8))
        end,
    })
    form:add(ui.label({ x = x, y = 8, text = "Clock" }))
    form:add(ui.checkbox({
        x = x, y = 9, text = "Show real-world time",
        value = phoenix.settings.get("clock.mode", "game") == "real",
        onChange = function(_, v) phoenix.settings.set("clock.mode", v and "real" or "game") end,
    }))
    form:add(ui.label({ x = x, y = 10, text = "(otherwise Minecraft time)", fg = colors.gray }))
end

build[3] = function(x, w, h)
    heading(x, "Users")
    local users = phoenix.users.list()
    local items = {}
    for _, u in ipairs(users) do
        items[#items + 1] = " " .. u.name .. (u.admin and "  (administrator)" or "")
    end
    local list = form:add(ui.list({ x = x, y = 4, w = w, h = math.max(2, h - 7), items = items, bg = colors.lightGray }))
    local y = h - 1
    form:add(ui.button({ x = x, y = y, text = "Password", onClick = function()
        local old = ui.prompt(t, "Change password", "Current password:", "", "\7")
        if not old then return end
        local new = ui.prompt(t, "Change password", "New password:", "", "\7")
        if not new then return end
        if ui.prompt(t, "Change password", "New password again:", "", "\7") ~= new then
            ui.message(t, "Settings", "The passwords didn't match.")
            return
        end
        local ok, err = phoenix.users.setPassword(user, new, old)
        ui.message(t, "Settings", ok and "Password changed." or err)
    end }))
    if admin then
        form:add(ui.button({ x = x + 11, y = y, text = "Add", onClick = function()
            local name = ui.prompt(t, "Add user", "Username:")
            if not name then return end
            name = name:lower():gsub("%s", "")
            local pass = ui.prompt(t, "Add user", "Password for " .. name .. ":", "", "\7")
            if not pass then return end
            local makeAdmin = ui.message(t, "Add user", "Make " .. name .. " an administrator?", { "No", "Yes" }) == 2
            local ok, err = phoenix.users.add(name, pass, makeAdmin)
            if not ok then ui.message(t, "Settings", err) end
            rebuild()
        end }))
        form:add(ui.button({ x = x + 17, y = y, text = "Remove", onClick = function()
            local u = users[list.sel]
            if not u then return end
            if ui.message(t, "Remove user", "Remove " .. u.name .. "? Their files are kept.", { "Remove", "Cancel" }) == 1 then
                local ok, err = phoenix.users.remove(u.name)
                if not ok then ui.message(t, "Settings", err) end
                rebuild()
            end
        end }))
    end
end

local update = require("update")
local found, upStatus -- last check result, kept while you flick between pages

local status -- the Updates page's status line, while it's showing

local function say(text)
    upStatus = text
    if status then status.text = text end
    form:draw()
end

local function doCheck()
    say("Checking...")
    local info, err = update.check()
    found = info
    if not info then say(err)
    elseif info.available then say("An update is available.")
    else say("Phoenix OS is up to date.") end
    rebuild()
end

local function doInstall()
    if not (found and found.available) then return end
    local answer = ui.message(t, "Update Phoenix OS",
        "Phoenix OS " .. update.describe(found) .. " will be downloaded and installed.\n\n"
        .. "Your computer will need to restart afterwards, so save your work first.",
        { "Update", "Cancel" })
    if answer ~= 1 then return end
    local ok, err = update.install(found, function(done, total)
        say(("Downloading %d of %d..."):format(done, total))
    end)
    if not ok then say(err) return end
    found = nil
    -- The new files are in place; they take over at the next restart.
    if ui.message(t, "Restart required", "The update is installed. Restart now to finish updating?",
        { "Restart now", "Later" }) == 1 then
        say("Restarting...")
        sleep(0.5)
        phoenix.power.reboot()
    else
        say("Restart to finish updating.")
        rebuild()
    end
end

build[4] = function(x, w, h)
    heading(x, "Updates")
    local mine = update.installed()
    form:add(ui.label({ x = x, y = 4, text = "Installed", fg = colors.gray }))
    form:add(ui.label({ x = x + 10, y = 4, w = w - 10, text = update.describe(mine) }))
    form:add(ui.label({ x = x, y = 5, text = "Branch", fg = colors.gray }))
    form:add(ui.label({ x = x + 10, y = 5, w = w - 10, text = update.getBranch() }))
    status = form:add(ui.label({ x = x, y = 7, w = w, text = upStatus or "", fg = colors.blue }))
    local detail = form:add(ui.label({ x = x, y = 8, w = w, text = "", fg = colors.gray }))
    if found and found.available then
        detail.text = "New: " .. update.describe(found) .. (found.commit and (" [" .. found.commit .. "]") or "")
    end
    if not admin then
        form:add(ui.label({ x = x, y = h - 1, w = w, text = "Ask an administrator to update.", fg = colors.gray }))
        return
    end
    form:add(ui.checkbox({
        x = x, y = 10, text = "Check when I sign in",
        value = phoenix.settings.get("update.auto", true) ~= false,
        onChange = function(_, v) phoenix.settings.set("update.auto", v) end,
    }))
    form:add(ui.button({ x = x, y = h - 1, text = "Check", onClick = doCheck }))
    form:add(ui.button({ x = x + 8, y = h - 1, text = "Update", bg = colors.blue, fg = colors.white,
        disabled = not (found and found.available), onClick = doInstall }))
    form:add(ui.button({ x = x + 17, y = h - 1, text = "Branch", onClick = function()
        local b = ui.prompt(t, "Update branch", "Branch to update from (normally main):", update.getBranch())
        if b and b:match("%S") then
            local ok, err = update.setBranch(b:gsub("%s", ""))
            if not ok then ui.message(t, "Settings", err) end
            found, upStatus = nil, nil
            rebuild()
        end
    end }))
end

rebuild = function()
    local w, h = t.getSize()
    form:clear()
    status = nil
    form.paint = function()
        t.setBackgroundColor(colors.lightGray)
        for y = 1, h do
            t.setCursorPos(1, y)
            t.write((" "):rep(NAV))
        end
    end
    local items = {}
    for i, name in ipairs(pages) do items[i] = " " .. name end
    local nav = form:add(ui.list({ x = 1, y = 2, w = NAV, h = #pages, items = items, sel = page, bg = colors.lightGray,
        onSelect = function(_, i)
            if i ~= page then page = i; rebuild() end
        end }))
    build[page](NAV + 3, w - NAV - 4, h)
    form:setFocus(nav)
end

form.onResize = rebuild
rebuild()
if startWith == "update" and admin then
    -- Opened from the "Update available" notification: check, then offer to install.
    form:draw()
    doCheck()
    doInstall()
end
ui.run(form)
