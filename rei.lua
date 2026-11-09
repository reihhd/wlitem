-- main_bbvalues.luau
-- Blade Ball Booth Scanner — Dual Source: Manual (Bot) + Auto (BBValues)
-- FIXED: "Both" mode now evaluates BOTH sources in one pass (no double-scan/skip bug).
-- Hanya scan item dengan value > 100
-- Made by Rei

local Players         = game:GetService("Players")
local LocalPlayer     = Players.LocalPlayer
local HttpService     = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

-- ── CONFIG ────────────────────────────────────────────────────────────────────
local ROOT_PLACE_ID = 16581637217
local PLACE_ID      = ROOT_PLACE_ID
local API_BASE      = "https://api.om-ni.my.id"
local SCANS_URL     = API_BASE .. "/scans"
local HEARTBEAT_URL = API_BASE .. "/heartbeat"
local BBVALUES_URL  = API_BASE .. "/bbvalues.json"
local VALUES_URL    = API_BASE .. "/values.json"
local SCANNED_URL   = API_BASE .. "/scanned"
local SCANNER_KEY   = "edDpaouIfWd-mPN6mz-eCWndYmXO9mgG57_yjxC3ApA"
local API_HEADERS   = { ["X-Scanner-Key"] = SCANNER_KEY }
local MIN_VALUE      = 100
local DEFAULT_UNDER  = 20
local HOP_SKIP_COUNT = 20
local HOP_HISTORY_FILE = "hop_history.json"
-- ─────────────────────────────────────────────────────────────────────────────

local hopHistory = {}
local isTeleporting = false

local function apiPost(url, data)
    local opts = {
        Url = url, Method = "POST",
        Headers = { ["Content-Type"] = "application/json", ["X-Scanner-Key"] = SCANNER_KEY },
        Body = HttpService:JSONEncode(data),
    }
    local req = request or http_request or (syn and syn.request)
    if req then
        local ok, res = pcall(req, opts)
        if ok and type(res) == "table" then
            return tonumber(res.StatusCode) or 0, res.Body or ""
        end
        return 0, ""
    end
    local ok, res = pcall(function() return HttpService:RequestAsync(opts) end)
    if ok and type(res) == "table" then return res.StatusCode or 0, res.Body or "" end
    return 0, ""
end

local function loadHopHistory()
    if readfile then
        local ok, content = pcall(readfile, HOP_HISTORY_FILE)
        if ok and content ~= "" then
            local ok2, data = pcall(function() return HttpService:JSONDecode(content) end)
            if ok2 and type(data) == "table" then hopHistory = data return end
        end
    end
    hopHistory = {}
end

local function saveHopHistory()
    if writefile then
        pcall(writefile, HOP_HISTORY_FILE, HttpService:JSONEncode(hopHistory))
    end
end

local function addToHistory(jobId)
    table.insert(hopHistory, jobId)
    while #hopHistory > HOP_SKIP_COUNT do table.remove(hopHistory, 1) end
    saveHopHistory()
end

local function isInHistory(jobId)
    for _, id in ipairs(hopHistory) do
        if id == jobId then return true end
    end
    return false
end

local httpGet

-- ── SHARED SCANNED SERVERS ────────────────────────────────────────────────────

local sharedScannedCache = {}
local lastScannedFetch = 0
local SCANNED_FETCH_INTERVAL = 10
local SCANNED_LOCAL_TTL = 300

local function fetchSharedScanned()
    if (os.time() - lastScannedFetch) < SCANNED_FETCH_INTERVAL then
        return
    end
    local ok2, body = pcall(function()
        return httpGet(SCANNED_URL .. ".json", API_HEADERS)
    end)
    if not ok2 or not body then
        lastScannedFetch = os.time()
        return
    end
    if body:sub(1, 1) == "{" then
        local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
        if ok and type(data) == "table" then
            local now = os.time()
            local merged = {}
            for jid, ts in pairs(sharedScannedCache) do
                if (now - ts) < SCANNED_LOCAL_TTL then
                    merged[jid] = ts
                end
            end
            for jid, ts in pairs(data) do
                if type(ts) == "number" then
                    local localTs = merged[jid]
                    if not localTs then
                        merged[jid] = now
                    end
                end
            end
            sharedScannedCache = merged
            lastScannedFetch = os.time()
        end
    end
end

local function markServerScanned(jobId)
    sharedScannedCache[jobId] = os.time()
    task.spawn(function()
        apiPost(SCANNED_URL, { job_id = jobId, username = LocalPlayer.Name })
    end)
end

local function isServerScanned(jobId)
    local t = sharedScannedCache[jobId]
    if not t then return false end
    if (os.time() - t) >= SCANNED_LOCAL_TTL then
        sharedScannedCache[jobId] = nil
        return false
    end
    return true
end

task.spawn(function()
    while true do
        pcall(fetchSharedScanned)
        task.wait(SCANNED_FETCH_INTERVAL)
    end
end)

-- ── OBSIDIAN ──────────────────────────────────────────────────────────────────
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

Library.ForceCheckbox = false
Library.ShowToggleFrameInKeybinds = true

local Window = Library:CreateWindow({
    Title = "Booth Scanner (BBValues)",
    Footer = "Made by Rei",
    Icon = 95816097006870,
    NotifySide = "Right",
    ShowCustomCursor = true,
})

-- ── UTILITY ───────────────────────────────────────────────────────────────────

function httpGet(url, extraHeaders)
    local headers = {
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        ["Accept"] = "application/json",
    }
    if extraHeaders then
        for k, v in pairs(extraHeaders) do headers[k] = v end
    end
    if request then
        local ok, res = pcall(request, { Url = url, Method = "GET", Headers = headers })
        if ok and res and res.Body and res.Body ~= "" then return res.Body end
    end
    if syn and syn.request then
        local ok, res = pcall(syn.request, { Url = url, Method = "GET", Headers = headers })
        if ok and res and res.Body and res.Body ~= "" then return res.Body end
    end
    local ok, body = pcall(function() return HttpService:GetAsync(url) end)
    return ok and body or nil
end

local function parseNumber(str)
    if not str then return nil end
    local clean = tostring(str):gsub(",", ""):gsub("%s+", "")
    return tonumber(clean)
end

local usernameCache = {}
local function getUsername(userId)
    if usernameCache[userId] then return usernameCache[userId] end
    local plr = Players:GetPlayerByUserId(userId)
    local name = plr and plr.Name
    if not name then
        local ok, n = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
        name = ok and n or nil
    end
    if name then usernameCache[userId] = name end
    return name or tostring(userId)
end

local function getDisplayName(userId)
    local ok, info = pcall(function()
        local player = Players:GetPlayerByUserId(userId)
        if player then return player.DisplayName end
        return nil
    end)
    return ok and info or nil
end

