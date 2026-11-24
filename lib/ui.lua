-- Phoenix UI: a small widget toolkit used by the system screens and by apps.
--
--   local ui = require("ui")
--   local form = ui.form(term.current())
--   form:add(ui.label({ x = 2, y = 2, text = "Hello" }))
--   form:add(ui.button({ x = 2, y = 4, text = "Close", onClick = function() form.done = true end }))
--   ui.run(form)
--
-- Everything is laid out in character cells. Forms redraw fully on every event,
-- which is cheap because the window manager only sends changed rows to the screen.
local ui = {}

local function class(base)
    local c = setmetatable({}, { __index = base })
    c.__index = c
    return c
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function fit(s, w)
    if #s > w then return s:sub(1, w) end
    return s .. (" "):rep(w - #s)
end
ui.fit = fit

-- Word-wrap text to a width. Returns a list of lines.
function ui.wrap(text, width)
    local lines = {}
    for para in (tostring(text) .. "\n"):gmatch("(.-)\n") do
        local line = ""
        for word in para:gmatch("%S+") do
            while #word > width do
                if #line > 0 then lines[#lines + 1] = line; line = "" end
                lines[#lines + 1] = word:sub(1, width)
                word = word:sub(width + 1)
            end
            if #line == 0 then
                line = word
            elseif #line + 1 + #word <= width then
                line = line .. " " .. word
            else
                lines[#lines + 1] = line
                line = word
            end
        end
        lines[#lines + 1] = line
    end
    return lines
end

------------------------------------------------------------------ widgets
local Widget = {}
Widget.__index = Widget
function Widget:hit(x, y)
    return x >= self.x and x < self.x + self.w and y >= self.y and y < self.y + (self.h or 1)
end

-- Label: { x, y, text, fg, bg, w, align = "left" | "centre" | "right" }
local Label = class(Widget)
function ui.label(o) return setmetatable(o, Label) end
function Label:hit() return false end
function Label:draw(t, form)
    local s = tostring(self.text)
    if self.w then
        if self.align == "centre" and #s < self.w then
            s = (" "):rep(math.floor((self.w - #s) / 2)) .. s
        elseif self.align == "right" and #s < self.w then
            s = (" "):rep(self.w - #s) .. s
        end
        s = fit(s, self.w)
    end
    t.setCursorPos(self.x, self.y)
    t.setBackgroundColour(self.bg or form.bg)
    t.setTextColour(self.fg or form.fg)
    t.write(s)
end

-- Button: { x, y, w, text, fg, bg, onClick, disabled }
local Button = class(Widget)
function ui.button(o)
    o.w = o.w or (#o.text + 2)
    if o.focusable == nil then o.focusable = true end
    return setmetatable(o, Button)
end
function Button:draw(t, _, focused)
    local s = self.text
    if #s > self.w then s = s:sub(1, self.w) end
    local pad = self.w - #s
    local left = math.floor(pad / 2)
    s = (" "):rep(left) .. s .. (" "):rep(pad - left)
    if focused and pad >= 2 then s = "\16" .. s:sub(2, -2) .. "\17" end
    t.setCursorPos(self.x, self.y)
    t.setBackgroundColour(self.bg or colors.lightGray)
    t.setTextColour(self.disabled and colors.gray or (self.fg or colors.black))
    t.write(s)
end
function Button:click()
    if not self.disabled and self.onClick then self.onClick(self) end
end
function Button:key(k)
    if k == keys.enter or k == keys.space then self:click() return true end
end

-- Input: { x, y, w, value, mask, placeholder, maxLen, onEnter, onChange }
local Input = class(Widget)
function ui.input(o)
    o.value = o.value or ""
    o.pos, o.scroll, o.focusable = #o.value, 0, true
    return setmetatable(o, Input)
end
function Input:set(v) self.value = v or ""; self.pos = #self.value; self.scroll = 0 end
function Input:draw(t, _, focused)
    local w = self.w
    if self.pos - self.scroll >= w then self.scroll = self.pos - w + 1 end
    if self.pos < self.scroll then self.scroll = self.pos end
    local shown = self.mask and self.mask:rep(#self.value) or self.value
    local s = shown:sub(self.scroll + 1, self.scroll + w)
    t.setCursorPos(self.x, self.y)
    t.setBackgroundColour(self.bg or colors.lightGray)
    if #self.value == 0 and self.placeholder and not focused then
        t.setTextColour(colors.gray)
        s = self.placeholder:sub(1, w)
    else
        t.setTextColour(self.fg or colors.black)
    end
    t.write(fit(s, w))
end
function Input:cursor() return self.x + self.pos - self.scroll, self.y end
function Input:char(c)
    c = c:gsub("[\r\n]", "")
    if self.maxLen and #self.value + #c > self.maxLen then c = c:sub(1, self.maxLen - #self.value) end
    if #c == 0 then return end
    self.value = self.value:sub(1, self.pos) .. c .. self.value:sub(self.pos + 1)
    self.pos = self.pos + #c
    if self.onChange then self.onChange(self) end
end
function Input:key(k)
    if k == keys.backspace then
        if self.pos > 0 then
            self.value = self.value:sub(1, self.pos - 1) .. self.value:sub(self.pos + 1)
            self.pos = self.pos - 1
            if self.onChange then self.onChange(self) end
        end
    elseif k == keys.delete then
        if self.pos < #self.value then
            self.value = self.value:sub(1, self.pos) .. self.value:sub(self.pos + 2)
            if self.onChange then self.onChange(self) end
        end
    elseif k == keys.left then self.pos = math.max(0, self.pos - 1)
    elseif k == keys.right then self.pos = math.min(#self.value, self.pos + 1)
    elseif k == keys.home then self.pos = 0
    elseif k == keys["end"] then self.pos = #self.value
    elseif k == keys.enter then
        if self.onEnter then self.onEnter(self) end
    else
        return false
    end
    return true
end
function Input:click(_, x) self.pos = clamp(self.scroll + x - self.x, 0, #self.value) end

-- List: { x, y, w, h, items, sel, onSelect, onOpen }. Items are strings or { text =, fg = }.
local List = class(Widget)
function ui.list(o)
    o.items, o.sel, o.top, o.focusable = o.items or {}, o.sel or 0, 1, true
    return setmetatable(o, List)
end
function List:ensure()
    local n = #self.items
    if self.sel > n then self.sel = n end
    if self.sel > 0 then
        if self.sel < self.top then self.top = self.sel end
        if self.sel >= self.top + self.h then self.top = self.sel - self.h + 1 end
    end
    self.top = clamp(self.top, 1, math.max(1, n - self.h + 1))
end
function List:setItems(items, keepSel)
    self.items = items
    if not keepSel then self.sel, self.top = 0, 1 end
    self:ensure()
end
function List:draw(t, form, focused)
    self:ensure()
    local n = #self.items
    local bar = n > self.h
    local w = self.w - (bar and 1 or 0)
    local bg0, fg0 = self.bg or form.bg, self.fg or form.fg
    for i = 0, self.h - 1 do
        local idx = self.top + i
        local it = self.items[idx]
        local text, fg, bg = "", fg0, bg0
        if it then
            if type(it) == "table" then text, fg = it.text, it.fg or fg0 else text = it end
            if idx == self.sel then
                bg = focused and colors.blue or colors.lightGray
                fg = focused and colors.white or colors.black
            end
        end
        t.setCursorPos(self.x, self.y + i)
        t.setBackgroundColour(bg)
        t.setTextColour(fg)
        t.write(fit(text, w))
    end
    if bar then
        local thumb = math.max(1, math.floor(self.h * self.h / n + 0.5))
        local maxTop = n - self.h + 1
        local pos = math.floor((self.top - 1) / (maxTop - 1) * (self.h - thumb) + 0.5)
        for i = 0, self.h - 1 do
            t.setCursorPos(self.x + self.w - 1, self.y + i)
            t.setBackgroundColour((i >= pos and i < pos + thumb) and colors.gray or colors.lightGray)
            t.write(" ")
        end
    end
end
function List:select(idx)
    if idx < 1 or idx > #self.items then return end
    self.sel = idx
    self:ensure()
    if self.onSelect then self.onSelect(self, idx) end
end
function List:click(button, x, y)
    local idx = self.top + (y - self.y)
    if button == 2 then
        if self.items[idx] then self:select(idx) else self.sel = 0 end
        if self.onMenu then self.onMenu(self, self.items[idx] and idx or nil, x, y) end
        return
    end
    if not self.items[idx] then return end
    local now = os.epoch("utc")
    local double = idx == self.sel and self.lastClick and now - self.lastClick < 500
    self.lastClick = now
    self:select(idx)
    if double and self.onOpen then
        self.lastClick = nil
        self.onOpen(self, idx)
    end
end
function List:scroll(dir)
    self.top = clamp(self.top + dir, 1, math.max(1, #self.items - self.h + 1))
end
function List:key(k)
    local n = #self.items
    if n == 0 then return false end
    if k == keys.up then self:select(math.max(1, self.sel - 1))
    elseif k == keys.down then self:select(math.min(n, self.sel + 1))
    elseif k == keys.pageUp then self:select(math.max(1, self.sel - self.h))
    elseif k == keys.pageDown then self:select(math.min(n, math.max(1, self.sel) + self.h))
    elseif k == keys.home then self:select(1)
    elseif k == keys["end"] then self:select(n)
    elseif k == keys.enter then
        if self.sel > 0 and self.onOpen then self.onOpen(self, self.sel) end
    else
        return false
    end
    return true
end

-- Checkbox: { x, y, text, value, onChange }
local Check = class(Widget)
function ui.checkbox(o)
    o.w, o.focusable = #o.text + 4, true
    return setmetatable(o, Check)
end
function Check:draw(t, form, focused)
    t.setCursorPos(self.x, self.y)
    t.setBackgroundColour(self.bg or form.bg)
    t.setTextColour(focused and colors.blue or (self.fg or form.fg))
    t.write((self.value and "[x] " or "[ ] ") .. self.text)
end
function Check:click()
    self.value = not self.value
    if self.onChange then self.onChange(self, self.value) end
end
function Check:key(k)
    if k == keys.space or k == keys.enter then self:click() return true end
end

-- Menu bar: { x, y, w, menus = { { "File", { { "Open", fn }, { "-" }, { "Close", fn, key = "Ctrl+W" } } } } }
-- Click a heading (or press Alt) to drop its menu down; click an item to run it.
-- Add it to the form last, so its dropdown draws on top and gets clicks first.
local MenuBar = class(Widget)
function ui.menubar(o)
    o.h, o.open, o.sel = 1, nil, 0
    o.dropW = {}
    for i, m in ipairs(o.menus) do
        local wd = 10
        for _, it in ipairs(m[2]) do wd = math.max(wd, #it[1] + 4 + (it.key and #it.key + 1 or 0)) end
        o.dropW[i] = wd
    end
    return setmetatable(o, MenuBar)
end
function MenuBar:headX(i)
    local x = self.x + 1
    for j = 1, i - 1 do x = x + #self.menus[j][1] + 2 end
    return x
end
function MenuBar:hit(x, y)
    if self.open then return true end -- while a menu is down, every click comes here
    return y == self.y and x >= self.x and x < self.x + self.w
end
function MenuBar:draw(t, form)
    t.setCursorPos(self.x, self.y)
    t.setBackgroundColour(colors.lightGray)
    t.write((" "):rep(self.w))
    for i, m in ipairs(self.menus) do
        t.setCursorPos(self:headX(i), self.y)
        local open = self.open == i
        t.setBackgroundColour(open and colors.blue or colors.lightGray)
        t.setTextColour(open and colors.white or colors.black)
        t.write(" " .. m[1] .. " ")
    end
    if self.open then
        local items, dw = self.menus[self.open][2], self.dropW[self.open]
        local dx = self:headX(self.open)
        t.setBackgroundColour(colors.lightGray) -- shadow, as on right-click menus
        for j = 2, #items do
            t.setCursorPos(dx + dw, self.y + j)
            t.write(" ")
        end
        t.setCursorPos(dx + 1, self.y + #items + 1)
        t.write((" "):rep(dw))
        for j, it in ipairs(items) do
            t.setCursorPos(dx, self.y + j)
            if it[1] == "-" then
                t.setBackgroundColour(colors.white)
                t.setTextColour(colors.lightGray)
                t.write(("\140"):rep(dw))
            else
                local sel = j == self.sel
                t.setBackgroundColour(sel and colors.blue or colors.white)
                t.setTextColour(it.disabled and colors.lightGray or (sel and colors.white or colors.black))
                local text = " " .. it[1]
                local keyText = it.key and (it.key .. " ") or ""
                t.write(text .. (" "):rep(dw - #text - #keyText) .. keyText)
            end
        end
    end
end
function MenuBar:close() self.open, self.sel = nil, 0 end
function MenuBar:run(j)
    local it = self.open and self.menus[self.open][2][j]
    if not it or it[1] == "-" or it.disabled then return end
    self:close()
    if it[2] then it[2]() end
end
function MenuBar:click(_, x, y)
    if self.open then
        local dx, dw = self:headX(self.open), self.dropW[self.open]
        local items = self.menus[self.open][2]
        if x >= dx and x < dx + dw and y > self.y and y <= self.y + #items then
            return self:run(y - self.y)
        end
    end
    if y == self.y then
        for i, m in ipairs(self.menus) do
            local hx = self:headX(i)
            if x >= hx and x < hx + #m[1] + 2 then
                if self.open == i then self:close() else self.open, self.sel = i, 0 end
                return
            end
        end
    end
    self:close()
end
function MenuBar:key(k)
    if not self.open then return false end
    local items = self.menus[self.open][2]
    if k == keys.down or k == keys.up then
        local step = k == keys.down and 1 or -1
        for _ = 1, #items do
            self.sel = (self.sel - 1 + step) % #items + 1
            if items[self.sel][1] ~= "-" then break end
        end
    elseif k == keys.left or k == keys.right then
        self.open = (self.open - 1 + (k == keys.right and 1 or -1)) % #self.menus + 1
        self.sel = 0
    elseif k == keys.enter then
        self:run(self.sel)
    else
        self:close()
    end
    return true
end

-- Right-click menu: ui.contextMenu(target, x, y, { { "Open", fn }, { "-" }, { "Delete", fn, disabled = true } })
-- Draws a menu at x, y (moved to fit), waits for a choice, then runs that item's function.
-- Clicking anywhere else closes it. Returns the chosen item's label, or nil.
function ui.contextMenu(t, x, y, items)
    local W, H = t.getSize()
    local w = 8
    for _, it in ipairs(items) do w = math.max(w, #it[1] + 3) end
    local h = #items
    x = clamp(x, 1, math.max(1, W - w))
    y = clamp(y, 1, math.max(1, H - h))
    local sel = 0
    local function draw()
        -- a grey shadow on the right and underneath, so the menu stands out on white
        t.setBackgroundColour(colors.lightGray)
        for i = 2, h do
            t.setCursorPos(x + w, y + i - 1)
            t.write(" ")
        end
        t.setCursorPos(x + 1, y + h)
        t.write((" "):rep(w))
        for i, it in ipairs(items) do
            t.setCursorPos(x, y + i - 1)
            if it[1] == "-" then
                t.setBackgroundColour(colors.white)
                t.setTextColour(colors.lightGray)
                t.write(("\140"):rep(w))
            else
                t.setBackgroundColour(i == sel and colors.blue or colors.white)
                t.setTextColour(it.disabled and colors.lightGray or (i == sel and colors.white or colors.black))
                t.write(fit(" " .. it[1], w))
            end
        end
        t.setCursorBlink(false)
    end
    local function pick(i)
        local it = items[i]
        if not it or it[1] == "-" or it.disabled then return false end
        if it[2] then it[2]() end
        return true, it[1]
    end
    while true do
        draw()
        local ev, a, b, c = os.pullEvent()
        if ev == "mouse_click" then
            if b >= x and b < x + w and c >= y and c < y + h then
                local ok, label = pick(c - y + 1)
                if ok then return label end
            else
                return nil
            end
        elseif ev == "key" then
            if a == keys.down or a == keys.up then
                local step = a == keys.down and 1 or -1
                for _ = 1, #items do
                    sel = (sel - 1 + step) % #items + 1
                    if items[sel][1] ~= "-" and not items[sel].disabled then break end
                end
            elseif a == keys.enter then
                local ok, label = pick(sel)
                if ok then return label end
            elseif a ~= keys.leftCtrl and a ~= keys.rightCtrl then
                return nil
            end
        elseif ev == "term_resize" then
            return nil
        end
    end
end

-- Text area: { x, y, w, h, lines = { "..." }, readonly, onChange }
-- A scrolling block of editable (or read-only) text with a cursor.
local TextArea = class(Widget)
function ui.textarea(o)
    o.lines = o.lines or { "" }
    o.cx, o.cy, o.sx, o.sy, o.focusable = 1, 1, 0, 0, true
    return setmetatable(o, TextArea)
end
function TextArea:setText(text)
    local lines = {}
    text = (text or ""):gsub("\r\n", "\n"):gsub("\t", "    ")
    for line in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    if #lines > 1 and lines[#lines] == "" then lines[#lines] = nil end
    self.lines, self.cx, self.cy, self.sx, self.sy = lines, 1, 1, 0, 0
end
function TextArea:getText() return table.concat(self.lines, "\n") .. "\n" end
function TextArea:fix()
    local n = #self.lines
    self.cy = clamp(self.cy, 1, n)
    self.cx = clamp(self.cx, 1, #self.lines[self.cy] + 1)
    if self.readonly then
        self.sy = clamp(self.sy, 0, math.max(0, n - self.h))
        return
    end
    if self.cy - self.sy > self.h then self.sy = self.cy - self.h end
    if self.cy <= self.sy then self.sy = self.cy - 1 end
    if self.cx - self.sx > self.w then self.sx = self.cx - self.w end
    if self.cx <= self.sx then self.sx = math.max(0, self.cx - 1) end
end
function TextArea:draw(t, form)
    self:fix()
    t.setBackgroundColour(self.bg or colors.white)
    t.setTextColour(self.fg or colors.black)
    for i = 1, self.h do
        local line = self.lines[self.sy + i]
        t.setCursorPos(self.x, self.y + i - 1)
        t.write(fit(line and line:sub(self.sx + 1, self.sx + self.w) or "", self.w))
    end
end
function TextArea:cursor()
    if self.readonly then return nil end
    return self.x + self.cx - 1 - self.sx, self.y + self.cy - 1 - self.sy
end
function TextArea:changed()
    if self.onChange then self.onChange(self) end
end
function TextArea:insert(text)
    if self.readonly then return end
    local line = self.lines[self.cy]
    local before, after = line:sub(1, self.cx - 1), line:sub(self.cx)
    local parts = {}
    for p in (text .. "\n"):gmatch("(.-)\n") do parts[#parts + 1] = p end
    if #parts == 1 then
        self.lines[self.cy] = before .. parts[1] .. after
        self.cx = self.cx + #parts[1]
    else
        self.lines[self.cy] = before .. parts[1]
        for i = 2, #parts do table.insert(self.lines, self.cy + i - 1, parts[i]) end
        self.cy = self.cy + #parts - 1
        self.cx = #self.lines[self.cy] + 1
        self.lines[self.cy] = self.lines[self.cy] .. after
    end
    self:changed()
end
function TextArea:char(c)
    if ui.ctrl then return end -- Ctrl+letter is a shortcut, not typing
    self:insert((c:gsub("\t", "    ")))
end
function TextArea:key(k)
    local L = self.lines
    if self.readonly then
        if k == keys.up then self.sy = self.sy - 1
        elseif k == keys.down then self.sy = self.sy + 1
        elseif k == keys.pageUp then self.sy = self.sy - self.h
        elseif k == keys.pageDown then self.sy = self.sy + self.h
        elseif k == keys.home then self.sy = 0
        elseif k == keys["end"] then self.sy = #L
        elseif k == keys.left then self.sx = math.max(0, self.sx - 4)
        elseif k == keys.right then self.sx = self.sx + 4
        else return false end
        return true
    end
    if k == keys.left then
        if self.cx > 1 then self.cx = self.cx - 1 elseif self.cy > 1 then self.cy = self.cy - 1; self.cx = #L[self.cy] + 1 end
    elseif k == keys.right then
        if self.cx <= #L[self.cy] then self.cx = self.cx + 1 elseif self.cy < #L then self.cy = self.cy + 1; self.cx = 1 end
    elseif k == keys.up then self.cy = self.cy - 1
    elseif k == keys.down then self.cy = self.cy + 1
    elseif k == keys.pageUp then self.cy = self.cy - self.h
    elseif k == keys.pageDown then self.cy = self.cy + self.h
    elseif k == keys.home then self.cx = 1
    elseif k == keys["end"] then self.cx = #L[self.cy] + 1
    elseif k == keys.enter then
        local indent = L[self.cy]:match("^%s*")
        self:insert("\n" .. indent)
    elseif k == keys.tab then self:insert("    ")
    elseif k == keys.backspace then
        if self.cx > 1 then
            L[self.cy] = L[self.cy]:sub(1, self.cx - 2) .. L[self.cy]:sub(self.cx)
            self.cx = self.cx - 1
            self:changed()
        elseif self.cy > 1 then
            self.cx = #L[self.cy - 1] + 1
            L[self.cy - 1] = L[self.cy - 1] .. L[self.cy]
            table.remove(L, self.cy)
            self.cy = self.cy - 1
            self:changed()
        end
    elseif k == keys.delete then
        if self.cx <= #L[self.cy] then
            L[self.cy] = L[self.cy]:sub(1, self.cx - 1) .. L[self.cy]:sub(self.cx + 1)
            self:changed()
        elseif self.cy < #L then
            L[self.cy] = L[self.cy] .. L[self.cy + 1]
            table.remove(L, self.cy + 1)
            self:changed()
        end
    else
        return false
    end
    self:fix()
    return true
end
function TextArea:click(_, x, y)
    if self.readonly then return end
    self.cy = self.sy + (y - self.y) + 1
    self.cx = self.sx + (x - self.x) + 1
    self:fix()
end
function TextArea:scroll(dir)
    self.sy = clamp(self.sy + dir * 2, 0, math.max(0, #self.lines - self.h))
    if not self.readonly then self.cy = clamp(self.cy, self.sy + 1, self.sy + self.h) end
end

------------------------------------------------------------------ form
local Form = {}
Form.__index = Form

-- ui.form(target, { bg, fg, paint = function(t) end, noClear })
function ui.form(t, o)
    o = o or {}
    return setmetatable({
        t = t, widgets = {}, bg = o.bg or colors.white, fg = o.fg or colors.black,
        paint = o.paint, noClear = o.noClear,
    }, Form)
end

function Form:add(w)
    w.form = self
    self.widgets[#self.widgets + 1] = w
    if w.focusable and not self.focus and not w.disabled then self.focus = w end
    return w
end

function Form:clear()
    self.widgets, self.focus = {}, nil
end

function Form:setFocus(w) self.focus = w end

function Form:focusNext(back)
    local list = {}
    for _, w in ipairs(self.widgets) do
        if w.focusable and not w.hidden and not w.disabled then list[#list + 1] = w end
    end
    if #list == 0 then self.focus = nil return end
    local at = 0
    for i, w in ipairs(list) do if w == self.focus then at = i end end
    at = at + (back and -1 or 1)
    if at < 1 then at = #list elseif at > #list then at = 1 end
    self.focus = list[at]
end

function Form:draw()
    local t = self.t
    t.setCursorBlink(false)
    if not self.noClear then
        t.setBackgroundColour(self.bg)
        t.clear()
    end
    if self.paint then self.paint(t) end
    for _, w in ipairs(self.widgets) do
        if not w.hidden then w:draw(t, self, w == self.focus) end
    end
    local f = self.focus
    if f and f.cursor and not f.hidden then
        local cx, cy = f:cursor()
        if cx then -- a read-only text box has no cursor
            t.setCursorPos(cx, cy)
            t.setTextColour(f.fg or colors.black)
            t.setCursorBlink(true)
        end
    end
end

-- Feed one event to the form. Returns true if a widget used it.
function Form:event(ev, a, b, c)
    if ev == "mouse_click" then
        for i = #self.widgets, 1, -1 do
            local w = self.widgets[i]
            if not w.hidden and w:hit(b, c) then
                if w.focusable and not w.disabled then self.focus = w end
                if w.click then w:click(a, b, c) end
                return true
            end
        end
    elseif ev == "mouse_scroll" then
        for i = #self.widgets, 1, -1 do
            local w = self.widgets[i]
            if not w.hidden and w.scroll and w:hit(b, c) then w:scroll(a) return true end
        end
    elseif ev == "key" or ev == "key_up" then
        -- Ctrl is tracked for the whole program, not per form: a dialog opened by a
        -- shortcut gets the key release, and the form underneath must hear about it too.
        if a == keys.leftCtrl or a == keys.rightCtrl then ui.ctrl = ev == "key" return true end
        if ev == "key_up" then return false end
        -- an open menu bar takes the keyboard
        for _, w in ipairs(self.widgets) do
            if w.open and w.key and w:key(a, b) then return true end
        end
        if ui.ctrl and self.onShortcut and self.onShortcut(a) then return true end
        if a == keys.tab and not (self.focus and self.focus.lines and not self.focus.readonly) then self:focusNext() return true end
        local f = self.focus
        if f and f.key and f:key(a, b) then return true end
        if self.onKey then return self.onKey(a, b) end
    elseif ev == "char" or ev == "paste" then
        local f = self.focus
        if f and f.char then f:char(a) return true end
    elseif ev == "term_resize" then
        if self.onResize then self.onResize() return true end
    end
    return false
end

-- Run a form until something sets form.done. Other events go to form.onEvent.
function ui.run(form)
    form.done = false
    while not form.done do
        form:draw()
        local ev = table.pack(os.pullEvent())
        if not form:event(table.unpack(ev, 1, ev.n)) and form.onEvent then
            form.onEvent(table.unpack(ev, 1, ev.n))
        end
    end
    form.t.setCursorBlink(false)
    return form.result
end

------------------------------------------------------------------ dialogs
-- These draw a box over whatever is on the target and wait for an answer.
local function box(t, title, bodyLines, footerH, minW)
    local W, H = t.getSize()
    local w = math.max(minW or 20, #title + 4)
    for _, l in ipairs(bodyLines) do w = math.max(w, #l + 4) end
    w = math.min(w, W)
    local h = math.min(#bodyLines + footerH + 3, H)
    local x, y = math.floor((W - w) / 2) + 1, math.max(1, math.floor((H - h) / 2) + 1)
    local form = ui.form(t, { noClear = true, bg = colors.white })
    form.paint = function()
        t.setCursorPos(x, y)
        t.setBackgroundColour(colors.blue)
        t.setTextColour(colors.white)
        t.write(fit(" " .. title, w))
        t.setBackgroundColour(colors.white)
        t.setTextColour(colors.black)
        for i = 1, h - 1 do
            t.setCursorPos(x, y + i)
            t.write(fit("  " .. (bodyLines[i - 1] or ""), w))
        end
    end
    return form, x, y, w, h
end

-- ui.message(target, title, text, { "OK", "Cancel" }) -> index of the button pressed
function ui.message(t, title, text, buttons)
    buttons = buttons or { "OK" }
    local W = t.getSize()
    local lines = ui.wrap(text, math.max(10, W - 6))
    local form, x, y, w, h = box(t, title, lines, 1, 22)
    local total = 0
    for _, b in ipairs(buttons) do total = total + #b + 5 end
    local bx = x + w - total
    for i, b in ipairs(buttons) do
        form:add(ui.button({
            x = bx, y = y + h - 2, w = #b + 4, text = b,
            bg = i == 1 and colors.blue or colors.lightGray, fg = i == 1 and colors.white or colors.black,
            onClick = function() form.result = i; form.done = true end,
        }))
        bx = bx + #b + 5
    end
    return ui.run(form)
end

-- ui.prompt(target, title, label, default, mask) -> text, or nil if cancelled
function ui.prompt(t, title, label, default, mask)
    local form, x, y, w, h = box(t, title, { label, "" }, 1, 30)
    local input = form:add(ui.input({ x = x + 2, y = y + 3, w = w - 4, value = default or "", mask = mask }))
    local function ok() form.result = input.value; form.done = true end
    input.onEnter = ok
    form:add(ui.button({ x = x + w - 20, y = y + h - 2, w = 8, text = "OK", bg = colors.blue, fg = colors.white, onClick = ok }))
    form:add(ui.button({ x = x + w - 11, y = y + h - 2, w = 10, text = "Cancel", onClick = function() form.done = true end }))
    return ui.run(form)
end

return ui
