-- Task Manager: what's running, and a button to stop it.
local ui = require("ui")
local t = term.current()
local form = ui.form(t)
local list, pids, status

local function refresh()
    local keep = pids and pids[list.sel]
    local items = {}
    pids = {}
    for _, p in ipairs(phoenix.proc.list()) do
        local cpu = p.cpu >= 1000 and ("%.1fs"):format(p.cpu / 1000) or (p.cpu .. "ms")
        items[#items + 1] = (" %-4d %-16s %-10s %7s"):format(p.pid, (p.window or p.name):sub(1, 16), p.user:sub(1, 10), cpu)
        pids[#pids + 1] = p.pid
    end
    list:setItems(items, true)
    list.sel = 0
    for i, pid in ipairs(pids) do if pid == keep then list.sel = i end end
    status.text = #items .. " running"
end

local function layout()
    local w, h = t.getSize()
    form:clear()
    form:add(ui.label({ x = 1, y = 1, w = w, text = " PID  Name             User           CPU", fg = colors.white, bg = colors.gray }))
    list = form:add(ui.list({ x = 1, y = 2, w = w, h = h - 3 }))
    status = form:add(ui.label({ x = 2, y = h, w = w - 14, text = "", fg = colors.gray }))
    form:add(ui.button({ x = w - 11, y = h, w = 11, text = "End task", bg = colors.red, fg = colors.white, onClick = function()
        local pid = pids[list.sel]
        if not pid then return end
        local ok, err = phoenix.proc.kill(pid)
        if not ok then ui.message(t, "Tasks", err) end
        refresh()
    end }))
    form:setFocus(list)
    pids = nil
    refresh()
end

form.onResize = layout
local timer = os.startTimer(1)
form.onEvent = function(ev, id)
    if ev == "timer" and id == timer then
        refresh()
        timer = os.startTimer(1)
    end
end
layout()
ui.run(form)
