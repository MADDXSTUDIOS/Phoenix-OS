-- Phoenix OS Shell: the command line. CraftOS programs (list, cd, edit, lua...) work as usual.
local user, admin = phoenix.user()
local home = "usr/" .. user
local history = {}
local running = true

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.orange)
print("Phoenix OS Shell " .. phoenix.version)
term.setTextColor(colors.lightGray)
print("Type 'help' for a list of commands.")

local builtins = {}

function builtins.help()
    term.setTextColor(colors.white)
    print("Phoenix commands:")
    term.setTextColor(colors.lightGray)
    print(" apps            list installed apps")
    print(" open <app>      open an app, e.g. open files")
    print(" ps              list running programs")
    print(" kill <pid>      stop a program")
    print(" whoami, ver     who you are, system version")
    print(" lock, logoff, reboot, shutdown")
    print(" exit            close this window")
    term.setTextColor(colors.white)
    print("CraftOS commands work too:")
    term.setTextColor(colors.lightGray)
    print(" ls cd mkdir cp mv rm edit lua wget")
end

function builtins.exit() running = false end
function builtins.whoami() print(user .. (admin and " (administrator)" or "")) end
function builtins.ver() print("Phoenix OS " .. phoenix.edition .. " " .. phoenix.version .. " on " .. _HOST) end

function builtins.apps()
    for _, app in ipairs(phoenix.apps()) do print(" " .. app.id .. string.rep(" ", 10 - #app.id) .. app.name) end
end

function builtins.open(id, ...)
    if not id then printError("Usage: open <app>") return end
    local ok, err = phoenix.launch(id:lower(), ...)
    if not ok then printError(err) end
end

function builtins.ps()
    print(" PID  User      Name")
    for _, p in ipairs(phoenix.proc.list()) do
        print((" %-4d %-9s %s"):format(p.pid, p.user:sub(1, 9), p.name))
    end
end

function builtins.kill(pid)
    pid = tonumber(pid)
    if not pid then printError("Usage: kill <pid>") return end
    local ok, err = phoenix.proc.kill(pid)
    if not ok then printError(err) end
end

function builtins.lock() phoenix.power.lock() end
function builtins.logoff() phoenix.power.logoff() end

local function prompt()
    local dir = shell.dir()
    if dir == home then dir = "~" elseif dir:sub(1, #home + 1) == home .. "/" then dir = "~" .. dir:sub(#home + 1) else dir = "/" .. dir end
    term.setTextColor(colors.orange)
    write(user)
    term.setTextColor(colors.lightGray)
    write(":")
    term.setTextColor(colors.lightBlue)
    write(dir)
    term.setTextColor(colors.white)
    write("> ")
end

while running do
    term.setBackgroundColor(colors.black)
    prompt()
    local line = read(nil, history)
    if line and line:match("%S") then
        if history[#history] ~= line then history[#history + 1] = line end
        local words = {}
        for w in line:gmatch("%S+") do words[#words + 1] = w end
        local fn = builtins[words[1]]
        if fn then
            fn(table.unpack(words, 2))
        else
            shell.run(line)
        end
    end
end
