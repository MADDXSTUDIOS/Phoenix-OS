-- Files: browse folders, make, rename and delete things, open files in the editor.
local ui = require("ui")
local t = term.current()
local user = phoenix.user()
local dir = "/" .. fs.combine((...) or ("/usr/" .. user), "")
if not fs.isDir(dir) then dir = "/" end

local form = ui.form(t)
local list, entries, status

local function human(n)
    if n >= 1048576 then return ("%.1f MB"):format(n / 1048576) end
    if n >= 1024 then return ("%.1f KB"):format(n / 1024) end
    return n .. " B"
end

local function try(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then ui.message(t, "Files", tostring(err)) end
    return ok
end

local function load()
    local w = t.getSize()
    local ok, names = pcall(fs.list, dir)
    if not ok then names = {} end
    local dirs, files = {}, {}
    for _, name in ipairs(names) do
        if name:sub(1, 1) ~= "." then
            local path = fs.combine(dir, name)
            if fs.isDir(path) then dirs[#dirs + 1] = name else files[#files + 1] = name end
        end
    end
    local function byName(a, b) return a:lower() < b:lower() end
    table.sort(dirs, byName)
    table.sort(files, byName)
    entries = {}
    local items = {}
    local nameW = math.max(8, w - 13)
    for _, name in ipairs(dirs) do
        entries[#entries + 1] = { name = name, dir = true }
        items[#items + 1] = { text = " \16 " .. name:sub(1, nameW), fg = colors.blue }
    end
    for _, name in ipairs(files) do
        local size = fs.getSize(fs.combine(dir, name))
        entries[#entries + 1] = { name = name, size = size }
        items[#items + 1] = (" %-" .. (nameW + 2) .. "s%9s"):format("  " .. name:sub(1, nameW), human(size))
    end
    list:setItems(items)
    local free = fs.getFreeSpace(dir)
    status.text = #entries .. (#entries == 1 and " item" or " items") .. (type(free) == "number" and ("   " .. human(free) .. " free") or "")
    phoenix.window.setTitle((dir == "/" and "/" or fs.getName(dir)) .. " - Files")
end

local function selected() return entries[list.sel] end
local function pathOf(e) return "/" .. fs.combine(dir, e.name) end

local function go(path)
    if fs.isDir(path) then
        dir = "/" .. fs.combine(path, "")
        load()
    else
        ui.message(t, "Files", "Can't open that folder.")
    end
end

local function up()
    if dir ~= "/" then go("/" .. fs.getDir(dir)) end
end

local function open()
    local e = selected()
    if not e then return end
    if e.dir then go(pathOf(e)) else phoenix.launch("editor", pathOf(e)) end
end

local function newFolder()
    local name = ui.prompt(t, "New folder", "Folder name:")
    if name and name:match("%S") then
        if try(fs.makeDir, fs.combine(dir, name)) then load() end
    end
end

local function rename()
    local e = selected()
    if not e then return end
    local name = ui.prompt(t, "Rename", "New name:", e.name)
    if name and name:match("%S") and name ~= e.name then
        if try(fs.move, pathOf(e), fs.combine(dir, name)) then load() end
    end
end

local function delete()
    local e = selected()
    if not e then return end
    if ui.message(t, "Delete", "Delete '" .. e.name .. "'?" .. (e.dir and " Everything inside it goes too." or ""), { "Delete", "Cancel" }) == 1 then
        if try(fs.delete, pathOf(e)) then load() end
    end
end

local function run()
    local e = selected()
    if not e or e.dir then return end
    local ok, err = phoenix.run(pathOf(e))
    if not ok then ui.message(t, "Files", tostring(err)) end
end

local function layout()
    local w, h = t.getSize()
    form:clear()
    form.paint = function()
        t.setBackgroundColor(colors.lightGray)
        t.setCursorPos(1, 1)
        t.write((" "):rep(w))
        t.setCursorPos(1, 2)
        t.setBackgroundColor(colors.gray)
        t.setTextColor(colors.white)
        t.write(ui.fit(" " .. dir, w))
    end
    local x = 2
    local function button(text, fn)
        form:add(ui.button({ x = x, y = 1, text = text, bg = colors.white, focusable = false, onClick = fn }))
        x = x + #text + 3
    end
    button("\24 Up", up)
    button("New", newFolder)
    button("Rename", rename)
    button("Delete", delete)
    button("Run", run)
    list = form:add(ui.list({ x = 1, y = 3, w = w, h = math.max(1, h - 3), onOpen = open }))
    status = form:add(ui.label({ x = 2, y = h, w = w - 2, text = "", fg = colors.gray }))
    form:setFocus(list)
    load()
end

form.onResize = layout
form.onKey = function(k)
    if k == keys.backspace then up() return true end
    if k == keys.delete then delete() return true end
    if k == keys.f5 then load() return true end
end
layout()
ui.run(form)
