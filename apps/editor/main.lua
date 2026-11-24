-- Editor: create and edit text files.
-- File menu: New, Open, Save, Save As, Close. Ctrl+N / Ctrl+O / Ctrl+S work too.
local ui = require("ui")
local t = term.current()
local form = ui.form(t)
local path = ... -- the file being edited, or nil for a new, unsaved one
local dirty = false
local area, status, bar

local function name() return path and fs.getName(path) or "Untitled" end

local function refreshTitle()
    phoenix.window.setTitle((dirty and "*" or "") .. name() .. " - Editor")
end

local function setPath(p)
    path = p and ("/" .. fs.combine(p, "")) or nil
end

local function load(p)
    local f = fs.open(p, "r")
    if not f then return false, "Couldn't open " .. p end
    area:setText(f.readAll() or "")
    f.close()
    return true
end

-- Ask where to save. Relative names go in the user's documents folder.
local function askPath(title)
    local default = path or "documents/" .. name() .. (path and "" or ".txt")
    local p = ui.prompt(t, title, "Save as:", default)
    if not p or not p:match("%S") then return nil end
    if p:sub(1, 1) ~= "/" then p = shell.resolve(p) end
    if fs.isDir(p) then
        ui.message(t, title, p .. " is a folder.")
        return nil
    end
    if fs.exists(p) and "/" .. fs.combine(p, "") ~= path then
        if ui.message(t, title, fs.getName(p) .. " already exists. Replace it?", { "Replace", "Cancel" }) ~= 1 then return nil end
    end
    return p
end

local function save(as)
    local p = path
    if as or not p then
        p = askPath(as and "Save as" or "Save")
        if not p then return false end
    end
    local f, err = fs.open(p, "w")
    if not f then
        ui.message(t, "Save", err or ("Couldn't save " .. p))
        return false
    end
    f.write(area:getText())
    f.close()
    setPath(p)
    dirty = false
    refreshTitle()
    return true
end

-- Before throwing work away: true means go ahead.
local function okToDiscard()
    if not dirty then return true end
    local a = ui.message(t, "Editor", "Save changes to " .. name() .. "?", { "Save", "Don't save", "Cancel" })
    if a == 1 then return save(false) end
    return a == 2
end

local function new()
    if not okToDiscard() then return end
    area:setText("")
    setPath(nil)
    dirty = false
    refreshTitle()
end

local function open()
    if not okToDiscard() then return end
    local p = ui.prompt(t, "Open", "File to open:", "documents/")
    if not p or not p:match("%S") then return end
    if p:sub(1, 1) ~= "/" then p = shell.resolve(p) end
    if not fs.exists(p) or fs.isDir(p) then
        ui.message(t, "Open", "There's no file called " .. p .. ".")
        return
    end
    local ok, err = load(p)
    if not ok then ui.message(t, "Open", err) return end
    setPath(p)
    dirty = false
    refreshTitle()
end

local function close()
    if okToDiscard() then form.done = true end
end

local function layout()
    local w, h = t.getSize()
    local keep = area
    form:clear()
    area = form:add(ui.textarea({ x = 1, y = 2, w = w, h = h - 2, onChange = function()
        if not dirty then dirty = true refreshTitle() end
    end }))
    if keep then area.lines, area.cx, area.cy, area.sx, area.sy = keep.lines, keep.cx, keep.cy, keep.sx, keep.sy end
    status = form:add({
        x = 1, y = h, w = w, h = 1, hit = function() return false end,
        draw = function(self, tt)
            local pos = ("Ln %d, Col %d"):format(area.cy, area.cx)
            local left = " " .. (path or "Untitled (not saved yet)") .. (dirty and "  (unsaved)" or "")
            tt.setCursorPos(1, h)
            tt.setBackgroundColor(colors.lightGray)
            tt.setTextColor(colors.gray)
            tt.write(ui.fit(left:sub(1, w - #pos - 2), w - #pos - 1) .. pos .. " ")
        end,
    })
    bar = form:add(ui.menubar({ x = 1, y = 1, w = w, menus = {
        { "File", {
            { "New", new, key = "Ctrl+N" },
            { "Open...", open, key = "Ctrl+O" },
            { "Save", function() save(false) end, key = "Ctrl+S" },
            { "Save as...", function() save(true) end },
            { "-" },
            { "Close", close },
        } },
    } }))
    form:setFocus(area)
end

form.onShortcut = function(k)
    if k == keys.s then save(false) return true end
    if k == keys.o then open() return true end
    if k == keys.n then new() return true end
end
form.onResize = layout

layout()
if path then
    if not path:match("^/") then path = shell.resolve(path) end
    setPath(path)
    if fs.exists(path) and not fs.isDir(path) then
        local ok, err = load(path)
        if not ok then ui.message(t, "Editor", err) end
    end
    -- a path that doesn't exist yet is a new file that will be saved there
end
refreshTitle()
ui.run(form)
