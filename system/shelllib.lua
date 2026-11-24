-- The `shell` API every Phoenix process gets, so ordinary CraftOS programs
-- (edit, list, copy, lua, wget...) run unchanged inside a Phoenix window.
-- It is Phoenix's own implementation; the CraftOS shell itself never runs.
local S = {}

local DEFAULT_PATH = ".:/rom/programs:/rom/programs/http:/rom/programs/advanced"
    .. ":/rom/programs/rednet:/rom/programs/fun:/rom/programs/fun/advanced"

-- env: the process's sandbox globals. dir: starting directory.
-- makeRequire(env, dir) -> require, package (supplied by the kernel).
-- Returns the shell table and a small control table for the kernel.
function S.make(env, dir, makeRequire)
    local shell, ctl = {}, {}
    local path = DEFAULT_PATH
    local aliases = { ls = "list", dir = "list", cp = "copy", mv = "move", rm = "delete", clr = "clear", rs = "redstone" }
    local running, completion = {}, {}
    local fs = env.fs
    dir = fs.combine(dir or "", "")

    function shell.dir() return dir end
    function shell.setDir(d)
        if type(d) ~= "string" then error("bad argument #1 (string expected)", 2) end
        if not fs.isDir(d) then error("Not a directory", 2) end
        dir = fs.combine(d, "")
    end
    function shell.path() return path end
    function shell.setPath(p) path = p end

    function shell.resolve(p)
        local c = p:sub(1, 1)
        if c == "/" or c == "\\" then return fs.combine("", p) end
        return fs.combine(dir, p)
    end

    local function withExt(p)
        if fs.exists(p) and not fs.isDir(p) then return p end
        if fs.exists(p .. ".lua") and not fs.isDir(p .. ".lua") then return p .. ".lua" end
        return nil
    end

    function shell.resolveProgram(cmd)
        if aliases[cmd] then cmd = aliases[cmd] end
        local c = cmd:sub(1, 1)
        if c == "/" or c == "\\" then return withExt(fs.combine("", cmd)) end
        for part in path:gmatch("[^:]+") do
            local found = withExt(fs.combine(shell.resolve(part), cmd))
            if found then return found end
        end
        return nil
    end

    local function tokenise(...)
        local line = table.concat({ ... }, " ")
        local words, quoted = {}, false
        for match in (line .. "\""):gmatch("(.-)\"") do
            if quoted then
                words[#words + 1] = match
            else
                for m in match:gmatch("[^ \t]+") do words[#words + 1] = m end
            end
            quoted = not quoted
        end
        return words
    end
    ctl.tokenise = tokenise

    -- Globals a program sees: its own `shell`, `require` and `package`; the rest comes from env.
    local function programEnv(progPath, command, ...)
        local e = { shell = shell }
        e.require, e.package = makeRequire(e, fs.getDir(progPath))
        e.arg = { [0] = command, ... }
        return e
    end
    ctl.programEnv = programEnv
    function ctl.push(p) running[#running + 1] = p end
    function ctl.pop() running[#running] = nil end

    function shell.execute(command, ...)
        local progPath = shell.resolveProgram(command)
        if not progPath then
            env.printError("No such program")
            return false
        end
        running[#running + 1] = progPath
        local ok = env.os.run(programEnv(progPath, command, ...), progPath, ...)
        running[#running] = nil
        return ok
    end

    function shell.run(...)
        local words = tokenise(...)
        if words[1] then return shell.execute(words[1], table.unpack(words, 2)) end
        return false
    end

    function shell.exit() ctl.exit = true end
    function shell.getRunningProgram() return running[#running] end

    function shell.aliases()
        local copy = {}
        for k, v in pairs(aliases) do copy[k] = v end
        return copy
    end
    function shell.setAlias(a, program) aliases[a] = program end
    function shell.clearAlias(a) aliases[a] = nil end

    function shell.programs(includeHidden)
        local seen, list = {}, {}
        for part in path:gmatch("[^:]+") do
            local d = shell.resolve(part)
            if fs.isDir(d) then
                for _, file in ipairs(fs.list(d)) do
                    if not fs.isDir(fs.combine(d, file)) and (includeHidden or file:sub(1, 1) ~= ".") then
                        local name = file:gsub("%.lua$", "")
                        if not seen[name] then seen[name] = true; list[#list + 1] = name end
                    end
                end
            end
        end
        table.sort(list)
        return list
    end

    -- Tab completion isn't implemented yet; these keep programs that ask for it happy.
    function shell.complete() return nil end
    function shell.completeProgram() return {} end
    function shell.setCompletionFunction(program, fn) completion[program] = { fnComplete = fn } end
    function shell.getCompletionInfo() return completion end

    return shell, ctl
end

return S
