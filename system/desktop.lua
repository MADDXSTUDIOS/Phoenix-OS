-- Phoenix OS desktop: wallpaper, desktop icons, the taskbar and the Start menu.
local sys = sys
local theme = sys.theme
local D = { icons = {}, selected = nil, clock = "" }
local rows = {}
local barMap = {}
local generation = 0
local lastIconClick
local START = " Phoenix "
local MENU_W = 22

local lightColours = {
    [colors.white] = true, [colors.yellow] = true, [colors.lightGray] = true, [colors.lime] = true,
    [colors.pink] = true, [colors.lightBlue] = true, [colors.orange] = true,
}

local function hexOf(c) return sys.wm.hexOf[c] end

local function put(y, x, t, f, b)
    local r = rows[y]
    if not r then return end
    local n = #t
    r[1] = r[1]:sub(1, x - 1) .. t .. r[1]:sub(x + n)
    r[2] = r[2]:sub(1, x - 1) .. f .. r[2]:sub(x + n)
    r[3] = r[3]:sub(1, x - 1) .. b .. r[3]:sub(x + n)
end

local function clockText()
    if sys.kernel.getSetting("clock.mode", "game") == "real" then return os.date("%H:%M") end
    return textutils.formatTime(os.time(), true)
end

-- Rebuild the wallpaper and icon layer (rows 1 to H-1).
local function build()
    local W, H = sys.wm.size()
    local colour = sys.kernel.getSetting("desktop.colour", theme.desktop)
    if not hexOf(colour) then colour = theme.desktop end
    local bg = hexOf(colour)
    local label = hexOf(lightColours[colour] and colors.black or colors.white)
    rows = {}
    for y = 1, H - 1 do rows[y] = { (" "):rep(W), label:rep(W), bg:rep(W) } end

    local mark = "Phoenix OS " .. sys.edition
    local markFg = colour == theme.desktop and hexOf(theme.desktopText) or label
    put(H - 2, W - #mark, mark, markFg:rep(#mark), bg:rep(#mark))

    D.icons = {}
    local col, line = 0, 0
    for _, app in ipairs(sys.kernel.appOrder) do
        if app.icon and app.desktop ~= false then
            if 2 + line * 4 + 2 > H - 1 then col, line = col + 1, 0 end
            local x, y = 2 + col * 10, 2 + line * 4
            if x + 7 <= W then
                for i = 1, 2 do
                    local part = app.icon[i]
                    if type(part) == "table" and #part[1] == 4 then
                        put(y + i - 1, x + 2, part[1], part[2]:gsub("_", bg), part[3]:gsub("_", bg))
                    end
                end
                local name = app.name:sub(1, 8)
                local pad = math.floor((8 - #name) / 2)
                local text = (" "):rep(pad) .. name .. (" "):rep(8 - #name - pad)
                local selected = D.selected == app.id
                put(y + 2, x, text, (selected and "0" or label):rep(8), (selected and hexOf(theme.select) or bg):rep(8))
                D.icons[#D.icons + 1] = { app = app, x = x, y = y }
                line = line + 1
            end
        end
    end
end

function D.refresh()
    build()
    sys.wm.dirty = true
end

function D.row(y)
    local r = rows[y]
    return r[1], r[2], r[3]
end

------------------------------------------------------------------ taskbar
function D.taskbar()
    local W = sys.wm.size()
    local WM = sys.wm
    local bar, text = hexOf(theme.taskbar), hexOf(theme.taskbarText)
    local open = WM.popup ~= nil
    local t = START
    local f = hexOf(open and theme.start or theme.startText):rep(#START)
    local b = hexOf(open and theme.startText or theme.start):rep(#START)

    local wins = {}
    for _, win in ipairs(WM.stack) do wins[#wins + 1] = win end
    table.sort(wins, function(a, c) return a.id < c.id end)
    local clock = " " .. D.clock .. " "
    local room = W - #START - #clock
    barMap = {}
    local n = #wins
    if n > 0 then
        local bw = math.min(13, math.floor(room / n))
        if bw < 4 then bw = 4; n = math.floor(room / bw) end
        for i = 1, n do
            local win = wins[i]
            local active = win == WM.active and win.state ~= "min"
            local label = " " .. win.title
            if #label > bw - 1 then label = label:sub(1, bw - 1) end
            label = label .. (" "):rep(bw - 1 - #label)
            barMap[#barMap + 1] = { x1 = #t + 1, x2 = #t + bw, win = win }
            if active then
                t = t .. label .. " "
                f = f .. ("f"):rep(bw)
                b = b .. hexOf(colors.lightGray):rep(bw)
            else
                t = t .. label .. "\149"
                f = f .. hexOf(win.state == "min" and colors.lightGray or theme.taskbarText):rep(bw - 1) .. bar
                b = b .. bar:rep(bw - 1) .. hexOf(colors.lightGray)
            end
        end
    end
    local gap = W - #t - #clock
    t = t .. (" "):rep(gap) .. clock
    f = f .. text:rep(gap + #clock)
    b = b .. bar:rep(gap + #clock)
    return t, f, b
end

------------------------------------------------------------------ start menu
local function closeMenu()
    sys.wm.popup = nil
    sys.wm.dirty = true
end

-- One column of menu items: a list of { text =, action = } / { sep = true } / { text =, group = }.
-- Returns the row text, colours for item i at width w, with sel highlighted.
local function menuRow(it, w, selected)
    local bg, fg = hexOf(theme.menu), hexOf(theme.menuText)
    if not it then return (" "):rep(w), fg:rep(w), bg:rep(w) end
    if it.sep then return ("\140"):rep(w), hexOf(colors.lightGray):rep(w), bg:rep(w) end
    -- The selected item is shown with blue text and a marker rather than a coloured bar:
    -- CC's text sits at the top of each row, so a bar makes the line below look cramped.
    local text = (selected and " \16" or "  ") .. it.text
    if selected then fg = hexOf(theme.select) end
    if it.group then text = text .. (" "):rep(w - #text - 2) .. "\16 " end
    return text .. (" "):rep(w - #text), fg:rep(w), bg:rep(w)
end

local FLY_W = 16

local function openMenu()
    local K = sys.kernel
    local _, H = sys.wm.size()
    -- Apps with a group (e.g. "Utilities") go in a sub-menu that pops out to the side.
    local items, groups = {}, {}
    for _, app in ipairs(K.appOrder) do
        if not app.hidden then
            local entry = { text = app.name, action = function() K.launchApp(app.id) end }
            if type(app.group) == "string" then
                local g = groups[app.group]
                if not g then
                    g = { text = app.group, group = app.group, items = {} }
                    groups[app.group] = g
                    items[#items + 1] = g
                end
                g.items[#g.items + 1] = entry
            else
                items[#items + 1] = entry
            end
        end
    end
    -- Plain apps first, then the groups, each keeping their order.
    local plain, grouped = {}, {}
    for _, it in ipairs(items) do
        if it.group then grouped[#grouped + 1] = it else plain[#plain + 1] = it end
    end
    items = plain
    for _, g in ipairs(grouped) do items[#items + 1] = g end
    items[#items + 1] = { sep = true }
    items[#items + 1] = { text = "Lock", action = function() K.power("lock") end }
    items[#items + 1] = { text = "Sign out", action = function() K.power("logoff") end }
    items[#items + 1] = { text = "Restart", action = function() K.power("reboot") end }
    items[#items + 1] = { text = "Shut down", action = function() K.power("shutdown") end }
    local h = math.min(#items + 2, H - 1) -- name bar, a blank line, then the items
    local menuY = H - h
    local sel = 0
    local menu

    local function closeFlyout()
        menu.flyout = nil
        sys.wm.dirty = true
    end

    local function openFlyout(i)
        local g = items[i]
        local fsel = 0
        local fh = #g.items
        local fly = { x = MENU_W + 1, w = FLY_W, h = fh, group = i }
        fly.y = math.min(menuY + i + 1, H - fh) -- line up with the group's row, but stay above the taskbar
        local function run(j)
            local it = g.items[j]
            if it then
                closeMenu()
                it.action()
            end
        end
        fly.row = function(j) return menuRow(g.items[j], FLY_W, j == fsel) end
        fly.click = function(_, _, y) run(y) end
        fly.key = function(k)
            if k == keys.down then fsel = fsel % fh + 1
            elseif k == keys.up then fsel = (fsel - 2) % fh + 1
            elseif k == keys.enter or k == keys.right then run(fsel)
            elseif k == keys.left then closeFlyout()
            end
        end
        menu.flyout = fly
        sys.wm.dirty = true
    end

    local function choose(i)
        local it = items[i]
        if not it then return end
        if it.group then
            sel = i
            if menu.flyout and menu.flyout.group == i then closeFlyout() else openFlyout(i) end
        elseif it.action then
            closeMenu()
            it.action()
        end
    end
    menu = {
        x = 1, y = menuY, w = MENU_W, h = h, close = closeMenu,
        row = function(i)
            if i == 1 then
                local name = " \2 " .. K.session.name
                if K.session.admin then name = name .. " (admin)" end
                name = name:sub(1, MENU_W)
                return name .. (" "):rep(MENU_W - #name), ("0"):rep(MENU_W), hexOf(theme.select):rep(MENU_W)
            end
            return menuRow(items[i - 2], MENU_W, i - 2 == sel)
        end,
        click = function(_, _, y)
            if menu.flyout and items[y - 2] ~= items[menu.flyout.group] then closeFlyout() end
            choose(y - 2)
        end,
        key = function(k)
            if menu.flyout then return menu.flyout.key(k) end
            local step = (k == keys.down and 1) or (k == keys.up and -1) or 0
            if step ~= 0 then
                repeat
                    sel = sel + step
                    if sel < 1 then sel = #items elseif sel > #items then sel = 1 end
                until not items[sel].sep
            elseif k == keys.enter or (k == keys.right and items[sel] and items[sel].group) then
                choose(sel)
            end
        end,
    }
    sys.wm.popup = menu
    sys.wm.dirty = true
end

function D.taskbarClick(_, x)
    local WM = sys.wm
    if x <= #START then
        if WM.popup then closeMenu() else openMenu() end
        return
    end
    for _, m in ipairs(barMap) do
        if x >= m.x1 and x <= m.x2 then
            if m.win == WM.active and m.win.state ~= "min" then WM.minimise(m.win) else WM.focusWindow(m.win) end
            return
        end
    end
end

------------------------------------------------------------------ desktop icons
function D.click(_, x, y)
    local hit
    for _, icon in ipairs(D.icons) do
        if x >= icon.x and x < icon.x + 8 and y >= icon.y and y < icon.y + 3 then hit = icon end
    end
    local now = os.epoch("utc")
    if hit and lastIconClick and lastIconClick.id == hit.app.id and now - lastIconClick.at < 500 then
        lastIconClick = nil
        D.selected = nil
        build()
        sys.kernel.launchApp(hit.app.id)
        return
    end
    lastIconClick = hit and { id = hit.app.id, at = now } or nil
    D.selected = hit and hit.app.id or nil
    D.refresh()
end

------------------------------------------------------------------ session
function D.start()
    generation = generation + 1
    local mine = generation
    D.selected = nil
    D.clock = clockText()
    build()
    local function tick()
        if generation ~= mine then return end
        local now = clockText()
        if now ~= D.clock then
            D.clock = now
            sys.wm.dirty = true
        end
        sys.kernel.after(1, tick)
    end
    sys.kernel.after(1, tick)
end

function D.stop()
    generation = generation + 1
    closeMenu()
end

return D
