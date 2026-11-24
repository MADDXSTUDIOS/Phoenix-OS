-- Files: browse folders and work with what's in them.
-- Double-click opens (text files in the Text Viewer, folders here). Right-click for
-- everything else: open, edit, run, cut, copy, paste, rename, delete, new, shortcuts.
-- Started with "::bin" it shows the Recycle Bin instead.
local ui = require("ui")
local trash = require("trash")
local t = term.current()
local user = phoenix.user()
local arg = ...
local binMode = arg == "::bin"
local dir = "/" .. fs.combine((not binMode and arg) or ("/usr/" .. user), "")
if not binMode and not fs.isDir(dir) then dir = "/" end
local DESKTOP = "/usr/" .. user .. "/desktop"
local CLIP = "/tmp/.clipboard-" .. user

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

------------------------------------------------------------------ listing
local function load()
    local w = t.getSize()
    entries = {}
    local items = {}
    local nameW = math.max(8, w - 13)
    if binMode then
        for _, item in ipairs(trash.list()) do
            entries[#entries + 1] = item
            local from = item.from and fs.getDir(item.from) or "?"
            items[#items + 1] = {
                text = (" %s %-" .. math.max(4, nameW - 12) .. "s %s"):format(item.dir and "\16" or " ",
                    item.name:sub(1, math.max(4, nameW - 12)), ("/" .. from):sub(1, 14)),
                fg = item.dir and colors.blue or nil,
            }
        end
        list:setItems(items)
        status.text = #entries == 0 and "The Recycle Bin is empty" or (#entries .. (#entries == 1 and " item" or " items"))
        phoenix.window.setTitle("Recycle Bin")
        return
    end
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
    for _, name in ipairs(dirs) do
        entries[#entries + 1] = { name = name, dir = true }
        items[#items + 1] = { text = " \16 " .. name:sub(1, nameW), fg = colors.blue }
    end
    for _, name in ipairs(files) do
        local size = fs.getSize(fs.combine(dir, name))
        local shown = name:match("%.lnk$") and ("\26 " .. name:sub(1, -5)) or ("  " .. name)
        entries[#entries + 1] = { name = name, size = size }
        items[#items + 1] = (" %-" .. (nameW + 2) .. "s%9s"):format(shown:sub(1, nameW + 2), human(size))
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
    if not binMode and dir ~= "/" then go("/" .. fs.getDir(dir)) end
end

------------------------------------------------------------------ actions
local function open()
    local e = selected()
    if not e then return end
    if e.dir then go(pathOf(e)) return end
    local ok, err = phoenix.open(pathOf(e))
    if not ok then ui.message(t, "Files", tostring(err)) end
end

local function edit()
    local e = selected()
    if not e or e.dir then return end
    phoenix.open(pathOf(e), "edit")
end

local function run()
    local e = selected()
    if not e or e.dir then return end
    local ok, err = phoenix.run(pathOf(e))
    if not ok then ui.message(t, "Files", tostring(err)) end
end

local function newFolder()
    local name = ui.prompt(t, "New folder", "Folder name:")
    if name and name:match("%S") then
        if try(fs.makeDir, fs.combine(dir, name)) then load() end
    end
end

local function newFile()
    local name = ui.prompt(t, "New text file", "File name:", "untitled.txt")
    if not name or not name:match("%S") then return end
    local p = fs.combine(dir, name)
    if fs.exists(p) then ui.message(t, "Files", name .. " already exists.") return end
    local ok = try(function()
        local f = assert(fs.open(p, "w"))
        f.close()
    end)
    if ok then
        load()
        phoenix.open("/" .. p, "edit")
    end
end

local function newItem()
    local kind = ui.message(t, "New", "What do you want to make?", { "Text file", "Folder", "Cancel" })
    if kind == 1 then newFile() elseif kind == 2 then newFolder() end
end

local function rename()
    local e = selected()
    if not e then return end
    local name = ui.prompt(t, "Rename", "New name:", e.name)
    if name and name:match("%S") and name ~= e.name then
        if fs.exists(fs.combine(dir, name)) then ui.message(t, "Files", name .. " already exists.") return end
        if try(fs.move, pathOf(e), fs.combine(dir, name)) then load() end
    end
end

-- Delete goes to the Recycle Bin. If that can't be done (say, a read-only disk),
-- offer to delete for good instead.
local function delete()
    local e = selected()
    if not e then return end
    local ok, err = trash.put(pathOf(e))
    if not ok then
        if ui.message(t, "Delete", "'" .. e.name .. "' can't go in the Recycle Bin (" .. tostring(err) .. "). Delete it for good?", { "Delete", "Cancel" }) == 1 then
            try(fs.delete, pathOf(e))
        end
    end
    load()
    if dir == DESKTOP then phoenix.refreshDesktop() end
end

-- Clipboard: one thing at a time, shared between Files windows, kept in /tmp.
local function readClip()
    local f = fs.open(CLIP, "r")
    if not f then return nil end
    local c = textutils.unserialize(f.readAll() or "")
    f.close()
    if type(c) ~= "table" or type(c.path) ~= "string" or not fs.exists(c.path) then return nil end
    return c
end

local function setClip(mode)
    local e = selected()
    if not e then return end
    local f = fs.open(CLIP, "w")
    if not f then return end
    f.write(textutils.serialize({ mode = mode, path = pathOf(e) }))
    f.close()
    status.text = (mode == "cut" and "Cut " or "Copied ") .. e.name .. ". Paste it into a folder."
end

local function paste()
    local c = readClip()
    if not c then return end
    if c.mode == "cut" and fs.getDir(c.path) == fs.combine(dir, "") then return end -- same folder, nothing to do
    local target = dir
    if fs.combine(target, "") == fs.combine(c.path, "") or ("/" .. fs.combine(target, "")):sub(1, #c.path + 1) == c.path .. "/" then
        ui.message(t, "Paste", "A folder can't go inside itself.")
        return
    end
    local name = trash.freeName(target, fs.getName(c.path))
    local ok = try(c.mode == "cut" and fs.move or fs.copy, c.path, fs.combine(target, name))
    if ok and c.mode == "cut" then fs.delete(CLIP) end
    load()
    if dir == DESKTOP then phoenix.refreshDesktop() end
end

-- A shortcut on the desktop pointing at the selected file or folder.
local function shortcut()
    local e = selected()
    if not e then return end
    if not fs.isDir(DESKTOP) then fs.makeDir(DESKTOP) end
    local label = e.name:gsub("%.lnk$", "")
    local file = trash.freeName(DESKTOP, label .. ".lnk")
    local f = fs.open(fs.combine(DESKTOP, file), "w")
    if not f then ui.message(t, "Files", "Couldn't make the shortcut.") return end
    f.write(textutils.serialize({ name = label, target = pathOf(e) }))
    f.close()
    phoenix.refreshDesktop()
    status.text = "Shortcut to " .. e.name .. " is on your desktop."
end

-- Recycle Bin view
local function restore()
    local e = selected()
    if not e then return end
    local ok, err = trash.restore(e.id)
    if not ok then ui.message(t, "Recycle Bin", tostring(err)) end
    load()
    phoenix.refreshDesktop()
end

local function purge()
    local e = selected()
    if not e then return end
    if ui.message(t, "Delete for good", "Delete '" .. e.name .. "' for good? This can't be undone.", { "Delete", "Cancel" }) == 1 then
        local ok, err = trash.purge(e.id)
        if not ok then ui.message(t, "Recycle Bin", tostring(err)) end
        load()
    end
end

local function emptyBin()
    if #entries == 0 then return end
    if ui.message(t, "Empty Recycle Bin", "Delete all " .. #entries .. " items for good? This can't be undone.", { "Empty", "Cancel" }) == 1 then
        trash.empty()
        load()
    end
end

------------------------------------------------------------------ right-click menu
local function menu(idx, x, y)
    local cx, cy = list.x + x - list.x, y
    local items
    if binMode then
        if not idx then
            items = { { "Empty Recycle Bin", emptyBin, disabled = #entries == 0 } }
        else
            items = { { "Restore", restore }, { "-" }, { "Delete for good", purge } }
        end
    elseif idx then
        local e = entries[idx]
        items = {
            { "Open", open },
            { "Edit", edit, disabled = e.dir },
            { "Run", run, disabled = e.dir or e.name:match("%.lnk$") ~= nil },
            { "-" },
            { "Cut", function() setClip("cut") end },
            { "Copy", function() setClip("copy") end },
            { "Paste", paste, disabled = readClip() == nil },
            { "-" },
            { "Rename", rename },
            { "Delete", delete },
            { "Create shortcut", shortcut, disabled = dir == DESKTOP },
        }
    else
        items = {
            { "New text file", newFile },
            { "New folder", newFolder },
            { "-" },
            { "Paste", paste, disabled = readClip() == nil },
            { "Refresh", load },
        }
    end
    ui.contextMenu(t, cx, cy, items)
end

------------------------------------------------------------------ layout
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
        t.write(ui.fit(binMode and " Deleted things. Right-click to restore." or (" " .. dir), w))
    end
    local x = 2
    local function button(text, fn)
        form:add(ui.button({ x = x, y = 1, text = text, bg = colors.white, focusable = false, onClick = fn }))
        x = x + #text + 3
    end
    if binMode then
        button("Restore", restore)
        button("Delete", purge)
        button("Empty bin", emptyBin)
    else
        button("\24", up)
        button("New", newItem)
        button("Edit", edit)
        button("Rename", rename)
        button("Delete", delete)
        button("Run", run)
    end
    list = form:add(ui.list({
        x = 1, y = 3, w = w, h = math.max(1, h - 3),
        onOpen = binMode and restore or open,
        onMenu = function(_, idx, mx, my) menu(idx, mx, my) end,
    }))
    status = form:add(ui.label({ x = 2, y = h, w = w - 2, text = "", fg = colors.gray }))
    form:setFocus(list)
    load()
end

form.onResize = layout
form.onKey = function(k)
    if k == keys.backspace then up() return true end
    if k == keys.delete then if binMode then purge() else delete() end return true end
    if k == keys.f5 then load() return true end
end
form.onShortcut = function(k)
    if binMode then return end
    if k == keys.c then setClip("copy") return true end
    if k == keys.x then setClip("cut") return true end
    if k == keys.v then paste() return true end
end
layout()
ui.run(form)