local function postScanToAPI(data)
    for attempt = 1, 3 do
        local code, body = apiPost(SCANS_URL, data)
        if code >= 200 and code < 300 then
            if string.find(body or "", "duplicate", 1, true) then return "duplicate" end
            return "ok"
        end
        if code == 400 or code == 401 or code == 403 or code == 503 then
            warn(string.format("[scanner] /scans ditolak (%d): %s", code, tostring(body)))
            return "failed"
        end
        task.wait(attempt)
    end
    warn("[scanner] /scans gagal setelah 3x percobaan: " .. tostring(data.item_name))
    return "failed"
end

local function sendHeartbeat()
    apiPost(HEARTBEAT_URL, { username = LocalPlayer.Name, job_id = game.JobId })
end

task.spawn(function()
    while true do
        pcall(sendHeartbeat)
        task.wait(120)
    end
end)

-- ── BBVALUES.UK API ───────────────────────────────────────────────────────────

local BBVALUES_CACHE_FILE = "bbvalues_cache.json"
local cachedBBValues = nil
local lastFetchTime  = 0
local CACHE_TTL      = 300

local function parseBBValuesBody(body)
    if not body or body == "" then return nil end
    if body:sub(1, 1) ~= "[" then return nil end
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok or type(data) ~= "table" then return nil end
    return data
end

local function buildValuesLookup(data)
    local values = {}
    local count = 0
    local filtered = 0
    local dupeCount = 0
    for _, item in ipairs(data) do
        local name = item.n
        local value = item.p
        if name and value then
            if value > MIN_VALUE then
                local key = string.lower(name)
                local entry = {
                    value    = value,
                    category = item.c or "unknown",
                    rarity   = item.r or "NORMAL",
                    status   = item.st or "stable",
                    tag      = item.tg or "",
                    finisher = (item.s == "Finisher"),
                    source   = item.s or "None",
                    avg      = item.a or 0,
                    change   = item.ch or 0,
                    itemId   = item.id or "",
                }
                if not values[key] then
                    values[key] = { entry }
                else
                    table.insert(values[key], entry)
                    dupeCount += 1
                end
                count += 1
            else
                filtered += 1
            end
        end
    end
    print(string.format("[bbvalues] Built lookup: %d items (%d dupes, filtered %d with value <= %d)", count, dupeCount, filtered, MIN_VALUE))
    return values, count
end

local function saveBBValuesCache(body)
    if writefile then
        pcall(writefile, BBVALUES_CACHE_FILE, body)
        print("[bbvalues] Cache saved to file")
    end
end

