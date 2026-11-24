-- Phoenix OS window manager: windows, their title bars and borders, mouse and
-- keyboard routing, and the compositor that builds each frame.
--
-- Every program draws into its own off-screen buffer. The compositor layers the
-- desktop, the windows (bottom to top), any pop-up menu and the taskbar into
-- rows of text, and only sends the rows that changed to the real screen.
local sys = sys
local native, theme = sys.native, sys.theme
local WM = { stack = {}, active = nil, dirty = true, overlay = nil, popup = nil }
local W, H
local prev = {}
local nextId = 1
local drag -- { win, mode = "move" | "resize", ox, oy, rw, rh }
local mouseTarget -- window receiving the rest of a click-drag-release
local lastTitleClick

local hexOf = {}
for i = 0, 15 do hexOf[2 ^ i] = ("%x"):format(i) end
WM.hexOf = hexOf

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

------------------------------------------------------------------ geometry
local function isMax(win) return win.state == "max" end

-- Where the program's own area sits on screen: x, y, width, height.
local function content(win)
    if isMax(win) then return 1, 2, W, H - 2 end
    return win.x + 1, win.y + 1, win.w - 2, win.h - 2
end

local function outer(win)
    if isMax(win) then return 1, 1, W, H - 1 end
    return win.x, win.y, win.w, win.h
end

local function fitBuffer(win, notify)
    local _, _, cw, ch = content(win)
    local ow, oh = win.buf.getSize()
    if ow ~= cw or oh ~= ch then
        win.buf.reposition(1, 1, cw, ch)
        if notify then sys.kernel.resume(win.proc, "term_resize") end
    end
end

------------------------------------------------------------------ windows
-- A window's terminal is a normal CC window object, wrapped so any drawing marks the screen dirty.
local function makeTerm(buf)
    local t = {}
    for k, f in pairs(buf) do
        if k:sub(1, 3) == "get" or k:sub(1, 2) == "is" then
            t[k] = f
        else
            t[k] = function(...)
                WM.dirty = true
                return f(...)
            end
        end
    end
    -- Programs must not move or hide their buffer themselves.
    t.reposition = function() end
    t.setVisible = function() end
    return t
end

