-- Local accounts: /etc/users.db holds names, salted password hashes and admin flags.
local sys = sys
local sha = sys.sha256
local U = {}
local PATH = "/etc/users.db"
local ROUNDS = 200
local db

local function load()
    if db then return db end
    db = { users = {} }
    if fs.exists(PATH) then
        local f = fs.open(PATH, "r")
        local data = textutils.unserialize(f.readAll() or "")
        f.close()
        if type(data) == "table" and type(data.users) == "table" then db = data end
    end
    return db
end

local function save()
    local f = fs.open(PATH, "w")
    f.write(textutils.serialize(db))
    f.close()
end

local function hash(password, salt)
    local h = sha.hex(salt .. password)
    for _ = 1, ROUNDS do h = sha.hex(h .. salt .. password) end
    return h
end

local function newSalt()
    local s = ""
    for _ = 1, 16 do s = s .. ("%x"):format(math.random(0, 15)) end
    return s
end

function U.home(name) return "/usr/" .. name end

-- Names are lower case: letters, numbers, dot, dash, underscore; 1 to 16 characters.
function U.validName(name)
    if type(name) ~= "string" or #name < 1 then return false, "Enter a username" end
    if #name > 16 then return false, "Username is too long (16 max)" end
    if not name:match("^[a-z0-9][a-z0-9._-]*$") then return false, "Use letters, numbers, . - _ only" end
    if name == "system" or name == "root" then return false, "That name is reserved" end
    return true
end

function U.count()
    local n = 0
    for _ in pairs(load().users) do n = n + 1 end
    return n
end

function U.exists(name) return load().users[name] ~= nil end

function U.get(name)
    local u = load().users[name]
    if not u then return nil end
    return { name = name, admin = u.admin and true or false, created = u.created }
end

function U.list()
    local out = {}
    for name in pairs(load().users) do out[#out + 1] = U.get(name) end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function U.verify(name, password)
    local u = load().users[name]
    if not u or type(password) ~= "string" then return nil end
    if hash(password, u.salt) ~= u.hash then return nil end
    return U.get(name)
end

function U.add(name, password, admin)
    local ok, err = U.validName(name)
    if not ok then return false, err end
    if load().users[name] then return false, "That user already exists" end
    if type(password) ~= "string" or #password < 1 then return false, "Enter a password" end
    local salt = newSalt()
    db.users[name] = { salt = salt, hash = hash(password, salt), admin = admin and true or false, created = os.epoch("utc") }
    save()
    fs.makeDir(U.home(name))
    fs.makeDir(U.home(name) .. "/documents")
    return true
end

local function admins()
    local n = 0
    for _, u in pairs(load().users) do if u.admin then n = n + 1 end end
    return n
end

function U.remove(name)
    local u = load().users[name]
    if not u then return false, "No such user" end
    if u.admin and admins() <= 1 then return false, "Can't remove the last administrator" end
    db.users[name] = nil
    save()
    return true
end

function U.setPassword(name, password)
    local u = load().users[name]
    if not u then return false, "No such user" end
    if type(password) ~= "string" or #password < 1 then return false, "Enter a password" end
    u.salt = newSalt()
    u.hash = hash(password, u.salt)
    save()
    return true
end

function U.setAdmin(name, admin)
    local u = load().users[name]
    if not u then return false, "No such user" end
    if u.admin and not admin and admins() <= 1 then return false, "Can't demote the last administrator" end
    u.admin = admin and true or false
    save()
    return true
end

return U
