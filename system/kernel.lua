-- Phoenix OS kernel: processes, the scheduler, the per-program sandbox and file permissions.
--
-- Phoenix runs on top of CraftOS but takes it over. The shared CraftOS tables
-- (fs, os, term, debug) are patched in place so every program, including the
-- ROM's own code, goes through the kernel's checks. Each program then gets its
-- own copy of the globals, so it can't change anything another program sees.
local sys = sys
local K = { procs = {}, apps = {}, appOrder = {}, timers = {}, session = nil, pending = nil, current = nil }

-- Locals for everything used on security paths, so nothing can be swapped out from under us.
local type, error, pairs, ipairs, tostring, select, setmetatable, pcall = type, error, pairs, ipairs, tostring, select, setmetatable, pcall
local cyield, ccreate, cresume, cstatus = coroutine.yield, coroutine.create, coroutine.resume, coroutine.status
local tpack, tunpack, tsort = table.pack, table.unpack, table.sort
local realG, realfs, realos, realterm, realdebug = _G, fs, os, term, debug
local native = sys.native
local combine, epoch = fs.combine, os.epoch
local orig = { fs = {}, os = {}, term = {}, debug = {} }
local nextPid = 1
local LOG = "/etc/events.log"

------------------------------------------------------------------ permissions
-- Path rules for this first version (rwx-style permissions come later):
--   administrators: everything
--   standard users: read /rom /apps /opt /lib; read and write their own /usr/<name>, /tmp and floppies
local function can(p, path, write)
    if not p or p.system or p.admin then return true end
    if type(path) ~= "string" then return true end -- let the real function raise the type error
    path = combine(path, "")
    if path == "" then return not write end
    local top, rest = path:match("^([^/]+)/?(.*)$")
    if top == "tmp" then return true end
    if top == "rom" or top == "apps" or top == "opt" or top == "lib" then return not write end
    if top == "usr" then
        if rest == "" then return not write end
        return rest:match("^([^/]+)") == p.user
    end
    if top:match("^disk%d*$") then return true end
    return false
end
K.can = can

local function denied(path) return "/" .. combine(path, "") .. ": Access denied" end

-- Run kernel code with full rights, whichever process happens to be calling.
local function privileged(fn, ...)
    local saved = K.current
    K.current = nil
    local r = tpack(pcall(fn, ...))
    K.current = saved
    if not r[1] then error(r[2], 0) end
    return tunpack(r, 2, r.n)
end
K.privileged = privileged

