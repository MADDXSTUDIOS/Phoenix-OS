-- Text Editor. For now this opens CraftOS's own editor in a Phoenix window
-- (press Ctrl for its Save / Exit menu). Phoenix's own editor will replace it.
local ui = require("ui")
local path = ...

if not path then
    term.setBackgroundColor(colors.white)
    term.clear()
    path = ui.prompt(term.current(), "Text Editor", "File to open or create:", "documents/untitled.txt")
    if not path or not path:match("%S") then return end
end

path = "/" .. shell.resolve(path)
if fs.isDir(path) then
    ui.message(term.current(), "Text Editor", path .. " is a folder.")
    return
end
phoenix.window.setTitle(fs.getName(path) .. " - Editor")
shell.execute("/rom/programs/edit.lua", path)
