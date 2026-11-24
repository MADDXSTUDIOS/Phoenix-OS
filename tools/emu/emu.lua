-- Minimal CC:Tweaked computer for testing Phoenix OS outside Minecraft.
-- Loaded by emu.py inside a Lua 5.2 runtime. It provides the "Java side" of a
-- computer (term, fs, os, peripheral, redstone) and then boots the real
-- CC:Tweaked bios.lua and ROM on top, so the OS runs against genuine CraftOS.
--
-- Time is virtual: timers fire instantly when the test script advances the
-- clock, so tests are fast and repeatable.
return function(py, cfg)
    local host_io, host_os, host_load, host_debug = io, os, load, debug
    local W, H = cfg.w, cfg.h
    local ROOT, ROM, BIOS = cfg.root, cfg.rom, cfg.bios
    -- CC's Lua (Cobalt) follows Lua 5.1 for "%x" in gsub replacement strings,
    -- where plain Lua 5.2 raises an error. The ROM relies on the 5.1 behaviour.
    local raw_gsub = string.gsub
    string.gsub = function(s, pat, repl, n)
        if type(repl) == "string" and repl:find("%", 1, true) then
            repl = raw_gsub(repl, "%%(.?)", function(c)
                if c == "" then return "%%" end
                if c:match("[%d%%]") then return "%" .. c end
                return c
            end)
        end
        return raw_gsub(s, pat, repl, n)
    end

    local E = { vclock = 0, powered = false, label = nil, baseTime = cfg.base_time or 1700000000 }

    ------------------------------------------------------------ terminal
    local hexChars = "0123456789abcdef"
    local defaultPalette = {
        [0] = 0xF0F0F0, 0xF2B233, 0xE57FD8, 0x99B2F2, 0xDEDE6C, 0x7FCC19, 0xF2B2CC, 0x4C4C4C,
        0x999999, 0x4C99B2, 0xB266E5, 0x3366CC, 0x7F664C, 0x57A64E, 0xCC4C4C, 0x111111,
    }
    local scr

    local function newScreen()
        scr = { text = {}, fg = {}, bg = {}, cx = 1, cy = 1, blink = false, tc = 0, bc = 15, pal = {} }
        for i = 0, 15 do scr.pal[i] = defaultPalette[i] end
        for y = 1, H do
            scr.text[y] = (" "):rep(W)
            scr.fg[y] = ("0"):rep(W)
            scr.bg[y] = ("f"):rep(W)
        end
    end

    local function colIdx(c)
        if type(c) ~= "number" then error("bad argument #1 (number expected, got " .. type(c) .. ")", 3) end
        for i = 0, 15 do if c == 2 ^ i then return i end end
        error("Colour out of range", 3)
    end

    local function put(text, fg, bg)
        local y, x, n = scr.cy, scr.cx, #text
        if y >= 1 and y <= H and n > 0 then
            local s, e = x, x + n - 1
            if e >= 1 and s <= W then
                local cs, ce = math.max(s, 1), math.min(e, W)
                local a, b = cs - s + 1, ce - s + 1
                scr.text[y] = scr.text[y]:sub(1, cs - 1) .. text:sub(a, b) .. scr.text[y]:sub(ce + 1)
                scr.fg[y] = scr.fg[y]:sub(1, cs - 1) .. fg:sub(a, b) .. scr.fg[y]:sub(ce + 1)
                scr.bg[y] = scr.bg[y]:sub(1, cs - 1) .. bg:sub(a, b) .. scr.bg[y]:sub(ce + 1)
            end
        end
        scr.cx = x + n
    end

    local native = {}
    function native.write(text)
        text = tostring(text)
        local h1, h2 = hexChars:sub(scr.tc + 1, scr.tc + 1), hexChars:sub(scr.bc + 1, scr.bc + 1)
        put(text, h1:rep(#text), h2:rep(#text))
    end
    function native.blit(text, fg, bg)
        if type(text) ~= "string" or type(fg) ~= "string" or type(bg) ~= "string" then
            error("bad argument (string expected)", 2)
        end
        if #text ~= #fg or #text ~= #bg then error("Arguments must be the same length", 2) end
        put(text, fg:lower(), bg:lower())
    end
    function native.clear()
        local f, b = hexChars:sub(scr.tc + 1, scr.tc + 1), hexChars:sub(scr.bc + 1, scr.bc + 1)
        for y = 1, H do scr.text[y] = (" "):rep(W); scr.fg[y] = f:rep(W); scr.bg[y] = b:rep(W) end
    end
    function native.clearLine()
        local y = scr.cy
        if y >= 1 and y <= H then
            scr.text[y] = (" "):rep(W)
            scr.fg[y] = hexChars:sub(scr.tc + 1, scr.tc + 1):rep(W)
            scr.bg[y] = hexChars:sub(scr.bc + 1, scr.bc + 1):rep(W)
        end
    end
    function native.scroll(n)
        n = math.floor(n)
        local f, b = hexChars:sub(scr.tc + 1, scr.tc + 1), hexChars:sub(scr.bc + 1, scr.bc + 1)
        local nt, nf, nb = {}, {}, {}
        for y = 1, H do
            local src = y + n
            if src >= 1 and src <= H then
                nt[y], nf[y], nb[y] = scr.text[src], scr.fg[src], scr.bg[src]
            else
                nt[y], nf[y], nb[y] = (" "):rep(W), f:rep(W), b:rep(W)
            end
        end
        scr.text, scr.fg, scr.bg = nt, nf, nb
    end
    function native.getCursorPos() return scr.cx, scr.cy end
    function native.setCursorPos(x, y)
        if type(x) ~= "number" or type(y) ~= "number" then error("bad argument (number expected)", 2) end
        scr.cx, scr.cy = math.floor(x), math.floor(y)
    end
    function native.getCursorBlink() return scr.blink end
    function native.setCursorBlink(b) scr.blink = b and true or false end
    function native.getSize() return W, H end
    function native.isColour() return cfg.colour end
    native.isColor = native.isColour
    function native.setTextColour(c) scr.tc = colIdx(c) end
    native.setTextColor = native.setTextColour
    function native.getTextColour() return 2 ^ scr.tc end
    native.getTextColor = native.getTextColour
    function native.setBackgroundColour(c) scr.bc = colIdx(c) end
    native.setBackgroundColor = native.setBackgroundColour
    function native.getBackgroundColour() return 2 ^ scr.bc end
    native.getBackgroundColor = native.getBackgroundColour
    function native.setPaletteColour(c, r, g, b)
        local i = colIdx(c)
        if g == nil then
            scr.pal[i] = math.floor(r)
        else
            scr.pal[i] = math.floor(r * 255 + 0.5) * 65536 + math.floor(g * 255 + 0.5) * 256 + math.floor(b * 255 + 0.5)
        end
    end
    native.setPaletteColor = native.setPaletteColour
    local function rgb(v) return math.floor(v / 65536) / 255, math.floor(v / 256) % 256 / 255, v % 256 / 255 end
    function native.getPaletteColour(c) return rgb(scr.pal[colIdx(c)]) end
    native.getPaletteColor = native.getPaletteColour
    function native.nativePaletteColour(c) return rgb(defaultPalette[colIdx(c)]) end
    native.nativePaletteColor = native.nativePaletteColour

    ------------------------------------------------------------ filesystem
    local function sanitize(path)
        if type(path) ~= "string" then error("bad argument (string expected, got " .. type(path) .. ")", 3) end
        local parts = {}
        for part in path:gsub("\\", "/"):gmatch("[^/]+") do
            if part == "." then
                -- skip
            elseif part == ".." then
                if #parts > 0 and parts[#parts] ~= ".." then parts[#parts] = nil else parts[#parts + 1] = ".." end
            else
                parts[#parts + 1] = part
            end
        end
        return table.concat(parts, "/")
    end

    local function hostPath(path, level)
        local p = sanitize(path)
        if p:sub(1, 2) == ".." then error("/" .. p .. ": Invalid Path", (level or 2) + 1) end
        if p == "rom" or p:sub(1, 4) == "rom/" then return ROM .. p:sub(4), true, p end
        return ROOT .. (p == "" and "" or "/" .. p), false, p
    end

    local fsn = {}
    function fsn.combine(a, ...)
        local s = a
        for _, v in ipairs({ ... }) do s = s .. "/" .. v end
        return sanitize(s)
    end
    function fsn.getName(path)
        local p = sanitize(path)
        if p == "" then return "root" end
        return p:match("([^/]+)$")
    end
    function fsn.getDir(path)
        local p = sanitize(path)
        if p == "" then return ".." end
        return p:match("^(.*)/[^/]+$") or ""
    end
    function fsn.exists(path)
        local ok, hp = pcall(hostPath, path)
        return ok and py.exists(hp)
    end
    function fsn.isDir(path)
        local ok, hp = pcall(hostPath, path)
        return ok and py.isdir(hp)
    end
    function fsn.isReadOnly(path)
        local _, ro = hostPath(path)
        return ro
    end
    function fsn.list(path)
        local hp, _, p = hostPath(path)
        if not py.isdir(hp) then error("/" .. p .. ": Not a directory", 2) end
        local out = {}
        local names = py.listdir(hp)
        for i = 1, #names do out[#out + 1] = names[i] end
        if p == "" then out[#out + 1] = "rom" end
        table.sort(out)
        return out
    end
    function fsn.getSize(path)
        local hp, _, p = hostPath(path)
        if not py.exists(hp) then error("/" .. p .. ": No such file", 2) end
        if py.isdir(hp) then return 0 end
        return py.getsize(hp)
    end
    function fsn.attributes(path)
        local hp, ro, p = hostPath(path)
        if not py.exists(hp) then error("/" .. p .. ": No such file", 2) end
        local dir = py.isdir(hp)
        local m = py.mtime(hp)
        return { size = dir and 0 or py.getsize(hp), isDir = dir, isReadOnly = ro, created = m, modified = m, modification = m }
    end
    function fsn.getDrive(path)
        local hp, ro = hostPath(path)
        if not py.exists(hp) then return nil end
        return ro and "rom" or "hdd"
    end
    function fsn.getCapacity(path)
        local _, ro = hostPath(path)
        if ro then return nil end
        return cfg.capacity
    end
    function fsn.getFreeSpace(path)
        local _, ro = hostPath(path)
        if ro then return 0 end
        return math.max(0, cfg.capacity - py.du(ROOT))
    end
    function fsn.makeDir(path)
        local hp, ro, p = hostPath(path)
        if ro then error("/" .. p .. ": Access denied", 2) end
        if py.isfile(hp) then error("/" .. p .. ": File exists", 2) end
        py.mkdirs(hp)
    end
    function fsn.delete(path)
        local hp, ro, p = hostPath(path)
        if ro or p == "" then error("/" .. p .. ": Access denied", 2) end
        py.remove(hp)
    end
    local function transfer(fn, from, to)
        local hf, _, pf = hostPath(from, 3)
        local ht, ro, pt = hostPath(to, 3)
        if ro then error("/" .. pt .. ": Access denied", 3) end
        if not py.exists(hf) then error("/" .. pf .. ": No such file", 3) end
        if py.exists(ht) then error("/" .. pt .. ": File exists", 3) end
        local parent = ht:match("^(.*)/[^/]+$")
        if parent then py.mkdirs(parent) end
        fn(hf, ht)
    end
    function fsn.move(from, to)
        local _, ro, pf = hostPath(from)
        if ro then error("/" .. pf .. ": Access denied", 2) end
        transfer(py.move, from, to)
    end
    function fsn.copy(from, to) transfer(py.copy, from, to) end

    function fsn.open(path, mode)
        if type(mode) ~= "string" then error("bad argument #2 (string expected)", 2) end
        local hp, ro, p = hostPath(path)
        local binary = mode:find("b", 1, true) ~= nil
        local base = mode:gsub("b", "")
        if base ~= "r" and base ~= "w" and base ~= "a" and base ~= "r+" and base ~= "w+" then
            error("Unsupported mode", 2)
        end
        if base ~= "r" and ro then return nil, "/" .. p .. ": Access denied" end
        if py.isdir(hp) then return nil, "/" .. p .. ": Not a file" end
        if (base == "r" or base == "r+") and not py.exists(hp) then return nil, "/" .. p .. ": No such file" end
        if base ~= "r" then
            local parent = hp:match("^(.*)/[^/]+$")
            if parent then py.mkdirs(parent) end
        end
        local f, err = host_io.open(hp, base .. "b")
        if not f then return nil, "/" .. p .. ": " .. tostring(err) end
        local h, closed = {}, false
        local function check() if closed then error("attempt to use a closed file", 3) end end
        function h.close() check(); closed = true; f:close() end
        function h.seek(whence, offset)
            check()
            return f:seek(whence or "cur", offset or 0)
        end
        if base ~= "w" and base ~= "a" then
            function h.read(n)
                check()
                if n == nil then
                    local c = f:read(1)
                    if not c then return nil end
                    if binary then return c:byte() end
                    return c
                end
                return f:read(n)
            end
            function h.readLine(withTrailing)
                check()
                local line = f:read("*L")
                if not line then return nil end
                if not withTrailing then line = line:gsub("\r?\n$", "") end
                return line
            end
            function h.readAll()
                check()
                return f:read("*a") or ""
            end
        end
        if base ~= "r" then
            function h.write(v)
                check()
                if binary and type(v) == "number" then f:write(string.char(v)) else f:write(tostring(v)) end
            end
            function h.writeLine(v) check(); f:write(tostring(v), "\n") end
            function h.flush() check(); f:flush() end
        end
        return h
    end

    ------------------------------------------------------------ os
    local osn = {}
    local nextTimer = 0
    function osn.queueEvent(name, ...)
        if type(name) ~= "string" then error("bad argument #1 (string expected, got " .. type(name) .. ")", 2) end
        E.queue[#E.queue + 1] = table.pack(name, ...)
    end
    function osn.startTimer(t)
        if type(t) ~= "number" then error("bad argument #1 (number expected, got " .. type(t) .. ")", 2) end
        nextTimer = nextTimer + 1
        local delay = math.max(0.05, math.ceil(t * 20 - 1e-9) / 20)
        E.timers[#E.timers + 1] = { id = nextTimer, at = E.vclock + delay }
        return nextTimer
    end
    function osn.cancelTimer(id)
        for i, t in ipairs(E.timers) do if t.id == id then table.remove(E.timers, i) break end end
    end
    function osn.setAlarm() nextTimer = nextTimer + 1 return nextTimer end
    function osn.cancelAlarm() end
    function osn.shutdown() E.pending = "shutdown" end
    function osn.reboot() E.pending = "reboot" end
    function osn.getComputerID() return cfg.id end
    osn.computerID = osn.getComputerID
    function osn.getComputerLabel() return E.label end
    osn.computerLabel = osn.getComputerLabel
    function osn.setComputerLabel(l) E.label = l end
    function osn.clock() return E.vclock end
    local function now() return E.baseTime + E.vclock end
    function osn.time(a)
        if a == nil or a == "ingame" then return (6 + E.vclock / 50) % 24 end
        local t = host_os.date(a == "utc" and "!*t" or "*t", math.floor(now()))
        return t.hour + t.min / 60 + t.sec / 3600
    end
    function osn.day(a)
        if a == nil or a == "ingame" then return math.floor((6 + E.vclock / 50) / 24) end
        return math.floor(now() / 86400)
    end
    function osn.epoch(a)
        if a == nil or a == "ingame" then return math.floor(E.vclock * 72000) end
        return math.floor(now() * 1000)
    end
    function osn.date(fmt, t) return host_os.date(fmt or "%c", t or math.floor(now())) end

    ------------------------------------------------------------ peripherals / redstone
    local pern = {}
    function pern.isPresent() return false end
    function pern.getType() return nil end
    function pern.hasType() return nil end
    function pern.getMethods() return nil end
    function pern.call() error("No peripheral attached", 2) end
    local sides = { "bottom", "top", "back", "front", "right", "left" }
    local rsn = {}
    function rsn.getSides() return { table.unpack(sides) } end
    for _, n in ipairs({ "getInput", "getOutput" }) do rsn[n] = function() return false end end
    for _, n in ipairs({ "getAnalogInput", "getAnalogOutput", "getAnalogueInput", "getAnalogueOutput",
        "getBundledInput", "getBundledOutput" }) do rsn[n] = function() return 0 end end
    for _, n in ipairs({ "setOutput", "setAnalogOutput", "setAnalogueOutput", "setBundledOutput" }) do rsn[n] = function() end end
    function rsn.testBundledInput() return false end

    ------------------------------------------------------------ http (optional, served from a local folder)
    local function makeHttp()
        local h = {}
        local function respond(url)
            local path = cfg.http_map and cfg.http_map(url)
            local f = path and host_io.open(path, "rb")
            if not f then
                E.queue[#E.queue + 1] = table.pack("http_failure", url, "Not found (emu)")
                return
            end
            local body, pos = f:read("*a"), 1
            f:close()
            local handle = {}
            function handle.readAll() local s = body:sub(pos); pos = #body + 1; return s end
            function handle.readLine()
                if pos > #body then return nil end
                local s, e = body:find("\n", pos, true)
                local line = body:sub(pos, (s or #body + 1) - 1)
                pos = (e or #body) + 1
                return line
            end
            function handle.read(n) if pos > #body then return nil end local s = body:sub(pos, pos + (n or 1) - 1); pos = pos + #s; return s end
            function handle.close() end
            function handle.getResponseCode() return 200, "OK" end
            function handle.getResponseHeaders() return {} end
            E.queue[#E.queue + 1] = table.pack("http_success", url, handle)
        end
        function h.request(url)
            if type(url) == "table" then url = url.url end
            respond(url)
            return true
        end
        function h.checkURL(url)
            E.queue[#E.queue + 1] = table.pack("http_check", url, true)
            return true
        end
        function h.websocket() return false, "websockets not supported in emu" end
        return h
    end

    ------------------------------------------------------------ boot and run
    local function resume(...)
        local ok, res = coroutine.resume(E.co, ...)
        if not ok then
            E.powered = false
            E.crash = tostring(res) .. "\n" .. host_debug.traceback(E.co)
        elseif coroutine.status(E.co) == "dead" then
            E.powered = false
        else
            E.filter = res
        end
    end

    function E.boot()
        newScreen()
        E.queue, E.timers, E.pending, E.crash, E.filter = {}, {}, nil, nil, nil
        local env = {}
        for _, k in ipairs({ "assert", "error", "getmetatable", "ipairs", "next", "pairs", "pcall", "rawequal",
            "rawget", "rawlen", "rawset", "select", "setmetatable", "tonumber", "tostring", "type", "xpcall" }) do
            env[k] = _G[k]
        end
        local function copy(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
        env.coroutine, env.string, env.table, env.math, env.bit32 = copy(coroutine), string, copy(table), copy(math), copy(bit32)
        env.debug = copy(host_debug)
        env._G, env._VERSION = env, "Lua 5.2"
        env._HOST = "ComputerCraft 1.120.2 (Phoenix emu)"
        env._CC_DEFAULT_SETTINGS = cfg.default_settings or ""
        env.load = function(chunk, name, mode, ...)
            local e = env
            if select("#", ...) >= 1 then e = (...) end
            return host_load(chunk, name, mode, e)
        end
        env.loadstring = function(s, name) return host_load(s, name, "t", env) end
        env.setfenv = function(f, t)
            if type(f) == "number" then f = host_debug.getinfo(f + 1, "f").func end
            local i = 1
            while true do
                local n = host_debug.getupvalue(f, i)
                if n == "_ENV" then host_debug.upvaluejoin(f, i, function() return t end, 1) break end
                if not n then break end
                i = i + 1
            end
            return f
        end
        env.getfenv = function(f)
            f = f or 1
            if type(f) == "number" then
                if f == 0 then return env end
                local info = host_debug.getinfo(f + 1, "f")
                f = info and info.func
            end
            if type(f) == "function" then
                local i = 1
                while true do
                    local n, v = host_debug.getupvalue(f, i)
                    if n == "_ENV" then return v end
                    if not n then break end
                    i = i + 1
                end
            end
            return env
        end
        env.term, env.fs, env.os, env.peripheral, env.redstone, env.rs = copy(native), copy(fsn), copy(osn), copy(pern), copy(rsn), copy(rsn)
        if cfg.http_map then env.http = makeHttp() end
        E.env = env

        local f = assert(host_io.open(BIOS, "rb"))
        local src = f:read("*a")
        f:close()
        local fn = assert(host_load(src, "@bios.lua", "t", env))
        E.co = coroutine.create(fn)
        E.powered = true
        resume()
    end

    -- Advance virtual time by dt seconds, delivering queued events and timers.
    function E.run(dt)
        local target = E.vclock + dt
        local n = 0
        while E.powered do
            if E.pending == "reboot" then
                E.boots = (E.boots or 0) + 1
                E.boot()
            elseif E.pending == "shutdown" then
                E.powered = false
                break
            end
            local ev = table.remove(E.queue, 1)
            if not ev then
                local best
                for i, t in ipairs(E.timers) do
                    if not best or t.at < E.timers[best].at then best = i end
                end
                if best and E.timers[best].at <= target then
                    local t = table.remove(E.timers, best)
                    if t.at > E.vclock then E.vclock = t.at end
                    ev = table.pack("timer", t.id)
                else
                    E.vclock = target
                    break
                end
            end
            if E.filter == nil or ev[1] == E.filter or ev[1] == "terminate" then
                resume(table.unpack(ev, 1, ev.n))
            end
            n = n + 1
            if n > 200000 then error("emu: event storm (more than 200000 events in one run)") end
        end
        return E.powered
    end

    function E.queue_event(...) E.queue[#E.queue + 1] = table.pack(...) end
    function E.key_code(name) return E.env.keys and E.env.keys[name] end

    -- Screen contents for screenshots: rows joined by "\n", plus cursor and palette.
    function E.dump()
        local pal = {}
        for i = 0, 15 do pal[#pal + 1] = ("%06x"):format(scr.pal[i]) end
        return table.concat(scr.text, "\n"), table.concat(scr.fg, "\n"), table.concat(scr.bg, "\n"),
            table.concat(pal, ","), scr.cx, scr.cy, scr.blink
    end

    -- Run a snippet of Lua inside the computer's global environment (for test assertions).
    function E.eval(code)
        local fn, err = host_load(code, "=eval", "t", E.env)
        if not fn then error(err) end
        return fn()
    end

    return E
end