function WM.create(proc, o)
    o = type(o) == "table" and o or {}
    local function num(v, default, lo, hi) return clamp(math.floor(tonumber(v) or default), lo, hi) end
    local win = {
        id = nextId, proc = proc, state = "normal",
        title = type(o.title) == "string" and o.title or proc.name,
        minW = num(o.minW, 18, 12, W), minH = num(o.minH, 5, 4, H - 1),
        fixed = o.resizable == false,
    }
    nextId = nextId + 1
    win.w = num(o.w, 40, win.minW, W)
    win.h = num(o.h, 12, win.minH, H - 1)
    -- Open near the middle, stepping down and right for each window already open.
    local step = (#WM.stack % 4) * 2
    win.x = clamp(math.floor((W - win.w) / 2) + 1 + step - 2, 1, W - win.w + 1)
    win.y = clamp(math.floor((H - 1 - win.h) / 2) + step, 1, H - win.h)
    if o.maximised and not win.fixed then win.state = "max" end
    local _, _, cw, ch = content(win)
    win.buf = window.create(native, 1, 1, cw, ch, false)
    win.term = makeTerm(win.buf)
    WM.stack[#WM.stack + 1] = win
    WM.active = win
    WM.dirty = true
    return win
end

local function topVisible()
    for i = #WM.stack, 1, -1 do
        if WM.stack[i].state ~= "min" then return WM.stack[i] end
    end
end

function WM.destroy(win)
    for i, w in ipairs(WM.stack) do
        if w == win then table.remove(WM.stack, i) break end
    end
    if drag and drag.win == win then drag = nil end
    if mouseTarget == win then mouseTarget = nil end
    if WM.active == win then WM.active = topVisible() end
    WM.dirty = true
end

function WM.focusWindow(win)
    if win.state == "min" then
        win.state = win.restore or "normal"
        fitBuffer(win, true)
    end
    for i, w in ipairs(WM.stack) do
        if w == win then table.remove(WM.stack, i) break end
    end
    WM.stack[#WM.stack + 1] = win
    WM.active = win
    WM.dirty = true
end

function WM.minimise(win)
    win.restore = win.state
    win.state = "min"
    WM.active = topVisible()
    WM.dirty = true
end

function WM.toggleMax(win)
    if win.fixed then return end
    win.state = isMax(win) and "normal" or "max"
    fitBuffer(win, true)
    WM.dirty = true
end

function WM.setTitle(win, title)
    win.title = title
    WM.dirty = true
end

------------------------------------------------------------------ drawing
local function titleRow(win, w)
    local active = win == WM.active
    local bg = hexOf[active and theme.titleActive or theme.titleInactive]
    local fg = hexOf[active and theme.titleActiveText or theme.titleInactiveText]
    local buttons = (win.fixed and "" or (" " .. (isMax(win) and "\18" or "+") .. " ")) .. " \215 "
    buttons = " _ " .. buttons
    local room = w - #buttons
    local title = " " .. win.title
    if #title > room then title = title:sub(1, math.max(0, room - 1)) .. " " end
    title = title .. (" "):rep(room - #title)
    local closeBg = active and hexOf[theme.close] or bg
    return title .. buttons, fg:rep(w - 3) .. (active and "000" or fg:rep(3)), bg:rep(w - 3) .. closeBg:rep(3)
end

-- One screen row of a window: x, text, fg, bg (or nil if the window doesn't cover that row).
local function rowOf(win, y)
    local x, y0, w, h = outer(win)
    local ry = y - y0
    if ry < 0 or ry >= h then return nil end
    if ry == 0 then return x, titleRow(win, w) end
    if isMax(win) then return x, win.buf.getLine(ry) end
    local edge = hexOf[win == WM.active and theme.titleActive or theme.titleInactive]
    local frame = hexOf[theme.frame]
    if ry == h - 1 then
        return x, "\138" .. ("\143"):rep(w - 2) .. "\133", frame:rep(w), edge:rep(w)
    end
    local t, f, b = win.buf.getLine(ry)
    return x, "\149" .. t .. "\149", edge .. f .. frame, frame .. b .. edge
end

local function splice(t, f, b, x, st, sf, sb)
    local n = #st
    local s, e = x, x + n - 1
    if e < 1 or s > W then return t, f, b end
    local a, z = 1, n
    if s < 1 then a = 2 - s; s = 1 end
    if e > W then z = n - (e - W); e = W end
    return t:sub(1, s - 1) .. st:sub(a, z) .. t:sub(e + 1),
        f:sub(1, s - 1) .. sf:sub(a, z) .. f:sub(e + 1),
        b:sub(1, s - 1) .. sb:sub(a, z) .. b:sub(e + 1)
end

function WM.invalidate()
    prev = {}
    WM.dirty = true
end

-- Build the frame and send changed rows to the screen.
function WM.flush()
    if not WM.dirty then return end
    WM.dirty = false
    local overlay, popup = WM.overlay, WM.popup
    local barT, barF, barB = sys.desktop.taskbar()
    for y = 1, H do
        local t, f, b
        if overlay then
            t, f, b = overlay.term.getLine(y)
        elseif y == H then
            t, f, b = barT, barF, barB
        else
            t, f, b = sys.desktop.row(y)
            for i = 1, #WM.stack do
                local win = WM.stack[i]
                if win.state ~= "min" then
                    local x, wt, wf, wb = rowOf(win, y)
                    if x then t, f, b = splice(t, f, b, x, wt, wf, wb) end
                end
            end
            if popup and y >= popup.y and y < popup.y + popup.h then
                t, f, b = splice(t, f, b, popup.x, popup.row(y - popup.y + 1))
            end
            local fly = popup and popup.flyout -- a sub-menu popping out of the menu
            if fly and y >= fly.y and y < fly.y + fly.h then
                t, f, b = splice(t, f, b, fly.x, fly.row(y - fly.y + 1))
            end
            local toast = WM.toast
            if toast then
                local tx, ty = W - toast.w, H - toast.h
                if y >= ty then t, f, b = splice(t, f, b, tx, toast.row(y - ty + 1)) end
            end
        end
        local p = prev[y]
        if not p or p[1] ~= t or p[2] ~= f or p[3] ~= b then
            native.setCursorPos(1, y)
            native.blit(t, f, b)
            prev[y] = { t, f, b }
        end
    end
    -- Show the text cursor of whatever has keyboard focus.
    local buf, ox, oy, cw, ch
    if overlay then
        buf, ox, oy, cw, ch = overlay.term, 1, 1, W, H
    elseif WM.active and not popup then
        buf = WM.active.buf
        ox, oy, cw, ch = content(WM.active)
    end
    if buf and buf.getCursorBlink() then
        local cx, cy = buf.getCursorPos()
        local sx, sy = ox + cx - 1, oy + cy - 1
        if cx >= 1 and cx <= cw and cy >= 1 and cy <= ch and sx >= 1 and sx <= W and sy >= 1 and sy <= (overlay and H or H - 1) then
            native.setCursorPos(sx, sy)
            native.setTextColour(buf.getTextColour())
            native.setCursorBlink(true)
            return
        end
    end
    native.setCursorBlink(false)
end

------------------------------------------------------------------ input
local function windowAt(x, y)
    for i = #WM.stack, 1, -1 do
        local win = WM.stack[i]
        if win.state ~= "min" then
            local wx, wy, w, h = outer(win)
            if x >= wx and x < wx + w and y >= wy and y < wy + h then return win end
        end
    end
end

-- What part of a window is at a screen position.
local function part(win, x, y)
    local wx, wy, w, h = outer(win)
    local rx, ry = x - wx, y - wy
    if ry == 0 then
        if rx >= w - 3 then return "close" end
        local n = w - 3
        if not win.fixed then
            if rx >= n - 3 then return "max" end
            n = n - 3
        end
        if rx >= n - 3 then return "min" end
        return "title"
    end
    if isMax(win) then return "content" end
    if ry == h - 1 then
        if win.fixed then return "frame" end
        return rx >= w - 2 and "resize" or "resize-h"
    end
    if rx == w - 1 then return win.fixed and "frame" or "resize-w" end
    if rx == 0 then return "frame" end
    return "content"
end

local function toProc(win, name, a, x, y)
    local cx, cy = content(win)
    sys.kernel.resume(win.proc, name, a, x - cx + 1, y - cy + 1)
end

local function mouse(name, a, x, y)
    if name == "mouse_drag" then
        if drag then
            local win = drag.win
            if drag.mode == "move" then
                win.x = clamp(x - drag.ox, 3 - win.w, W - 2)
                win.y = clamp(y - drag.oy, 1, H - 1)
            else
                if drag.rw then win.w = clamp(x - win.x + 1, win.minW, math.max(win.minW, W - win.x + 1)) end
                if drag.rh then win.h = clamp(y - win.y + 1, win.minH, math.max(win.minH, H - win.y)) end
                fitBuffer(win, true)
            end
        elseif mouseTarget then
            toProc(mouseTarget, name, a, x, y)
        end
        return
    elseif name == "mouse_up" then
        if drag then drag = nil
        elseif mouseTarget then toProc(mouseTarget, name, a, x, y) end
        mouseTarget = nil
        return
    elseif name == "mouse_scroll" then
        local win = not WM.popup and y < H and windowAt(x, y)
        if win and part(win, x, y) == "content" then toProc(win, name, a, x, y) end
        return
    end

    -- mouse_click
    drag, mouseTarget = nil, nil
    local toast = WM.toast
    if toast then
        local tx, ty = W - toast.w, H - toast.h
        if x >= tx and x < tx + toast.w and y >= ty and y < H then
            if WM.popup then WM.popup.close() end
            toast.click(x - tx + 1, y - ty + 1)
            return
        end
    end
    local popup = WM.popup
    if popup then
        local fly = popup.flyout
        if fly and x >= fly.x and x < fly.x + fly.w and y >= fly.y and y < fly.y + fly.h then
            fly.click(a, x - fly.x + 1, y - fly.y + 1)
            return
        end
        if x >= popup.x and x < popup.x + popup.w and y >= popup.y and y < popup.y + popup.h then
            popup.click(a, x - popup.x + 1, y - popup.y + 1)
            return
        end
        popup.close()
        if y == H then return end -- a click on the taskbar just closes the menu
    end
    if y == H then
        sys.desktop.taskbarClick(a, x)
        return
    end
    local win = windowAt(x, y)
    if not win then
        if WM.active then WM.active = nil end
        sys.desktop.click(a, x, y)
        return
    end
    if win ~= WM.active or WM.stack[#WM.stack] ~= win then WM.focusWindow(win) end
    local where = part(win, x, y)
    if where == "content" then
        mouseTarget = win
        toProc(win, name, a, x, y)
    elseif where == "close" then
        sys.kernel.kill(win.proc)
    elseif where == "max" then
        WM.toggleMax(win)
    elseif where == "min" then
        WM.minimise(win)
    elseif where == "title" then
        local now = os.epoch("utc")
        if lastTitleClick and lastTitleClick.win == win and now - lastTitleClick.at < 500 then
            lastTitleClick = nil
            WM.toggleMax(win)
        else
            lastTitleClick = { win = win, at = now }
            if not isMax(win) and a == 1 then drag = { win = win, mode = "move", ox = x - win.x, oy = y - win.y } end
        end
    elseif where == "resize" or where == "resize-w" or where == "resize-h" then
        drag = { win = win, mode = "resize", rw = where ~= "resize-h", rh = where ~= "resize-w" }
    end
end

function WM.input(name, a, b, c)
    WM.dirty = true
    if WM.overlay then
        WM.overlay.event(name, a, b, c)
    elseif name:sub(1, 5) == "mouse" then
        mouse(name, a, b, c)
    elseif name == "terminate" then
        -- Ctrl+T asks the program in front to stop; Phoenix itself never terminates.
        if WM.active then sys.kernel.resume(WM.active.proc, "terminate") end
    elseif WM.popup then
        if name == "key" then WM.popup.key(a) end
    elseif WM.active then
        sys.kernel.resume(WM.active.proc, name, a, b, c)
    end
end

------------------------------------------------------------------ system screens and dialogs
-- A full-screen buffer for the login, lock and setup screens.
function WM.newOverlay(event)
    return { term = makeTerm(window.create(native, 1, 1, W, H, false)), event = event }
end

function WM.size() return W, H end

-- A small message window owned by the system.
function WM.alert(title, text)
    if not sys.kernel.session then return end
    local ui = sys.ui
    local lines = ui.wrap(text, 34)
    while #lines > 8 do lines[#lines] = nil end
    -- Always spawned as the system, even if a program's call led here.
    sys.kernel.privileged(sys.kernel.spawn, {
        name = "Message", system = true,
        window = { title = title, w = 38, h = #lines + 6, resizable = false },
        fn = function()
            local t = term.current()
            local w, h = t.getSize()
            local form = ui.form(t)
            for i, l in ipairs(lines) do form:add(ui.label({ x = 2, y = 1 + i, text = l })) end
            form:add(ui.button({
                x = math.floor((w - 8) / 2) + 1, y = h - 1, w = 8, text = "OK",
                bg = colors.blue, fg = colors.white, onClick = function() form.done = true end,
            }))
            ui.run(form)
        end,
    })
end

-- A notification box in the bottom-right corner, just above the taskbar.
-- It stays until a button (or the X) is clicked; it doesn't take the keyboard.
--   WM.notify({ title = "...", text = "...", buttons = { { "Update", fn }, { "Later" } } })
-- Each button closes the box, then runs its function (if it has one).
function WM.notify(n)
    local ui = sys.ui
    local hex = hexOf
    local w = math.min(W - 2, math.max(30, #n.title + 6))
    local lines = ui.wrap(n.text or "", w - 4)
    local h = #lines + 4
    local buttons, bx = {}, w
    for i = #(n.buttons or {}), 1, -1 do
        local b = n.buttons[i]
        local label = " " .. b[1] .. " "
        bx = bx - #label - 1
        buttons[i] = { x = bx, label = label, fn = b[2], primary = i == 1 }
    end
    local toast = { w = w, h = h, title = n.title }
    local function close()
        if WM.toast == toast then WM.toast = nil end
        WM.dirty = true
    end
    toast.close = close
    function toast.row(i)
        local white, black = hex[theme.menu], hex[theme.menuText]
        if i == 1 then
            local t = ui.fit(" " .. n.title, w - 3) .. " \215 "
            return t, ("0"):rep(w), hex[theme.titleActive]:rep(w - 3) .. hex[theme.close]:rep(3)
        end
        local line = lines[i - 1]
        if line then return ui.fit("  " .. line, w), black:rep(w), white:rep(w) end
        if i == h - 1 and #buttons > 0 then
            local t, f, b = (" "):rep(w), black:rep(w), white:rep(w)
            for _, btn in ipairs(buttons) do
                local fg = btn.primary and hex[colors.white] or black
                local bg = btn.primary and hex[theme.titleActive] or hex[colors.lightGray]
                local s, e = btn.x, btn.x + #btn.label - 1
                t = t:sub(1, s - 1) .. btn.label .. t:sub(e + 1)
                f = f:sub(1, s - 1) .. fg:rep(#btn.label) .. f:sub(e + 1)
                b = b:sub(1, s - 1) .. bg:rep(#btn.label) .. b:sub(e + 1)
            end
            return t, f, b
        end
        return (" "):rep(w), black:rep(w), white:rep(w)
    end
    function toast.click(x, y)
        if y == 1 and x >= w - 2 then close() return end
        if y ~= h - 1 then return end
        for _, btn in ipairs(buttons) do
            if x >= btn.x and x < btn.x + #btn.label then
                close()
                if btn.fn then btn.fn() end
                return
            end
        end
    end
    WM.toast = toast
    WM.dirty = true
    return toast
end

-- Blank the screen with one line of text (shutting down, restarting).
function WM.splash(text)
    native.setBackgroundColour(theme.desktop)
    native.setTextColour(colors.white)
    native.clear()
    native.setCursorPos(math.floor((W - #text) / 2) + 1, math.floor(H / 2))
    native.write(text)
    native.setCursorBlink(false)
    prev = {}
end

function WM.resize()
    W, H = native.getSize()
    for _, win in ipairs(WM.stack) do
        if not isMax(win) then
            win.w, win.h = math.min(win.w, W), math.min(win.h, H - 1)
            win.x, win.y = clamp(win.x, 3 - win.w, W - 2), clamp(win.y, 1, H - 1)
        end
        fitBuffer(win, true)
    end
    if WM.overlay and WM.overlay.resize then WM.overlay.resize() end
    sys.desktop.refresh()
    WM.invalidate()
end

function WM.init()
    W, H = native.getSize()
    for colour, rgb in pairs(theme.palette) do native.setPaletteColour(colour, rgb) end
    native.setBackgroundColour(colors.black)
    native.clear()
    WM.invalidate()
end

return WM
