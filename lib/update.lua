-- Phoenix OS updater. Used by Settings > Updates and the shell's `update` command.
--
--   local update = require("update")
--   local info = update.check()            -- what's online vs what's installed
--   update.install(info, function(done, total, path) ... end)
--
-- Updates come from GitHub. Each install keeps a copy of the manifest it came
-- from in /system/manifest.txt; the "build" line in it changes whenever any
-- file does, so even untagged development changes show up as an update.
-- Accounts, settings and user files (/etc, /usr) are never touched.
local U = {}

U.REPO = "MADDXSTUDIOS/Phoenix-OS"
local LOCAL = "/system/manifest.txt"
local CONFIG = "/etc/update.cfg"

-- Only these places are ever written or cleaned up by an update.
local function managed(path)
    return path == "startup.lua" or path:match("^system/") or path:match("^lib/") or path:match("^apps/")
end

local function parse(text)
    local m = { files = {} }
    for line in (text or ""):gmatch("[^\r\n]+") do
        local key, value = line:match("^#%s*(%w+)%s*=%s*(%S+)")
        if key then
            m[key] = value
        elseif line:match("%S") and not line:match("^#") then
            m.files[#m.files + 1] = line
        end
    end
    return m
end
U.parse = parse

local function readFile(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    local data = f.readAll()
    f.close()
    return data
end

function U.installed()
    return parse(readFile(LOCAL))
end

-- Which branch to update from. "main" is the normal one; another branch (say "dev")
-- gets you work in progress.
function U.getBranch()
    local cfg = textutils.unserialize(readFile(CONFIG) or "") or {}
    return type(cfg.branch) == "string" and cfg.branch or "main"
end

function U.setBranch(branch)
    if type(branch) ~= "string" or not branch:match("^[%w._/-]+$") then return false, "Bad branch name" end
    local f, err = fs.open(CONFIG, "w")
    if not f then return false, err end
    f.write(textutils.serialize({ branch = branch }))
    f.close()
    return true
end

local function get(url, binary)
    local res, err = http.get(url, nil, binary)
    if not res then return nil, err end
    local body = res.readAll()
    res.close()
    return body
end

-- GitHub's raw file server caches a branch for a few minutes, so a fresh push can
-- look like "no update". Asking the API for the branch's latest commit and
-- downloading from that commit avoids the cache. If the API is unreachable
-- (it allows 60 requests an hour per server), fall back to the branch itself.
local function resolve(branch)
    local body = get("https://api.github.com/repos/" .. U.REPO .. "/commits/" .. textutils.urlEncode(branch))
    local sha = body and body:match('"sha"%s*:%s*"(%x+)"')
    return sha or branch, sha
end

-- Returns { available, version, build, commit, branch, base, manifest, current } or nil, error.
function U.check(branch)
    if not http then return nil, "The http API is switched off on this server" end
    branch = branch or U.getBranch()
    local ref, sha = resolve(branch)
    local base = "https://raw.githubusercontent.com/" .. U.REPO .. "/" .. ref .. "/"
    local text, err = get(base .. "manifest.txt")
    if not text then return nil, "Couldn't reach the update server: " .. tostring(err) end
    local m = parse(text)
    if #m.files == 0 then return nil, "The update file list is empty" end
    local current = U.installed()
    return {
        available = m.build == nil or m.build ~= current.build,
        version = m.version, build = m.build, commit = sha and sha:sub(1, 7), branch = branch,
        base = base, manifest = text, files = m.files, current = current,
    }
end

-- Download everything first, then write, so a failed download changes nothing.
-- progress(done, total, path) is called as files arrive. Returns true or nil, error.
function U.install(info, progress)
    local got = {}
    for i, path in ipairs(info.files) do
        if not managed(path) then return nil, "Refusing to write " .. path end
        if progress then progress(i - 1, #info.files, path) end
        local body, err = get(info.base .. path, true)
        if not body then return nil, "Failed on " .. path .. ": " .. tostring(err) end
        got[path] = body
    end
    if progress then progress(#info.files, #info.files, nil) end

    for path, body in pairs(got) do
        local f, err = fs.open("/" .. path, "wb")
        if not f then return nil, "Couldn't write " .. path .. ": " .. tostring(err) end
        f.write(body)
        f.close()
    end
    -- Remove files the new version no longer has.
    local keep = {}
    for _, path in ipairs(info.files) do keep[path] = true end
    for _, path in ipairs(info.current.files) do
        if not keep[path] and managed(path) and fs.exists("/" .. path) then fs.delete("/" .. path) end
    end
    local f = fs.open(LOCAL, "w")
    f.write(info.manifest)
    f.close()
    return true
end

-- "0.1.1 (1a2b3c)" style text for showing to people: version and the start of the build.
function U.describe(m)
    if not m.version then return "unknown" end
    return m.version .. (m.build and (" (" .. m.build:sub(1, 6) .. ")") or "")
end

return U