local function loadBBValuesFromFile()
    if not readfile then return nil end
    local ok, content = pcall(readfile, BBVALUES_CACHE_FILE)
    if not ok or not content or content == "" then return nil end
    local data = parseBBValuesBody(content)
    if data and #data > 100 then
        print("[bbvalues] Loaded " .. #data .. " items from file cache")
        return data
    end
    return nil
end

local function fetchBBValuesRaw()
    return httpGet(BBVALUES_URL, {})
end

local function loadBBValues()
    if cachedBBValues and (os.time() - lastFetchTime) < CACHE_TTL then
        print("[bbvalues] Using in-memory cache (" .. (os.time() - lastFetchTime) .. "s old)")
        return cachedBBValues
    end

    local MAX_RETRIES = 3
    local body = nil
    for attempt = 1, MAX_RETRIES do
        print(string.format("[bbvalues] Fetch attempt %d/%d...", attempt, MAX_RETRIES))
        body = fetchBBValuesRaw()
        local data = parseBBValuesBody(body)
        if data and #data > 100 then
            print("[bbvalues] API fetch OK: " .. #data .. " items")
            saveBBValuesCache(body)
            local values, count = buildValuesLookup(data)
            if count > 0 then
                cachedBBValues = values
                lastFetchTime = os.time()
                return values
            end
        end
        if body then
            local preview = body:sub(1, 80):gsub("%s+", " ")
            warn(string.format("[bbvalues] Attempt %d failed: %s", attempt, preview))
        else
            warn(string.format("[bbvalues] Attempt %d failed: nil response", attempt))
        end
        if attempt < MAX_RETRIES then
            local delay = attempt * 3
            print("[bbvalues] Retrying in " .. delay .. "s...")
            task.wait(delay)
        end
    end

    if cachedBBValues then
        local age = os.time() - lastFetchTime
        warn(string.format("[bbvalues] API failed, using expired in-memory cache (%ds old)", age))
        Library:Notify({ Title = "BBValues", Description = string.format("API down, using cache (%dm old)", math.floor(age / 60)), Time = 5 })
        return cachedBBValues
    end

    local fileData = loadBBValuesFromFile()
    if fileData then
        local values, count = buildValuesLookup(fileData)
        if count > 0 then
            cachedBBValues = values
            lastFetchTime = os.time() - CACHE_TTL + 60
            warn("[bbvalues] API failed, using file cache")
            Library:Notify({ Title = "BBValues", Description = "API down, using saved cache", Time = 5 })
            return values
        end
    end

    warn("[bbvalues] All attempts failed, no cache available")
    return {}
end

-- ── ASSET ID → CATEGORY MAP ───────────────────────────────────────────────────

local ASSET_CATEGORY_MAP = {
    ["16266665378"]        = "Sword",
    ["103991473928751"]    = "Emote",
    ["122220220272317"]    = "Explosion",
    ["129131763936203"]    = "Explosion",
    ["17757365730"]        = "Sword",
    ["121538626129831"]    = "Sword",
    ["122139166298284"]    = "Emote",
    ["15965812017"]        = "Sword",
    ["15964013112"]        = "Explosion",
    ["135913442813047"]    = "Emote",
    ["77190288652210"]     = "Sword",
    ["72309796878320"]     = "Emote",
    ["98895700264373"]     = "Sword",
    ["114649402355251"]    = "Explosion",
    ["136298174298208"]    = "Emote",
    ["126034810019036"]    = "Sword",
    ["77798050960530"]     = "Sword",
    ["94990619459773"]     = "Emote",
    ["91449061436707"]     = "Emote",
    ["135684393446468"]    = "Sword",
    ["72687727611270"]     = "Sword",
    ["132530935111167"]    = "Emote",
    ["15862986776"]        = "Emote",
    ["78573433974758"]     = "Explosion",
    ["135381650702325"]    = "Sword",
    ["97054245713645"]     = "Emote",
}

local function resolveByAssetId(assetId, variants, sellPrice)
    if not assetId or assetId == "" then return nil end
    local id = assetId:match("(%d+)$")
    if not id then return nil end
    
    local targetCat = ASSET_CATEGORY_MAP[id]
    if not targetCat then return nil end
    
    for _, v in ipairs(variants) do
        if v.category == targetCat then
            local threshold = v.value - DEFAULT_UNDER
            return v, sellPrice and sellPrice <= threshold or false
        end
    end
    return nil
end

local CATEGORY_EXCEPTIONS = {
    ["astral seraph blade"]              = { { 1938, "Emote" }, { math.huge, "Sword" } },
    ["aurora burst"]                     = { { 11, "Explosion" }, { math.huge, "Emote" } },
    ["axolotl scythe"]                   = { { 320, "Emote" }, { math.huge, "Sword" } },
    ["ball drop"]                        = { { 119, "Explosion" }, { math.huge, "Emote" } },
    ["bittersweet scythe"]               = { { 493, "Emote" }, { math.huge, "Sword" } },
    ["blue bunny scythe"]                = { { 334, "Emote" }, { math.huge, "Sword" } },
    ["celestial dawn scythe"]            = { { 169, "Emote" }, { math.huge, "Sword" } },
    ["celestial hero bow"]               = { { 279, "Emote" }, { math.huge, "Sword" } },
    ["cherry blossom spear"]             = { { 423, "Emote" }, { math.huge, "Sword" } },
    ["chrome dracula spear"]             = { { 253, "Emote" }, { math.huge, "Sword" } },
    ["coal"]                             = { { 2, "Sword" }, { math.huge, "Explosion" } },
    ["confetti burst"]                   = { { 4, "Explosion" }, { math.huge, "Emote" } },
    ["corrupt blossom bow"]              = { { 249, "Emote" }, { math.huge, "Sword" } },
    ["crimson kagune"]                   = { { 1676, "Emote" }, { math.huge, "Sword" } },
    ["crystal ribbon scythe"]            = { { 270, "Emote" }, { math.huge, "Sword" } },
    ["death call scythe"]                = { { 305, "Emote" }, { math.huge, "Sword" } },
    ["deathrider"]                       = { { 5080, "Emote" }, { math.huge, "Sword" } },
    ["deathwarden lance"]                = { { 193, "Emote" }, { math.huge, "Sword" } },
    ["divine ruin bow"]                  = { { 190, "Emote" }, { math.huge, "Sword" } },
    ["dual axolotl blade"]               = { { 322, "Emote" }, { math.huge, "Sword" } },
    ["dual axolotl scythe"]              = { { 541, "Emote" }, { math.huge, "Sword" } },
    ["dual bittersweet blade"]           = { { 493, "Emote" }, { math.huge, "Sword" } },
    ["dual bittersweet scythe"]          = { { 536, "Emote" }, { math.huge, "Sword" } },
    ["dual blue bunny katana"]           = { { 288, "Emote" }, { math.huge, "Sword" } },
    ["dual blue bunny scythe"]           = { { 469, "Emote" }, { math.huge, "Sword" } },
    ["dual celestial dawn blade"]        = { { 203, "Emote" }, { math.huge, "Sword" } },
    ["dual celestial dawn scythe"]       = { { 244, "Emote" }, { math.huge, "Sword" } },
    ["dual celestial hero blade"]        = { { 317, "Emote" }, { math.huge, "Sword" } },
    ["dual cherry blossom blade"]        = { { 214, "Emote" }, { math.huge, "Sword" } },
    ["dual corrupt blossom blade"]       = { { 204, "Emote" }, { math.huge, "Sword" } },
    ["dual crystal ribbon scythe"]       = { { 340, "Emote" }, { math.huge, "Sword" } },
    ["dual death call blade"]            = { { 184, "Emote" }, { math.huge, "Sword" } },
    ["dual death call scythe"]           = { { 337, "Emote" }, { math.huge, "Sword" } },
    ["dual deathwarden blade"]           = { { 175, "Emote" }, { math.huge, "Sword" } },
    ["dual electro katana"]              = { { 136, "Emote" }, { math.huge, "Sword" } },
    ["dual flashback butterfly blade"]   = { { 195, "Emote" }, { math.huge, "Sword" } },
    ["dual flashback butterfly scythe"]  = { { 353, "Emote" }, { math.huge, "Sword" } },
    ["dual gothic bunny blade"]          = { { 374, "Emote" }, { math.huge, "Sword" } },
    ["dual gothic bunny scythe"]         = { { 545, "Emote" }, { math.huge, "Sword" } },
    ["dual gothic heartpiercer blade"]   = { { 211, "Emote" }, { math.huge, "Sword" } },
    ["dual hazy katana"]                 = { { 247, "Emote" }, { math.huge, "Sword" } },
    ["dual hazy scythe"]                 = { { 471, "Emote" }, { math.huge, "Sword" } },
    ["dual hidden beast blade"]          = { { 149, "Emote" }, { math.huge, "Sword" } },
    ["dual hidden beast scythe"]         = { { 304, "Emote" }, { math.huge, "Sword" } },
    ["dual jade blade"]                  = { { 122, "Emote" }, { math.huge, "Sword" } },
    ["dual jade scythe"]                 = { { 201, "Emote" }, { math.huge, "Sword" } },
    ["dual luv4pain blade"]              = { { 286, "Emote" }, { math.huge, "Sword" } },
    ["dual luv4pain scythe"]             = { { 386, "Emote" }, { math.huge, "Sword" } },
    ["dual masked horror blade"]         = { { 146, "Emote" }, { math.huge, "Sword" } },
    ["dual masked horror scythe"]        = { { 223, "Emote" }, { math.huge, "Sword" } },
    ["dual moon cycle scythe"]           = { { 223, "Emote" }, { math.huge, "Sword" } },
    ["dual moonlight blade"]             = { { 144, "Emote" }, { math.huge, "Sword" } },
    ["dual neo-neko katana"]             = { { 476, "Emote" }, { math.huge, "Sword" } },
    ["dual primordial blade"]            = { { 142, "Emote" }, { math.huge, "Sword" } },
    ["dual prince legacy scythe"]        = { { 373, "Emote" }, { math.huge, "Sword" } },
    ["dual prismatic gem blade"]         = { { 174, "Emote" }, { math.huge, "Sword" } },
    ["dual prismatic gem scythe"]        = { { 220, "Emote" }, { math.huge, "Sword" } },
    ["dual radiant duckling kunai"]      = { { 199, "Emote" }, { math.huge, "Sword" } },
    ["dual reborn wings blade"]          = { { 221, "Emote" }, { math.huge, "Sword" } },
    ["dual riftflare blade"]             = { { 207, "Emote" }, { math.huge, "Sword" } },
    ["dual royal relic blade"]           = { { 114, "Emote" }, { math.huge, "Sword" } },
    ["dual silk divinity blade"]         = { { 175, "Emote" }, { math.huge, "Sword" } },
    ["dual spring saber"]                = { { 183, "Emote" }, { math.huge, "Sword" } },
    ["dual spring scythe"]               = { { 205, "Emote" }, { math.huge, "Sword" } },
    ["dual starfish blade"]              = { { 162, "Emote" }, { math.huge, "Sword" } },
    ["dual starfish scythe"]             = { { 277, "Emote" }, { math.huge, "Sword" } },
    ["dual strawberry cake blade"]       = { { 207, "Emote" }, { math.huge, "Sword" } },
    ["dual sugarcoated saber"]           = { { 689, "Emote" }, { math.huge, "Sword" } },
    ["dual verdant thorn blade"]         = { { 881, "Sword" }, { math.huge, "Emote" } },
    ["dual y2k blade"]                   = { { 434, "Emote" }, { math.huge, "Sword" } },
    ["electro bow"]                      = { { 196, "Emote" }, { math.huge, "Sword" } },
    ["elemental"]                        = { { 26, "Explosion" }, { math.huge, "Emote" } },
    ["ethereal bombardment"]             = { { 1435, "Explosion" }, { math.huge, "Sword" } },
    ["event horizon"]                    = { { 328, "Sword" }, { math.huge, "Emote" } },
    ["flashback butterfly scythe"]       = { { 155, "Emote" }, { math.huge, "Sword" } },
    ["ghostly vengeance"]                = { { 79, "Explosion" }, { math.huge, "Sword" } },
    ["giant egg"]                        = { { 504, "Emote" }, { math.huge, "Explosion" } },
    ["gothic bunny scythe"]              = { { 245, "Emote" }, { math.huge, "Sword" } },
    ["gothic heartpiercer bow"]          = { { 237, "Emote" }, { math.huge, "Sword" } },
    ["gravelight"]                       = { { 2502, "Emote" }, { math.huge, "Sword" } },
    ["guardian of the underworld"]       = { { 2109, "Explosion" }, { math.huge, "Sword" } },
    ["gyaru katana"]                     = { { 2620, "Emote" }, { math.huge, "Sword" } },
    ["hazy scythe"]                      = { { 182, "Emote" }, { math.huge, "Sword" } },
    ["hidden beast scythe"]              = { { 173, "Emote" }, { math.huge, "Sword" } },
    ["higanbana katana"]                 = { { 2494, "Emote" }, { math.huge, "Sword" } },
    ["high noon"]                        = { { 8, "Explosion" }, { math.huge, "Emote" } },
    ["jade scythe"]                      = { { 162, "Emote" }, { math.huge, "Sword" } },
    ["luv4pain scythe"]                  = { { 163, "Emote" }, { math.huge, "Sword" } },
    ["masked horror scythe"]             = { { 192, "Emote" }, { math.huge, "Sword" } },
    ["moon cycle scythe"]                = { { 154, "Emote" }, { math.huge, "Sword" } },
    ["moonlight bow"]                    = { { 223, "Emote" }, { math.huge, "Sword" } },
    ["nebula blade"]                     = { { 642, "Explosion" }, { math.huge, "Sword" } },
    ["neo-neko needle"]                  = { { 469, "Emote" }, { math.huge, "Sword" } },
    ["night raver"]                      = { { 2383, "Emote" }, { 6161, "Explosion" }, { math.huge, "Sword" } },
    ["phantom ops"]                      = { { 2403, "Emote" }, { math.huge, "Sword" } },
    ["phantom pact"]                     = { { 548, "Explosion" }, { 5720, "Emote" }, { math.huge, "Sword" } },
    ["primordial lance"]                 = { { 164, "Emote" }, { math.huge, "Sword" } },
    ["prince legacy scythe"]             = { { 201, "Emote" }, { math.huge, "Sword" } },
    ["prismatic gem scythe"]             = { { 166, "Emote" }, { math.huge, "Sword" } },
    ["proyection sorcery katana"]        = { { 1981, "Emote" }, { math.huge, "Sword" } },
    ["radiant duckling lance"]           = { { 224, "Emote" }, { math.huge, "Sword" } },
    ["reborn wings bow"]                 = { { 335, "Emote" }, { math.huge, "Sword" } },
    ["red moon katana"]                  = { { 1914, "Emote" }, { math.huge, "Sword" } },
    ["regret blades"]                    = { { 10887, "Emote" }, { math.huge, "Sword" } },
    ["riftflare katana"]                 = { { 1762, "Explosion" }, { math.huge, "Sword" } },
    ["riftflare lance"]                  = { { 313, "Emote" }, { math.huge, "Sword" } },
    ["royal relic bow"]                  = { { 135, "Emote" }, { math.huge, "Sword" } },
    ["sea turtle"]                       = { { 6182, "Emote" }, { math.huge, "Sword" } },
    ["silk divinity bow"]                = { { 178, "Emote" }, { math.huge, "Sword" } },
    ["snow globe"]                       = { { 24, "Emote" }, { math.huge, "Explosion" } },
    ["spring scythe"]                    = { { 162, "Emote" }, { math.huge, "Sword" } },
    ["starfall"]                         = { { 2525002, "Explosion" }, { math.huge, "Sword" } },
    ["starfish scythe"]                  = { { 225, "Emote" }, { math.huge, "Sword" } },
    ["starlit halo wings"]               = { { 7993, "Emote" }, { math.huge, "Sword" } },
    ["strawberry cake lance"]            = { { 238, "Emote" }, { math.huge, "Sword" } },
    ["sugarcoated bow"]                  = { { 380, "Emote" }, { math.huge, "Sword" } },
    ["thronebreaker"]                    = { { 4020, "Explosion" }, { math.huge, "Sword" } },
    ["verdant thorn lance"]              = { { 208, "Emote" }, { math.huge, "Sword" } },
    ["volcanic surge"]                   = { { 5, "Explosion" }, { math.huge, "Sword" } },
    ["widowbloom bow"]                   = { { 227, "Emote" }, { math.huge, "Sword" } },
    ["wolf greatsword"]                  = { { 8283, "Emote" }, { math.huge, "Sword" } },
    ["y2k bow"]                          = { { 396, "Emote" }, { math.huge, "Sword" } },
}

local function resolveException(itemName, variants, sellPrice)
    local exc = CATEGORY_EXCEPTIONS[string.lower(itemName)]
    if not exc then return nil end

    local targetCat = nil
    for _, rule in ipairs(exc) do
        if sellPrice <= rule[1] then
            targetCat = rule[2]
            break
        end
    end
    if not targetCat then return nil end

    for _, v in ipairs(variants) do
        if v.category == targetCat then
            local threshold = v.value - DEFAULT_UNDER
            return v, sellPrice <= threshold
        end
    end
    return nil
end

local function analyzeItem(itemName, variants, hasFinisher, sellPrice, assetId)
    if not sellPrice then
        return nil, false
    end

    local assetVariant, assetUnderrap = resolveByAssetId(assetId, variants, sellPrice)
    if assetVariant then
        return assetVariant, assetUnderrap
    end

    local excVariant, excUnderrap = resolveException(itemName, variants, sellPrice)
    if excVariant then
        return excVariant, excUnderrap
    end

    local finisherMatch = {}
    local finisherOther = {}
    for _, v in ipairs(variants) do
        if v.finisher == hasFinisher then
            table.insert(finisherMatch, v)
        else
            table.insert(finisherOther, v)
        end
    end

    local pool = #finisherMatch > 0 and finisherMatch or variants

    if #pool == 1 then
        local v = pool[1]
        local threshold = v.value - DEFAULT_UNDER
        local isUnderrap = sellPrice <= threshold

        if isUnderrap then
            for _, other in ipairs(finisherOther) do
                local low  = other.value - DEFAULT_UNDER
                local high = other.value * 1.5
                if sellPrice >= low and sellPrice <= high then
                    return other, false
                end
            end
        end

        return v, isUnderrap
    end

    local categoryGroups = {}
    for _, v in ipairs(pool) do
        local cat = v.category or "unknown"
        if not categoryGroups[cat] then
            categoryGroups[cat] = {}
        end
        table.insert(categoryGroups[cat], v)
    end

    local catCount = 0
    for _ in pairs(categoryGroups) do catCount += 1 end

    local closestVariant = nil
    local closestDiff = math.huge
    local closestRatio = math.huge

    for _, v in ipairs(pool) do
        local diff = math.abs(v.value - sellPrice)
        local ratio = diff / math.max(v.value, 1)
        if catCount > 1 then
            if ratio < closestRatio then
                closestRatio = ratio
                closestDiff = diff
                closestVariant = v
            end
        else
            if diff < closestDiff then
                closestDiff = diff
                closestVariant = v
            end
        end
    end

    for _, v in ipairs(finisherOther) do
        local diff = math.abs(v.value - sellPrice)
        local ratio = diff / math.max(v.value, 1)
        if catCount > 1 then
            if ratio < closestRatio then
                closestRatio = ratio
                closestDiff = diff
                closestVariant = v
            end
        else
            if diff < closestDiff then
                closestDiff = diff
                closestVariant = v
            end
        end
    end

    if closestVariant then
        local low  = closestVariant.value - DEFAULT_UNDER
        local high = closestVariant.value * 1.5
        if sellPrice >= low and sellPrice <= high then
            return closestVariant, false
        end
    end

    local cheapest = pool[1]
    for i = 2, #pool do
        if pool[i].value < cheapest.value then
            cheapest = pool[i]
        end
    end

    local threshold = cheapest.value - DEFAULT_UNDER
    local isUnderrap = sellPrice <= threshold

    if isUnderrap then
        for _, v in ipairs(variants) do
            local rangeLow = v.value * (catCount > 1 and 0.6 or 0.5)
            local rangeHigh = v.value * 1.5
            if sellPrice >= rangeLow and sellPrice <= rangeHigh then
                return v, false
            end
        end
    end

    return cheapest, isUnderrap
end

-- ── MANUAL VALUES ─────────────────────────────────────────────────────────────

local function loadManualValues()
    print("[manual] Fetching: " .. VALUES_URL)
    local body = httpGet(VALUES_URL, API_HEADERS)
    if not body then
        warn("[manual] httpGet returned nil")
        return {}
    end
    if body:sub(1, 1) ~= "{" then
        warn("[manual] Response is not JSON: " .. body:sub(1, 80))
        return {}
    end
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok then
        warn("[manual] JSONDecode failed: " .. tostring(data))
        return {}
    end
    if not data or not data.items then
        warn("[manual] No 'items' field")
        return {}
    end
    local values = {}
    local count = 0
    for k, v in pairs(data.items) do
        if not v.disabled or v.disabled == 0 then
            local val = v.value
            if val and val > MIN_VALUE then
                local rawName = v.name or k:gsub("|fin$", "")
                local fin = v.finisher == true or v.finisher == 1
                local key = string.lower(rawName)
                local underThreshold = v.under or 0
                if underThreshold == 0 then underThreshold = val - DEFAULT_UNDER end
                local entry = {
                    value    = val,
                    category = v.category or "sword",
                    rarity   = "MANUAL",
                    status   = "manual",
                    finisher = fin,
                    source   = "manual",
                    avg      = 0,
                    change   = 0,
                    itemId   = "",
                    underThreshold = underThreshold,
                }
                if not values[key] then
                    values[key] = { entry }
                else
                    table.insert(values[key], entry)
                end
                count += 1
            end
        end
    end
    print(string.format("[manual] Loaded %d items from bot", count))
    return values, count
end

-- ── BOOTH SCAN HELPERS ────────────────────────────────────────────────────────

local function firePrompt(prompt)
    if typeof(prompt) ~= "Instance" or not prompt:IsA("ProximityPrompt") then return false end
    if fireproximityprompt then
        fireproximityprompt(prompt)
        return true
    end
    local ok = pcall(function()
        prompt:InputHoldBegin()
        task.wait(0.05)
        prompt:InputHoldEnd()
    end)
    return ok
end

local function getScrollingList()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local booth = pg:FindFirstChild("Booth")
    if not booth then return nil end
    local pb = booth:FindFirstChild("PlayersBooth")
    if not pb then return nil end
    return pb:FindFirstChild("ScrollingList")
end

local function scanCurrentBooth()
    local list = getScrollingList()
    if not list then return {} end
    local items = {}
    for _, entry in ipairs(list:GetChildren()) do
        local itemName, amount, hasFinisher = "", "", false
        local frame = entry:FindFirstChild("Frame")
        local assetId = ""
        if frame then
            local nl = frame:FindFirstChild("ItemName")
            if nl and (nl:IsA("TextLabel") or nl:IsA("TextBox")) then itemName = nl.Text end
            local fin = frame:FindFirstChild("Finisher")
            if fin and fin:IsA("GuiObject") then hasFinisher = fin.Visible end
            local vec = frame:FindFirstChild("Vector")
            if vec and (vec:IsA("ImageLabel") or vec:IsA("ImageButton")) then
                local img = vec.Image
                if img and img ~= "" then
                    assetId = img
                end
            end
        end
        local bb = entry:FindFirstChild("BuyButton")
        if bb then
            local li = bb:FindFirstChild("List")
            if li then
                local al = li:FindFirstChild("Amount")
                if al and (al:IsA("TextLabel") or al:IsA("TextBox")) then amount = al.Text end
            end
        end
        if itemName ~= "" then
            table.insert(items, { name = itemName, price = amount, finisher = hasFinisher, assetId = assetId })
        end
    end
    return items
end

-- ── SERVER HOP ────────────────────────────────────────────────────────────────

local function getServerList()
    local url = string.format(
        "https://games.roblox.com/v1/games/%d/servers/Public?limit=100", PLACE_ID
    )
    local body = httpGet(url)
    if not body then return {} end
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok or not data or not data.data then return {} end
    local servers = {}
    for _, s in ipairs(data.data) do
        table.insert(servers, { jobId = s.id, players = s.playing, maxPlayers = s.maxPlayers })
    end
    return servers
end

local function joinServer(jobId)
    addToHistory(game.JobId)
    TeleportService:TeleportToPlaceInstance(PLACE_ID, jobId, LocalPlayer)
end

local function pickNextServer()
    local servers = getServerList()
    if #servers == 0 then return nil end
    for i = #servers, 2, -1 do
        local j = math.random(i)
        servers[i], servers[j] = servers[j], servers[i]
    end
    local currentJob = game.JobId
    for _, s in ipairs(servers) do
        if s.jobId ~= currentJob and not isInHistory(s.jobId) and not isServerScanned(s.jobId) then
            return s.jobId
        end
    end
    for _, s in ipairs(servers) do
        if s.jobId ~= currentJob and not isInHistory(s.jobId) then
            return s.jobId
        end
    end
    warn("[hop] All servers in history, resetting")
    hopHistory = {}
    saveHopHistory()
    for _, s in ipairs(servers) do
        if s.jobId ~= currentJob then return s.jobId end
    end
    return nil
end

local function doHop(reason)
    local currentJob = game.JobId
    for attempt = 1, 5 do
        Library:Notify({ Title = "Auto Hop", Description = string.format("%s (%d/5)", reason, attempt), Time = 2 })
        local nextServer = pickNextServer()
        if not nextServer then
            warn("[hop] No server found, attempt " .. attempt)
            task.wait(3)
            continue
        end
        isTeleporting = true
        joinServer(nextServer)
        task.wait(6)
        if game.JobId ~= currentJob then
            return true
        end
        isTeleporting = false
        addToHistory(nextServer)
        warn("[hop] Teleport failed attempt " .. attempt)
        task.wait(1)
    end
    isTeleporting = false
    Library:Notify({ Title = "Auto Hop", Description = "All attempts failed", Time = 5 })
    return false
end

-- ── SCAN ALL BOOTHS (REWRITTEN FOR "BOTH" MODE) ──────────────────────────────

local autoHopEnabled  = true
local autoScanEnabled = true
local autoScanThread  = nil
local scanMode        = "auto"

local lastUnderrapInfo = nil

local function stopAutoScan()
    if autoScanThread then
        task.cancel(autoScanThread)
        autoScanThread = nil
    end
end

local scanAllBooths = nil

-- Batches both sources so "Both" mode scans once per booth and picks the best deal.
-- valuesBySource = { auto = <bbvalues lookup|nil>, manual = <manual lookup|nil> }
scanAllBooths = function(valuesBySource)
    if isTeleporting then
        print("[scanner] Skipping scan — teleporting")
        return
    end

    local currentJobId = game.JobId

    if isServerScanned(currentJobId) then
        print("[scanner] Server " .. currentJobId:sub(1, 8) .. " already scanned, skipping")
        return
    end

    local stands = workspace:FindFirstChild("Spawn")
        and workspace.Spawn:FindFirstChild("Hub")
        and workspace.Spawn.Hub:FindFirstChild("Stands")

    if not stands then
        warn("[scanner] Stands not found")
        Library:Notify({ Title = "Error", Description = "Stands not found", Time = 5 })
        return
    end

    local results = {}
    local boothCount, underrapCount = 0, 0
    local sentOk, sentDup, sentFail = 0, 0, 0
    local sourceStats = { auto = 0, manual = 0, both = 0 }
    local pendingSends = 0

    for _, booth in ipairs(stands:GetChildren()) do
        local ownerId = booth:GetAttribute("Owner")
        if ownerId == nil then continue end
        boothCount += 1

        local boothX, boothY, boothZ = 0, 0, 0
        do
            local pos
            local okPivot = pcall(function() pos = booth:GetPivot().Position end)
            if (not okPivot or not pos) then
                local r = booth:FindFirstChild("Root")
                if r and r:IsA("BasePart") then pos = r.Position end
                if not pos and r then
                    local anyPart = r:FindFirstChildWhichIsA("BasePart", true)
                    if anyPart then pos = anyPart.Position end
                end
            end
            if pos then
                boothX = math.floor(pos.X * 100 + 0.5) / 100
                boothY = math.floor(pos.Y * 100 + 0.5) / 100
                boothZ = math.floor(pos.Z * 100 + 0.5) / 100
            end
        end

        local prompt = nil
        local root = booth:FindFirstChild("Root")
        if root then
            local holder = root:FindFirstChild("ProximityPromptHolder")
            if holder then prompt = holder:FindFirstChild("BoothProximityPrompt") end
        end
        if prompt then firePrompt(prompt) task.wait(0.1) end

        local items    = scanCurrentBooth()
        local username = getUsername(ownerId)

        local sellerSales, sellerRap = -1, -1
        do
            local sellerPlayer = Players:GetPlayerByUserId(ownerId)
            if sellerPlayer then
                local ls = sellerPlayer:FindFirstChild("leaderstats")
                if ls then
                    local salesVal = ls:FindFirstChild("Sales")
                    if salesVal and salesVal:IsA("IntValue") then sellerSales = salesVal.Value end
                    local rapVal = ls:FindFirstChild("RAP")
                    if rapVal and rapVal:IsA("IntValue") then sellerRap = rapVal.Value end
                end
            end
        end

        table.insert(results, string.format("=== Booth: %s (%s) ===", username, tostring(ownerId)))

        for slotIdx, item in ipairs(items) do
            item.sellerSales = sellerSales
            item.sellerRap   = sellerRap

            local sellPrice = parseNumber(item.price)
            if not sellPrice then continue end

            local key = string.lower(item.name)
            local underrapCandidates = {}

            -- ── Evaluate AUTO source ──
            if valuesBySource.auto then
                local variants = valuesBySource.auto[key]
                if variants then
                    local v, isU = analyzeItem(item.name, variants, item.finisher, sellPrice, item.assetId)
                    if v and isU then
                        table.insert(underrapCandidates, {
                            variant = v,
                            source = "auto",
                            variantCount = #variants,
                        })
                    end
                end
            end

            -- ── Evaluate MANUAL source ──
            if valuesBySource.manual then
                local variants = valuesBySource.manual[key]
                if variants then
                    local v = nil
                    for _, vv in ipairs(variants) do
                        if vv.finisher == (item.finisher and true or false) then
                            v = vv
                            break
                        end
                    end
                    if not v then v = variants[1] end
                    if v then
                        local threshold = v.underThreshold or (v.value - DEFAULT_UNDER)
                        if sellPrice <= threshold then
                            table.insert(underrapCandidates, {
                                variant = v,
                                source = "manual",
                                variantCount = #variants,
                            })
                        end
                    end
                end
            end

            if #underrapCandidates == 0 then continue end

            -- ── Pick best deal (highest value) ──
            local best = underrapCandidates[1]
            for i = 2, #underrapCandidates do
                if underrapCandidates[i].variant.value > best.variant.value then
                    best = underrapCandidates[i]
                end
            end

            local realValue = best.variant.value
            local category  = best.variant.category
            local rarity    = best.variant.rarity
            local profit    = realValue - sellPrice
            local srcLabel  = best.source
            if #underrapCandidates > 1 then
                srcLabel = "both"
                sourceStats.both += 1
            else
                sourceStats[best.source] = (sourceStats[best.source] or 0) + 1
            end

            table.insert(results, string.format(
                "%s | Price: %s | Value: %s [%s] | Cat: %s | Rarity: %s%s%s",
                item.name, item.price, tostring(realValue), srcLabel, category, rarity,
                item.finisher and " | FINISHER" or "",
                " | <UNDERRAP>"
            ))

            underrapCount += 1

            lastUnderrapInfo = {
                item      = item.name,
                price     = tostring(item.price),
                realValue = tostring(realValue),
                seller    = username,
                category  = category,
                finisher  = item.finisher,
                profit    = tostring(profit),
                jobId     = currentJobId,
            }
            if lastJoinedLabels then
                lastJoinedLabels.item:SetText("📦 Item: " .. item.name .. (item.finisher and " ✨" or ""))
                lastJoinedLabels.seller:SetText("👤 Seller: " .. username)
                lastJoinedLabels.price:SetText("💰 Price: " .. tostring(item.price))
                lastJoinedLabels.value:SetText("💎 Value: " .. tostring(realValue))
                lastJoinedLabels.profit:SetText("📈 Profit: +" .. tostring(profit))
            end

            local scanPayload = {
                item_name  = item.name,
                price      = sellPrice or 0,
                real_value = realValue,
                seller     = username,
                display_name = getDisplayName(ownerId) or username,
                seller_id  = ownerId,
                sales      = item.sellerSales or -1,
                rap        = item.sellerRap or -1,
                finisher   = item.finisher and 1 or 0,
                category   = category,
                profit     = profit,
                job_id     = currentJobId,
                place_id   = PLACE_ID,
                loc_x      = boothX,
                loc_y      = boothY,
                loc_z      = boothZ,
                source     = best.source,   -- "auto" or "manual"
                slot       = slotIdx,
            }

            pendingSends += 1
            task.spawn(function()
                local sendResult = postScanToAPI(scanPayload)
                if sendResult == "ok" then sentOk += 1
                elseif sendResult == "duplicate" then sentDup += 1
                else sentFail += 1 end
                pendingSends -= 1
            end)
        end

        task.wait(0)
        table.insert(results, "")
    end

    local output = table.concat(results, "\n")
    if writefile then writefile("booth_scan_results.txt", output) end

    markServerScanned(currentJobId)

    local waitStart = os.clock()
    while pendingSends > 0 and os.clock() - waitStart < 15 do task.wait(0.1) end

    local desc = string.format(
        "%d booths, %d underrap\nBot: %d tersimpan, %d duplikat, %d gagal",
        boothCount, underrapCount, sentOk, sentDup, sentFail
    )
    if valuesBySource.auto and valuesBySource.manual then
        desc = desc .. string.format("\n(auto:%d, manual:%d, both:%d)",
            sourceStats.auto, sourceStats.manual, sourceStats.both)
    end

    Library:Notify({
        Title = "Scan Complete",
        Description = desc,
        Time = 5,
    })

    if autoHopEnabled then
        task.wait(0.5)
        doHop("Scan done, hopping")
    end
end

local function gatherSources()
    -- Returns (sourcesTable, didScan) — sources is { auto = ..., manual = ... }
    local sources = {}
    local didScan = false

    if scanMode == "auto" or scanMode == "both" then
        local values = loadBBValues()
        if next(values) then
            sources.auto = values
            didScan = true
        else
            Library:Notify({ Title = "Auto Scan", Description = "Failed to load bbvalues", Time = 3 })
        end
    end

    if scanMode == "manual" or scanMode == "both" then
        local values = loadManualValues()
        if next(values) then
            sources.manual = values
            didScan = true
        else
            if scanMode == "manual" then
                Library:Notify({ Title = "Auto Scan", Description = "Failed to load manual values", Time = 3 })
            end
        end
    end

    return sources, didScan
end

local function startAutoScan()
    stopAutoScan()
    autoScanThread = task.spawn(function()
        while scanAllBooths == nil do task.wait(0.1) end
        while autoScanEnabled do
            if isTeleporting then
                print("[auto] Teleporting, skipping scan")
                task.wait(2)
                continue
            end

            local currentJob = game.JobId

            if isServerScanned(currentJob) then
                print("[auto] Server " .. currentJob:sub(1, 8) .. " already scanned")
                if autoHopEnabled then
                    doHop("Already scanned")
                    if game.JobId == currentJob then
                        task.wait(10)
                    end
                else
                    task.wait(5)
                end
                continue
            end

            local sources, didScan = gatherSources()
            if didScan then
                scanAllBooths(sources)
            else
                task.wait(5)
            end

            if autoScanEnabled and not autoHopEnabled then
                task.wait(2)
            end
        end
    end)
end

-- ── GUI ───────────────────────────────────────────────────────────────────────

local Tabs = {
    Main   = Window:AddTab("Scanner",     "search"),
    Server = Window:AddTab("Servers",     "server"),
    UISett = Window:AddTab("UI Settings", "settings"),
}

local MainGroup = Tabs.Main:AddGroupbox({ Side = "Left", Name = "Scanner" })

MainGroup:AddLabel("Dual Source: Manual (Bot) + Auto (BBValues)")
MainGroup:AddDivider()

MainGroup:AddDropdown("ScanMode", {
    Values  = { "Auto (BBValues)", "Manual (Bot)", "Both" },
    Default = 1,
    Multi   = false,
    Text    = "Scan Mode",
    Tooltip = "Auto = bbvalues.uk, Manual = harga dari bot /add, Both = keduanya (union, best deal)",
    Callback = function(val)
        if val == "Auto (BBValues)" then
            scanMode = "auto"
        elseif val == "Manual (Bot)" then
            scanMode = "manual"
        else
            scanMode = "both"
        end
        Library:Notify({ Title = "Scan Mode", Description = "Mode: " .. val, Time = 3 })
    end,
})

MainGroup:AddDivider()

MainGroup:AddButton({
    Text = "🔄 Refresh Values",
    Func = function()
        task.spawn(function()
            Library:Notify({ Title = "Refresh", Description = "Fetching values...", Time = 2 })

            local bbCount = 0
            local manualCount = 0

            cachedBBValues = nil
            lastFetchTime = 0
            local bbVals = loadBBValues()
            if bbVals and next(bbVals) then
                for _, variants in pairs(bbVals) do
                    bbCount += #variants
                end
            end

            local manVals = loadManualValues()
            if manVals and next(manVals) then
                for _, variants in pairs(manVals) do
                    manualCount += #variants
                end
            end

            local currentJob = game.JobId
            if sharedScannedCache[currentJob] then
                sharedScannedCache[currentJob] = nil
            end

            Library:Notify({
                Title = "Refresh Complete",
                Description = string.format("BBValues: %d | Manual: %d", bbCount, manualCount),
                Time = 5,
            })
        end)
    end,
    Tooltip = "Force fetch ulang BBValues + Manual values (clear cache)",
})

MainGroup:AddDivider()

MainGroup:AddButton({
    Text = "Scan All Booths",
    Func = function()
        task.spawn(function()
            local sources, didScan = gatherSources()
            if didScan then
                scanAllBooths(sources)
            else
                Library:Notify({ Title = "Error", Description = "No values loaded", Time = 5 })
            end
        end)
    end,
    Tooltip = "Scan booths sesuai mode yang dipilih (Both = union, best deal)",
})

MainGroup:AddDivider()

MainGroup:AddToggle("AutoScan", {
    Default = true,
    Text = "Auto Scan",
    Tooltip = "Continuously scan booths",
    Callback = function(val)
        autoScanEnabled = val
        if val then
            startAutoScan()
        else
            stopAutoScan()
            Library:Notify({ Title = "Auto Scan", Description = "Stopped", Time = 3 })
        end
    end,
})

MainGroup:AddToggle("AutoHop", {
    Default = true,
    Text = "Auto Change Server",
    Tooltip = string.format("Hop to next server after scan (skip last %d)", HOP_SKIP_COUNT),
    Callback = function(val)
        autoHopEnabled = val
        if val and not autoScanEnabled then
            autoScanEnabled = true
            Toggles.AutoScan:SetValue(true)
            startAutoScan()
            Library:Notify({ Title = "Auto Hop", Description = "Auto Scan enabled automatically", Time = 3 })
        end
    end,
})

MainGroup:AddDivider()

-- ── LAST UNDERRAP INFO ──
local LastJoinedGroup = Tabs.Main:AddGroupbox({ Side = "Right", Name = "Last Underrap Found" })

local lastJoinedLabels = {
    item   = LastJoinedGroup:AddLabel("📦 Item: -"),
    seller = LastJoinedGroup:AddLabel("👤 Seller: -"),
    price  = LastJoinedGroup:AddLabel("💰 Price: -"),
    value  = LastJoinedGroup:AddLabel("💎 Value: -"),
    profit = LastJoinedGroup:AddLabel("📈 Profit: -"),
}

LastJoinedGroup:AddDivider()

LastJoinedGroup:AddButton({
    Text = "Join Last Underrap Server",
    Func = function()
        if not lastUnderrapInfo then
            Library:Notify({ Title = "Error", Description = "No underrap found yet", Time = 3 })
            return
        end
        local jobId = lastUnderrapInfo.jobId
        if jobId == game.JobId then
            Library:Notify({ Title = "Info", Description = "Already in this server", Time = 3 })
            return
        end
        Library:Notify({
            Title = "Joining...",
            Description = string.format("%s by %s", lastUnderrapInfo.item, lastUnderrapInfo.seller),
            Time = 3,
        })
        task.spawn(function()
            joinServer(jobId)
        end)
    end,
    Tooltip = "Teleport ke server underrap terakhir",
})

-- ── SERVERS TAB ──
local ServerGroup = Tabs.Server:AddGroupbox({ Side = "Left", Name = "Server List" })
local cachedServers = {}

ServerGroup:AddButton({
    Text = "Refresh Server List",
    Func = function()
        cachedServers = getServerList()
        if #cachedServers == 0 then
            Library:Notify({ Title = "Error", Description = "Failed to get server list", Time = 5 })
            return
        end
        local names = {}
        for i, s in ipairs(cachedServers) do
            table.insert(names, string.format("Server %d (%d/%d)", i, s.players, s.maxPlayers))
        end
        Options.ServerDropdown:SetValues(names)
        Library:Notify({ Title = "Server List", Description = #cachedServers .. " servers found", Time = 4 })
    end,
})

ServerGroup:AddDropdown("ServerDropdown", {
    Values  = { "Not refreshed" },
    Default = 1,
    Multi   = false,
    Text    = "Select Server",
})

ServerGroup:AddButton({
    Text = "Join Selected Server",
    Func = function()
        local selected = Options.ServerDropdown.Value
        for i, s in ipairs(cachedServers) do
            local name = string.format("Server %d (%d/%d)", i, s.players, s.maxPlayers)
            if name == selected then joinServer(s.jobId) return end
        end
        Library:Notify({ Title = "Error", Description = "Refresh server list first", Time = 4 })
    end,
})

ServerGroup:AddDivider()

ServerGroup:AddButton({
    Text = "Hop to Random Server",
    Func = function()
        Library:Notify({ Title = "Hopping...", Description = "Finding server...", Time = 3 })
        task.spawn(function()
            doHop("Manual hop")
        end)
    end,
    Tooltip = string.format("Skip last %d servers", HOP_SKIP_COUNT),
})

ServerGroup:AddButton({
    Text = "Reset Hop History",
    Func = function()
        hopHistory = {}
        saveHopHistory()
        Library:Notify({ Title = "Hop History", Description = "History cleared", Time = 3 })
    end,
})

-- ── UI SETTINGS ──
local MenuGroup = Tabs.UISett:AddGroupbox({ Side = "Left", Name = "Menu", IconName = "wrench" })

MenuGroup:AddToggle("KeybindMenuOpen", {
    Default  = Library.KeybindFrame.Visible,
    Text     = "Show Keybind Menu",
    Callback = function(val) Library.KeybindFrame.Visible = val end,
})

MenuGroup:AddButton("Unload", function() Library:Unload() end)

Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder("BoothScannerBBV")
SaveManager:SetFolder("BoothScannerBBV")
SaveManager:BuildConfigSection(Tabs.UISett)
ThemeManager:ApplyToTab(Tabs.UISett)

ThemeManager:ApplyThemeData({
    FontColor       = "f5f5f6",
    MainColor       = "111113",
    AccentColor     = "4ade80",
    BackgroundColor = "0c0c0e",
    OutlineColor    = "1c1c1f",
    BackgroundImage = "",
})

SaveManager:LoadAutoloadConfig()

-- ── INIT ──────────────────────────────────────────────────────────────────────

loadHopHistory()

if queue_on_teleport then
    pcall(function()
        local src = nil
        if readfile then
            local ok, content = pcall(readfile, "main.luau")
            if ok and content and content ~= "" then src = content end
        end
        if not src then
            src = 'loadstring(readfile("main.luau"))()'
        end
        queue_on_teleport(src)
        print("[init] Queued script for re-execution on teleport")
    end)
elseif syn and syn.queue_on_teleport then
    pcall(function()
        syn.queue_on_teleport('loadstring(readfile("main.luau"))()')
        print("[init] Queued script (syn) for re-execution on teleport")
    end)
end

if game.PlaceId ~= ROOT_PLACE_ID then
    Library:Notify({ Title = "Wrong Place", Description = "Teleporting to Plaza...", Time = 5 })
    task.wait(2)
    TeleportService:Teleport(ROOT_PLACE_ID, LocalPlayer)
    return
end

Library:Notify({ Title = "BBValues Scanner", Description = string.format("Loaded (min value: %d) — Auto Scan + Hop ON", MIN_VALUE), Time = 4 })

task.spawn(function()
    task.wait(1)
    autoHopEnabled  = Toggles.AutoHop.Value
    autoScanEnabled = Toggles.AutoScan.Value
    print("[init] AutoScan=" .. tostring(autoScanEnabled) .. " AutoHop=" .. tostring(autoHopEnabled))
    if autoScanEnabled then
        Library:Notify({ Title = "Auto Scan", Description = "Started automatically", Time = 3 })
        startAutoScan()
    end
end)