------------------------------------------------------------------ event log
function K.log(level, message)
    privileged(function()
        local line = os.date("%Y-%m-%d %H:%M:%S") .. " [" .. level .. "] " .. message .. "\n"
        if orig.fs.exists(LOG) and orig.fs.getSize(LOG) > 16384 then
            -- Keep the newest half so the log can't fill the disk.
            local f = orig.fs.open(LOG, "r")
            local data = f.readAll() or ""
            f.close()
            data = data:sub(#data - 8192)
            data = data:sub((data:find("\n", 1, true) or 0) + 1)
            f = orig.fs.open(LOG, "w")
            f.write(data)
            f.close()
        end
        local f = orig.fs.open(LOG, "a")
        if f then f.write(line) f.close() end
    end)
end

------------------------------------------------------------------ patching the shared APIs
local function patchFs()
    local o = orig.fs
    for k, v in pairs(realfs) do o[k] = v end
    local function guard(name, write)
        realfs[name] = function(path, ...)
            if not can(K.current, path, write) then error(denied(path), 2) end
            return o[name](path, ...)
        end
    end
    for _, n in ipairs({ "getSize", "attributes", "getDrive", "getFreeSpace", "getCapacity" }) do guard(n, false) end
    for _, n in ipairs({ "makeDir", "delete" }) do guard(n, true) end
    realfs.exists = function(path) return can(K.current, path, false) and o.exists(path) end
    realfs.isDir = function(path) return can(K.current, path, false) and o.isDir(path) end
    realfs.isReadOnly = function(path)
        if not can(K.current, path, true) then return true end
        return o.isReadOnly(path)
    end
    realfs.list = function(path)
        local p = K.current
        if not can(p, path, false) then error(denied(path), 2) end
        local items = o.list(path)
        if not p or p.system or p.admin then return items end
        local out = {}
        for i = 1, #items do
            if can(p, combine(path, items[i]), false) then out[#out + 1] = items[i] end
        end
        return out
    end
    realfs.open = function(path, mode)
        if type(path) == "string" and type(mode) == "string" then
            local p = K.current
            local plain = mode:sub(1, 1) == "r" and not mode:find("+", 1, true)
            if not can(p, path, false) or (not plain and not can(p, path, true)) then
                return nil, denied(path)
            end
        end
        return o.open(path, mode)
    end
    realfs.move = function(from, to)
        local p = K.current
        if not can(p, from, true) then error(denied(from), 2) end
        if not can(p, to, true) then error(denied(to), 2) end
        return o.move(from, to)
    end
    realfs.copy = function(from, to)
        local p = K.current
        if not can(p, from, false) then error(denied(from), 2) end
        if not can(p, to, true) then error(denied(to), 2) end
        return o.copy(from, to)
    end
    if o.find then
        realfs.find = function(pattern)
            local p = K.current
            local found = o.find(pattern)
            if not p or p.system or p.admin then return found end
            local out = {}
            for i = 1, #found do
                if can(p, found[i], false) then out[#out + 1] = found[i] end
            end
            return out
        end
    end
end

local function patchOs()
    local o = orig.os
    for k, v in pairs(realos) do o[k] = v end
    -- Timers and alarms belong to whoever started them; only the owner gets the event.
    realos.startTimer = function(t)
        local id = o.startTimer(t)
        local p = K.current
        if p then K.timers[id] = p; p.timers[id] = true end
        return id
    end
    realos.cancelTimer = function(id)
        local p = K.current
        if p then
            if K.timers[id] ~= p then return end
            K.timers[id] = nil
            p.timers[id] = nil
        end
        return o.cancelTimer(id)
    end
    realos.setAlarm = function(t)
        local id = o.setAlarm(t)
        local p = K.current
        if p then p.alarms[id] = true end
        return id
    end
    -- Events a program queues come back to that program only, so one program
    -- can't fake key presses or clicks for another.
    realos.queueEvent = function(name, ...)
        local p = K.current
        if p then
            if type(name) ~= "string" then error("bad argument #1 (string expected, got " .. type(name) .. ")", 2) end
            return o.queueEvent("phoenix_event", p.pid, name, ...)
        end
        return o.queueEvent(name, ...)
    end
    realos.shutdown = function()
        if K.current then K.power("shutdown") while true do cyield() end end
        return o.shutdown()
    end
    realos.reboot = function()
        if K.current then K.power("reboot") while true do cyield() end end
        return o.reboot()
    end
    realos.setComputerLabel = function(label)
        local p = K.current
        if p and not (p.admin or p.system) then error("Access denied", 2) end
        return o.setComputerLabel(label)
    end
end

local function patchTerm()
    orig.term.native = realterm.native
    -- A program's "real screen" is its own window, never the whole display.
    realterm.native = function()
        local p = K.current
        if p then return p.baseTerm end
        return native
    end
end

local function patchDebug()
    local o = orig.debug
    for k, v in pairs(realdebug) do o[k] = v end
    local function restricted() local p = K.current return p and not p.system end
    local function block(name)
        if not o[name] then return end
        realdebug[name] = function(...)
            if restricted() then error("debug." .. name .. " is not available to programs", 2) end
            return o[name](...)
        end
    end
    for _, n in ipairs({ "setupvalue", "upvaluejoin", "setlocal", "sethook", "setmetatable", "setuservalue" }) do block(n) end
    if o.getupvalue then
        realdebug.getupvalue = function(f, i)
            if restricted() then return (o.getupvalue(f, i)) end -- the name only, never the value
            return o.getupvalue(f, i)
        end
    end
    if o.getlocal then
        realdebug.getlocal = function(a, b, c)
            if restricted() then
                if type(a) == "function" then return (o.getlocal(a, b)) end -- parameter names are harmless
                return nil
            end
            if c ~= nil then return o.getlocal(a, b, c) end
            return o.getlocal(a, b)
        end
    end
    if o.getregistry then
        -- Programs get a harmless scratch table instead of the real registry
        -- (CC's error-reporting code keeps a marker function in it).
        local fakeRegistry = {}
        realdebug.getregistry = function()
            if restricted() then return fakeRegistry end
            return o.getregistry()
        end
    end
    if o.getmetatable then
        realdebug.getmetatable = function(v)
            if restricted() then return getmetatable(v) end
            return o.getmetatable(v)
        end
    end
end

local stringMeta
function K.patch()
    patchFs()
    patchOs()
    patchTerm()
    patchDebug()
    -- Stop programs reaching the shared string library through a string's metatable.
    stringMeta = getmetatable("")
    if type(stringMeta) == "table" then stringMeta.__metatable = false end
end

-- Put CraftOS back exactly as it was (used when leaving for recovery or after a crash).
function K.unpatch()
    for k, v in pairs(orig.fs) do realfs[k] = v end
    for k, v in pairs(orig.os) do realos[k] = v end
    for k, v in pairs(orig.term) do realterm[k] = v end
    for k, v in pairs(orig.debug) do realdebug[k] = v end
    if type(stringMeta) == "table" then stringMeta.__metatable = nil end
end

------------------------------------------------------------------ sandbox
local ccRequire = dofile("rom/modules/main/cc/require.lua").make
local hidden = { _G = true, shell = true, multishell = true, require = true, package = true, sys = true }

-- require/package for a program. `base` is the sandbox env the standard libraries come from.
local function makeRequire(e, dir, base)
    local req, pkg = privileged(ccRequire, e, dir)
    for k in pairs(pkg.loaded) do
        -- Never hand out the shared tables; give the program's own copies.
        if k == "_G" then pkg.loaded[k] = base elseif k ~= "package" then pkg.loaded[k] = base[k] end
    end
    pkg.path = "/lib/?.lua;/lib/?/init.lua;" .. pkg.path
    return req, pkg
end

local function copyTable(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

function K.makeEnv(p, dir)
    local env = {}
    for k, v in pairs(realG) do
        if not hidden[k] then
            if type(v) == "table" then env[k] = copyTable(v) else env[k] = v end
        end
    end
    env._G = env

    local rload, rloadfile = realG.load, realG.loadfile
    env.load = function(chunk, name, mode, e)
        if e == nil then e = env end
        return rload(chunk, name, "t", e)
    end
    env.loadstring = function(chunk, name) return rload(chunk, name, "t", env) end
    env.loadfile = function(path, mode, e)
        if type(mode) == "table" and e == nil then e = mode end
        return rloadfile(path, "t", e or env)
    end
    env.dofile = function(path)
        local fn, err = env.loadfile(path)
        if not fn then error(err, 2) end
        return fn()
    end
    if realG.getfenv then
        local rget, rset = realG.getfenv, realG.setfenv
        env.getfenv = function(f)
            if f == nil then f = 1 end
            if type(f) == "number" and f > 0 then f = f + 1 end
            local t = rget(f)
            if t == realG then return env end
            return t
        end
        env.setfenv = function(f, t)
            if type(f) == "number" and f > 0 then f = f + 1 end
            if rget(f) == realG then error("setfenv: not permitted on system functions", 2) end
            return rset(f, t)
        end
    end

    -- os.run and os.loadAPI normally reach for the shared globals; these stay inside the sandbox.
    env.os.run = function(tEnv, path, ...)
        if type(tEnv) ~= "table" or type(path) ~= "string" then error("bad argument to os.run", 2) end
        setmetatable(tEnv, { __index = env })
        local fn, err = rloadfile(path, "t", tEnv)
        if not fn then
            if err and err ~= "" then printError(err) end
            return false
        end
        local ok, e = pcall(fn, ...)
        if not ok then
            if e and e ~= "" then printError(e) end
            return false
        end
        return true
    end
    env.os.loadAPI = function(path)
        if type(path) ~= "string" then error("bad argument #1 (string expected)", 2) end
        local name = combine(path, ""):match("([^/]+)$"):gsub("%.lua$", "")
        local t = setmetatable({}, { __index = env })
        local fn, err = rloadfile(path, "t", t)
        if not fn then printError(err) return false end
        local ok, e = pcall(fn)
        if not ok then printError(e) return false end
        local api = {}
        for k, v in pairs(t) do if k ~= "_ENV" then api[k] = v end end
        env[name] = api
        return true
    end
    env.os.unloadAPI = function(name)
        if name ~= "_G" and type(env[name]) == "table" then env[name] = nil end
    end

    local function req(e, d) return makeRequire(e, d, env) end
    env.shell, p.shellCtl = sys.shelllib.make(env, dir, req)
    env.require, env.package = req(env, combine(dir or "", ""))
    env.phoenix = K.makeApi(p)
    return env
end

------------------------------------------------------------------ processes
local function nullTerm()
    local w, h = native.getSize()
    return window.create(native, 1, 1, w, h, false)
end

local function finish(p, ok, err)
    if p.status == "dead" then return end
    p.status = "dead"
    for id in pairs(p.timers) do
        K.timers[id] = nil
        orig.os.cancelTimer(id)
    end
    for id in pairs(p.alarms) do orig.os.cancelAlarm(id) end
    if p.win then sys.wm.destroy(p.win) end
    K.procs[p.pid] = nil
    if not ok and not p.killed then
        local msg = tostring(err)
        if msg ~= "Terminated" then
            K.log("ERROR", p.name .. " (pid " .. p.pid .. ", " .. p.user .. ") crashed: " .. msg)
            sys.wm.alert("Program error", p.name .. " stopped working.\n\n" .. msg)
        end
    end
end

-- Give a process one event (or its start-up arguments) and let it run until it next waits.
function K.resume(p, ...)
    if p.status ~= "alive" then return end
    local ev = ...
    if p.filter ~= nil and ev ~= p.filter and ev ~= "terminate" then return end
    local prevProc = K.current
    local prevTerm = realterm.redirect(p.term)
    K.current = p
    local t0 = epoch("utc")
    local res = tpack(cresume(p.co, ...))
    p.cpu = p.cpu + (epoch("utc") - t0)
    K.current = prevProc
    p.term = realterm.current()
    realterm.redirect(prevTerm)
    if not res[1] then
        finish(p, false, res[2])
    elseif cstatus(p.co) == "dead" then
        finish(p, true)
    else
        p.filter = res[2]
    end
end

function K.kill(p)
    if not p or p.status ~= "alive" then return false end
    p.killed = true
    finish(p, true)
    return true
end

-- The function a program process starts in: load the file and run it like a shell would.
local function programMain(p, path, hold)
    return function(...)
        local e = setmetatable(p.shellCtl.programEnv(path, path, ...), { __index = p.env })
        local fn, err = realG.loadfile(path, "t", e)
        if not fn then error(err, 0) end
        p.shellCtl.push(path)
        fn(...)
        if hold then
            print()
            term.setTextColour(colors.lightGray)
            print("Program finished. Press any key to close.")
            os.pullEvent("key")
        end
    end
end

-- K.spawn({ path = , args = {}, name = , window = { title, w, h, ... }, dir = , hold = })
-- Kernel code may also pass fn = function() ... end and system = true.
-- A program can only start processes as its own user; rights never go up.
function K.spawn(o)
    local parent = K.current
    local trusted = not parent or parent.system
    local s = K.session
    local p = {
        pid = nextPid, name = type(o.name) == "string" and o.name or "process", app = o.app, path = o.path,
        status = "alive", cpu = 0, timers = {}, alarms = {}, started = epoch("utc"),
    }
    if trusted then
        p.user = o.user or (s and s.name) or "system"
        p.admin = o.admin
        if p.admin == nil then p.admin = s and s.admin or false end
        p.system = o.system and true or false
    else
        p.user, p.admin, p.system = parent.user, parent.admin, false
    end
    if not p.system and not s then return nil, "Nobody is signed in" end

    local main
    if o.fn and trusted then
        main = o.fn
    else
        if type(o.path) ~= "string" then return nil, "No program given" end
        if not can(p, o.path, false) then return nil, denied(o.path) end
        if not orig.fs.exists(o.path) or orig.fs.isDir(o.path) then return nil, "No such program" end
    end
    nextPid = nextPid + 1

    if o.window then
        p.win = sys.wm.create(p, o.window)
        p.baseTerm = p.win.term
    else
        p.baseTerm = nullTerm()
    end
    p.term = p.baseTerm
    if not main then
        local home = "usr/" .. p.user
        local dir = type(o.dir) == "string" and o.dir or (orig.fs.isDir(home) and home or "")
        p.env = K.makeEnv(p, dir)
        main = programMain(p, o.path, o.hold)
    end
    p.co = ccreate(main)
    K.procs[p.pid] = p
    local args = o.args or {}
    K.resume(p, tunpack(args, 1, args.n or #args))
    return p.pid
end

function K.list()
    local out = {}
    for _, p in pairs(K.procs) do out[#out + 1] = p end
    tsort(out, function(a, b) return a.pid < b.pid end)
    return out
end

------------------------------------------------------------------ apps
-- Every folder in /apps with an app.cfg is an installed app.
function K.scanApps()
    K.apps, K.appOrder = {}, {}
    if not orig.fs.isDir("/apps") then return end
    for _, id in ipairs(orig.fs.list("/apps")) do
        local cfg = "/apps/" .. id .. "/app.cfg"
        if orig.fs.exists(cfg) and orig.fs.exists("/apps/" .. id .. "/main.lua") then
            local f = orig.fs.open(cfg, "r")
            local app = textutils.unserialize(f.readAll() or "")
            f.close()
            if type(app) == "table" and type(app.name) == "string" then
                app.id = id
                K.apps[id] = app
                K.appOrder[#K.appOrder + 1] = app
            end
        end
    end
    tsort(K.appOrder, function(a, b)
        local oa, ob = a.order or 100, b.order or 100
        if oa ~= ob then return oa < ob end
        return a.name < b.name
    end)
end

function K.launchApp(id, args)
    local app = K.apps[id]
    if not app then return nil, "No such app" end
    if app.single then
        for _, p in pairs(K.procs) do
            if p.app == id and p.win then
                sys.wm.focusWindow(p.win)
                return p.pid
            end
        end
    end
    return K.spawn({
        path = "/apps/" .. id .. "/main.lua", name = app.name, app = id, args = args,
        window = { title = app.name, w = app.w, h = app.h, minW = app.minW, minH = app.minH, maximised = app.maximised },
    })
end

------------------------------------------------------------------ per-user settings
local function settingsPath(user) return "/usr/" .. user .. "/.config/phoenix.cfg" end

function K.loadSettings(user)
    return privileged(function()
        local path = settingsPath(user)
        if orig.fs.exists(path) then
            local f = orig.fs.open(path, "r")
            local data = textutils.unserialize(f.readAll() or "")
            f.close()
            if type(data) == "table" then return data end
        end
        return {}
    end)
end

function K.getSetting(key, default)
    local s = K.session
    local v = s and s.settings[key]
    if v == nil then return default end
    return v
end

function K.setSetting(key, value)
    local s = K.session
    if not s then return end
    s.settings[key] = value
    privileged(function()
        local f = orig.fs.open(settingsPath(s.name), "w")
        if f then f.write(textutils.serialize(s.settings)) f.close() end
    end)
    sys.desktop.refresh()
end

------------------------------------------------------------------ the API programs see as `phoenix`
function K.hostname()
    return orig.os.getComputerLabel() or ("computer-" .. orig.os.getComputerID())
end

function K.makeApi(p)
    local A = { version = sys.version, edition = sys.edition }
    local function isAdmin() return p.admin or p.system end

    function A.user() return p.user, p.admin end
    function A.pid() return p.pid end
    function A.hostname() return K.hostname() end

    A.window = {
        setTitle = function(title)
            if p.win and type(title) == "string" then sys.wm.setTitle(p.win, title) end
        end,
        getTitle = function() return p.win and p.win.title end,
        close = function()
            K.kill(p)
            error("Terminated", 0)
        end,
    }

    A.proc = {
        list = function()
            local out = {}
            for _, q in ipairs(K.list()) do
                out[#out + 1] = {
                    pid = q.pid, name = q.name, user = q.user, cpu = q.cpu, system = q.system,
                    window = q.win and q.win.title or nil, started = q.started,
                }
            end
            return out
        end,
        kill = function(pid)
            local q = K.procs[pid]
            if not q then return false, "No such process" end
            if not isAdmin() and q.user ~= p.user then return false, "Access denied" end
            K.kill(q)
            if q == p then error("Terminated", 0) end
            return true
        end,
    }

    -- Installed apps: { { id = , name = }, ... }
    function A.apps()
        local out = {}
        for _, app in ipairs(K.appOrder) do out[#out + 1] = { id = app.id, name = app.name } end
        return out
    end
    function A.launch(id, ...)
        if type(id) ~= "string" then return nil, "No such app" end
        return K.launchApp(id, tpack(...))
    end
    -- Run any program in a new window.
    function A.run(path, ...)
        if type(path) ~= "string" then return nil, "No program given" end
        local name = combine(path, ""):match("([^/]+)$") or path
        return K.spawn({ path = path, name = name, args = tpack(...), hold = true, window = { title = name, w = 46, h = 15 } })
    end

    A.power = {
        shutdown = function() K.power("shutdown") end,
        reboot = function() K.power("reboot") end,
        logoff = function() K.power("logoff") end,
        lock = function() K.power("lock") end,
    }

    A.users = {
        list = function() return privileged(sys.users.list) end,
        exists = function(name) return privileged(sys.users.exists, name) end,
        add = function(name, password, admin)
            if not isAdmin() then return false, "Administrator rights needed" end
            local ok, err = privileged(sys.users.add, name, password, admin)
            if ok then K.log("INFO", p.user .. " created user " .. name) end
            return ok, err
        end,
        remove = function(name)
            if not isAdmin() then return false, "Administrator rights needed" end
            if K.session and K.session.name == name then return false, "That user is signed in" end
            local ok, err = privileged(sys.users.remove, name)
            if ok then K.log("INFO", p.user .. " removed user " .. name) end
            return ok, err
        end,
        -- Anyone can change their own password with the old one; administrators can reset anyone's.
        setPassword = function(name, new, old)
            if name ~= p.user and not isAdmin() then return false, "Administrator rights needed" end
            if name == p.user and not privileged(sys.users.verify, name, old) then
                return false, "Current password is wrong"
            end
            local ok, err = privileged(sys.users.setPassword, name, new)
            if ok then K.log("INFO", p.user .. " changed the password for " .. name) end
            return ok, err
        end,
    }

    A.settings = {
        get = function(key, default)
            if K.session and K.session.name == p.user then return K.getSetting(key, default) end
            return default
        end,
        set = function(key, value)
            if type(key) ~= "string" then return false end
            local tv = type(value)
            if tv ~= "string" and tv ~= "number" and tv ~= "boolean" and tv ~= "nil" then return false end
            if K.session and K.session.name == p.user then K.setSetting(key, value) return true end
            return false
        end,
    }

    A.system = {
        info = function()
            local w, h = native.getSize()
            return {
                version = sys.version, edition = sys.edition, id = orig.os.getComputerID(),
                label = orig.os.getComputerLabel(), host = _HOST, width = w, height = h,
                uptime = orig.os.clock(), free = orig.fs.getFreeSpace("/"), capacity = orig.fs.getCapacity("/"),
                booted = K.booted,
            }
        end,
        setLabel = function(label)
            if not isAdmin() then return false, "Administrator rights needed" end
            if label ~= nil and type(label) ~= "string" then return false, "Bad label" end
            orig.os.setComputerLabel(label)
            return true
        end,
    }
    return A
end

------------------------------------------------------------------ sessions and power
function K.power(action) K.pending = action end

function K.startSession(user)
    K.session = { name = user.name, admin = user.admin, started = epoch("utc"), settings = K.loadSettings(user.name) }
    K.log("INFO", user.name .. " signed in")
    sys.wm.overlay = nil
    sys.desktop.start()
    sys.wm.invalidate()
end

function K.endSession()
    for _, p in ipairs(K.list()) do K.kill(p) end
    if K.session then K.log("INFO", K.session.name .. " signed out") end
    sys.desktop.stop()
    K.session = nil
end

-- A kernel timer: fn runs in the kernel after t seconds.
function K.after(t, fn)
    local id = orig.os.startTimer(t)
    K.timers[id] = fn
    return id
end

local function doPending()
    local action = K.pending
    K.pending = nil
    if action == "lock" then
        if K.session then sys.login.lock() end
    elseif action == "logoff" then
        K.endSession()
        sys.login.show()
    elseif action == "shutdown" or action == "reboot" then
        K.endSession()
        K.log("INFO", action == "reboot" and "Restarting" or "Shutting down")
        sys.wm.splash(action == "reboot" and "Restarting..." or "Shutting down...")
        K.unpatch()
        if action == "reboot" then orig.os.reboot() else orig.os.shutdown() end
    end
end

------------------------------------------------------------------ events
local inputEvents = {
    key = true, key_up = true, char = true, paste = true, terminate = true,
    mouse_click = true, mouse_up = true, mouse_drag = true, mouse_scroll = true,
}

local function dispatch(ev)
    local name = ev[1]
    if inputEvents[name] then
        sys.wm.input(tunpack(ev, 1, ev.n))
    elseif name == "timer" then
        local owner = K.timers[ev[2]]
        if owner then
            K.timers[ev[2]] = nil
            if type(owner) == "function" then
                owner(ev[2])
            else
                owner.timers[ev[2]] = nil
                K.resume(owner, "timer", ev[2])
            end
        end
    elseif name == "alarm" then
        for _, p in ipairs(K.list()) do
            if p.alarms[ev[2]] then
                p.alarms[ev[2]] = nil
                K.resume(p, "alarm", ev[2])
            end
        end
    elseif name == "phoenix_event" then
        local p = K.procs[ev[2]]
        if p then K.resume(p, tunpack(ev, 3, ev.n)) end
    elseif name == "term_resize" then
        sys.wm.resize()
    else
        -- Everything else (network, peripherals, redstone, http...) goes to every program.
        for _, p in ipairs(K.list()) do K.resume(p, tunpack(ev, 1, ev.n)) end
    end
end

function K.main()
    K.booted = epoch("utc")
    -- Standard folders. /tmp is emptied on every start.
    if fs.exists("/tmp") then fs.delete("/tmp") end
    for _, d in ipairs({ "/tmp", "/etc", "/usr", "/opt", "/apps", "/lib" }) do
        if not fs.exists(d) then fs.makeDir(d) end
    end
    K.patch()
    K.scanApps()
    sys.wm.init()
    K.log("INFO", "Phoenix OS " .. sys.version .. " started on computer " .. orig.os.getComputerID())
    sys.login.show()
    sys.wm.flush()
    while true do
        local ev = tpack(cyield())
        dispatch(ev)
        while K.pending do doPending() end
        sys.wm.flush()
    end
end

return K
