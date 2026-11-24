-- Text Viewer: read a file without being able to change it.
-- File > Edit opens it in the Editor.
local ui = require("ui")
local t = term.current()
local form = ui.form(t)
local path = ...
local area

local function load(p)
    if p:sub(1, 1) ~= "/" then p = shell.resolve(p) end
    p = "/" .. fs.combine(p, "")
    if not fs.exists(p) or fs.isDir(p) then
        ui.message(t, "Text Viewer", "There's no file called " .. p .. ".")
        return false
    end
    local f = fs.open(p, "r")
    if not f then
        ui.message(t, "Text Viewer", "Couldn't open " .. p .. ".")
        return false
    end
    area:setText(f.readAll() or "")
    f.close()
    path = p
    phoenix.window.setTitle(fs.getName(p) .. " - Text Viewer")
    return true
end

local function open()
    local p = ui.prompt(t, "Open", "File to view:", path or "documents/")
    if p and p:match("%S") then load(p) end
end

local function edit()
    if not path then return end
    phoenix.launch("editor", path)
    form.done = true
end

local function layout()
    local w, h = t.getSize()
    local keep = area
    form:clear()
    area = form:add(ui.textarea({ x = 1, y = 2, w = w, h = h - 2, readonly = true, bg = colors.white }))
    if keep then area.lines, area.sx, area.sy = keep.lines, keep.sx, keep.sy end
    form:add({
        x = 1, y = h, w = w, h = 1, hit = function() return false end,
        draw = function(_, tt)
            local info = ("%d lines  Read only "):format(#area.lines)
            tt.setCursorPos(1, h)
            tt.setBackgroundColor(colors.lightGray)
            tt.setTextColor(colors.gray)
            tt.write(ui.fit(" " .. (path or "No file open"), w - #info) .. info)
        end,
    })
    form:add(ui.menubar({ x = 1, y = 1, w = w, menus = {
        { "File", {
            { "Open...", open, key = "Ctrl+O" },
            { "Edit", edit, key = "Ctrl+E" },
            { "-" },
            { "Close", function() form.done = true end },
        } },
    } }))
    form:setFocus(area)
end

form.onShortcut = function(k)
    if k == keys.o then open() return true end
    if k == keys.e then edit() return true end
end
form.onResize = layout

layout()
if path then
    if not load(path) then path = nil end
else
    phoenix.window.setTitle("Text Viewer")
end
ui.run(form)
