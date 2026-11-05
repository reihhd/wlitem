-- main_bbvalues.luau
-- Blade Ball Booth Scanner — Dual Source: Manual (Bot) + Auto (BBValues)
-- Hanya scan item dengan value > 100
-- Made by Rei

local Players         = game:GetService("Players")
local LocalPlayer     = Players.LocalPlayer
local HttpService     = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

-- ── CONFIG ────────────────────────────────────────────────────────────────────
local ROOT_PLACE_ID = 16581637217
local PLACE_ID      = ROOT_PLACE_ID
local WEBHOOK_URL = "https://discord.com/api/webhooks/1510395545141907478/cN3zzPCevXKBL4nEBefV7Z6m_ufHSUYjlBHKyPK8sZGl2VufTkamnNpxL58DWvF5z7hs"
-- Server bot Omni (HTTPS). Ganti di satu tempat ini saja kalau domain berubah.
local API_BASE      = "https://api.om-ni.my.id"
local SCANS_URL     = API_BASE .. "/scans"
local HEARTBEAT_URL = API_BASE .. "/heartbeat"
local BBVALUES_URL  = API_BASE .. "/bbvalues.json" -- proxy via bot (bbvalues.uk down di luau)
local VALUES_URL    = API_BASE .. "/values.json"   -- manual values dari bot
local SCANNED_URL   = API_BASE .. "/scanned"       -- shared scanned servers (cross-account)
local MIN_VALUE      = 100 -- hanya scan item dengan value > ini
local DEFAULT_UNDER  = 10  -- default under deduction
local HOP_SKIP_COUNT = 20
local HOP_HISTORY_FILE = "hop_history.json"
-- ─────────────────────────────────────────────────────────────────────────────

local hopHistory = {}
local isTeleporting = false

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

-- Forward declaration
local httpGet

-- ── SHARED SCANNED SERVERS (via bot API — cross-account) ──────────────────────
local sharedScannedCache = {}
local lastScannedFetch = 0
local SCANNED_FETCH_INTERVAL = 10
local SCANNED_LOCAL_TTL = 300

local function fetchSharedScanned()
    if (os.time() - lastScannedFetch) < SCANNED_FETCH_INTERVAL then return end
    local ok2, body = pcall(function()
        return httpGet(SCANNED_URL .. ".json", {})
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
                if (now - ts) < SCANNED_LOCAL_TTL then merged[jid] = ts end
            end
            for jid, ts in pairs(data) do
                if type(ts) == "number" then
                    if not merged[jid] then merged[jid] = now end
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
        local json = HttpService:JSONEncode({ job_id = jobId, username = LocalPlayer.Name })
        local opts = {
            Url = SCANNED_URL, Method = "POST",
            Headers = { ["Content-Type"] = "application/json" }, Body = json,
        }
        if request then pcall(request, opts)
        elseif syn and syn.request then pcall(syn.request, opts)
        else pcall(function() HttpService:PostAsync(SCANNED_URL, json) end)
        end
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

-- Background refresh shared scanned list
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

-- httpGet dengan retry otomatis dan timeout handling
function httpGet(url, extraHeaders)
    local headers = {
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        ["Accept"] = "application/json",
    }
    if extraHeaders then
        for k, v in pairs(extraHeaders) do headers[k] = v end
    end
    -- Coba request / syn.request / GetAsync — return body atau nil
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

-- httpPost non-blocking: fire and forget in background thread
local function httpPostAsync(url, jsonBody)
    task.spawn(function()
        local opts = {
            Url = url, Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = jsonBody,
        }
        if request then pcall(request, opts)
        elseif syn and syn.request then pcall(syn.request, opts)
        else pcall(function() HttpService:PostAsync(url, jsonBody) end)
        end
    end)
end

local function parseNumber(str)
    if not str then return nil end
    local clean = tostring(str):gsub(",", ""):gsub("%s+", "")
    return tonumber(clean)
end

local function getUsername(userId)
    local ok, name = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
    return ok and name or tostring(userId)
end

local function getDisplayName(userId)
    local ok, info = pcall(function()
        local player = Players:GetPlayerByUserId(userId)
        if player then return player.DisplayName end
        return nil
    end)
    return ok and info or nil
end

local function sendWebhook(payload)
    httpPostAsync(WEBHOOK_URL, HttpService:JSONEncode(payload))
end

local function postScanToAPI(data)
    httpPostAsync(SCANS_URL, HttpService:JSONEncode(data))
end

local function sendHeartbeat()
    httpPostAsync(HEARTBEAT_URL, HttpService:JSONEncode({
        username = LocalPlayer.Name,
        job_id   = game.JobId,
    }))
end

-- Heartbeat loop: setiap 2 menit
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
local CACHE_TTL      = 300  -- 5 menit

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
    -- 1. In-memory cache masih fresh
    if cachedBBValues and (os.time() - lastFetchTime) < CACHE_TTL then
        return cachedBBValues
    end

    -- 2. Fetch dari API (retry singkat — jangan block lama)
    local MAX_RETRIES = 3
    local body = nil
    for attempt = 1, MAX_RETRIES do
        body = fetchBBValuesRaw()
        local data = parseBBValuesBody(body)
        if data and #data > 100 then
            saveBBValuesCache(body)
            local values, count = buildValuesLookup(data)
            if count > 0 then
                cachedBBValues = values
                lastFetchTime = os.time()
                return values
            end
        end
        if attempt < MAX_RETRIES then
            -- Delay pendek: 1s, 2s (lebih cepat dari 3s, 6s sebelumnya)
            task.wait(attempt)
        end
    end

    -- 3. Fallback: expired in-memory cache
    if cachedBBValues then
        local age = os.time() - lastFetchTime
        warn(string.format("[bbvalues] API failed, using expired cache (%dm old)", math.floor(age / 60)))
        Library:Notify({ Title = "BBValues", Description = string.format("API down, using cache (%dm old)", math.floor(age / 60)), Time = 5 })
        return cachedBBValues
    end

    -- 4. Fallback: file cache
    local fileData = loadBBValuesFromFile()
    if fileData then
        local values, count = buildValuesLookup(fileData)
        if count > 0 then
            cachedBBValues = values
            lastFetchTime = os.time() - CACHE_TTL + 60
            warn("[bbvalues] Using file cache")
            Library:Notify({ Title = "BBValues", Description = "API down, using saved cache", Time = 5 })
            return values
        end
    end

    warn("[bbvalues] All attempts failed, no cache available")
    return {}
end

-- ── CATEGORY EXCEPTION TABLE ──────────────────────────────────────────────────
local ASSET_CATEGORY_MAP = {
    -- Crimson Kagune
    ["16266665378"]        = "Sword",
    ["103991473928751"]    = "Emote",
    ["122220220272317"]    = "Explosion",
    -- Starfall
    ["129131763936203"]    = "Explosion",
    ["17757365730"]        = "Sword",
    -- Dual Gothic Heartpiercer Blade
    ["121538626129831"]    = "Sword",
    ["122139166298284"]    = "Emote",
    -- Nebula Blade
    ["15965812017"]        = "Sword",
    ["15964013112"]        = "Explosion",
    -- Radiant Duckling Lance
    ["135913442813047"]    = "Emote",
    ["77190288652210"]     = "Sword",
    -- Primordial Lance
    ["72309796878320"]     = "Emote",
    ["98895700264373"]     = "Sword",
    -- Night Raver
    ["114649402355251"]    = "Explosion",
    ["136298174298208"]    = "Emote",
    ["126034810019036"]    = "Sword",
    -- Dual Hidden Beast Blade
    ["77798050960530"]     = "Sword",
    ["94990619459773"]     = "Emote",
    -- Higanbana Katana
    ["91449061436707"]     = "Emote",
    ["135684393446468"]    = "Sword",
    -- Strawberry Cake Lance
    ["72687727611270"]     = "Sword",
    ["132530935111167"]    = "Emote",
    -- Ball Drop
    ["15862986776"]        = "Emote",
    ["78573433974758"]     = "Explosion",
    -- Dual Blue Bunny Katana
    ["135381650702325"]    = "Sword",
    ["97054245713645"]     = "Emote",
}

local ASSET_MAP_FILE = "asset_map.json"
local function _lastDigits(v)
    v = tostring(v or "")
    return v:match("(%d+)$")
end
local function loadAssetMapFile()
    if not readfile then return end
    local ok, content = pcall(readfile, ASSET_MAP_FILE)
    if not ok or not content or content == "" then return end
    local okD, data = pcall(function() return HttpService:JSONDecode(content) end)
    if not okD or type(data) ~= "table" then
        warn("[scanner] asset_map.json invalid JSON, ignored")
        return
    end
    local added = 0
    for k, v in pairs(data) do
        local id, cat
        if type(v) == "string" then
            id, cat = _lastDigits(k), v
        elseif type(v) == "table" then
            id  = _lastDigits(v.asset_id or v.assetId or v.id)
            cat = v.category or v.cat or v.type
        end
        if id and cat and cat ~= "" then
            ASSET_CATEGORY_MAP[id] = cat
            added += 1
        end
    end
    if added > 0 then print(string.format("[scanner] asset_map.json: +%d asset IDs", added)) end
end
pcall(loadAssetMapFile)

local _unknownSeen = {}
local _unknownLines = {}
local function logUnknownAsset(itemName, assetId, guessedCat)
    local id = _lastDigits(assetId)
    if not id or ASSET_CATEGORY_MAP[id] or _unknownSeen[id] then return end
    _unknownSeen[id] = true
    table.insert(_unknownLines, string.format("%s | %s | %s", tostring(itemName), id, tostring(guessedCat or "?")))
    if writefile then
        pcall(writefile, "unknown_assets.txt", table.concat(_unknownLines, "\n") .. "\n")
    end
end

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
    if not sellPrice then return nil, false end

    -- Step 0a: Asset ID (paling akurat)
    local assetVariant, assetUnderrap = resolveByAssetId(assetId, variants, sellPrice)
    if assetVariant then return assetVariant, assetUnderrap end

    -- Step 0b: Exception table (price-based)
    local excVariant, excUnderrap = resolveException(itemName, variants, sellPrice)
    if excVariant then return excVariant, excUnderrap end

    -- Step 1: Filter berdasarkan finisher status
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

    -- Step 2: Satu variant — langsung cek
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

    -- Step 3: Multiple variant — proximity matching
    local categoryGroups = {}
    for _, v in ipairs(pool) do
        local cat = v.category or "unknown"
        if not categoryGroups[cat] then categoryGroups[cat] = {} end
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

    -- Step 4: Cek underrap terhadap variant termurah
    local cheapest = pool[1]
    for i = 2, #pool do
        if pool[i].value < cheapest.value then cheapest = pool[i] end
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
    local body = httpGet(VALUES_URL, {})
    if not body then warn("[manual] httpGet returned nil") return {} end
    if body:sub(1, 1) ~= "{" then warn("[manual] Response is not JSON") return {} end
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok then warn("[manual] JSONDecode failed") return {} end
    if not data or not data.items then warn("[manual] No 'items' field") return {} end
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

-- ── BOOTH SCAN ────────────────────────────────────────────────────────────────

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

-- Tunggu ScrollingList muncul dengan timeout
local function waitForScrollingList(timeoutSec)
    timeoutSec = timeoutSec or 1.5
    local t0 = tick()
    while (tick() - t0) < timeoutSec do
        local list = getScrollingList()
        if list and #list:GetChildren() > 0 then return list end
        task.wait(0.05)
    end
    return getScrollingList()
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
                if img and img ~= "" then assetId = img end
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

-- Seed math.random sekali pakai waktu + tick agar benar-benar beda tiap session
math.randomseed(os.time() + math.floor(tick() * 1000) % 100000)
-- Buang beberapa angka pertama (LCG warm-up)
for _ = 1, 5 do math.random() end

-- Ambil semua halaman server dari Roblox API (pagination via cursor)
-- Roblox membatasi 100 server per halaman; game besar bisa punya 300-500+ server
local function getServerList()
    local servers = {}
    local cursor = nil
    local maxPages = 5 -- ambil max 5 halaman = 500 server

    for page = 1, maxPages do
        local url = string.format(
            "https://games.roblox.com/v1/games/%d/servers/Public?limit=100&sortOrder=Asc",
            PLACE_ID
        )
        if cursor then
            url = url .. "&cursor=" .. HttpService:UrlEncode(cursor)
        end

        local body = httpGet(url)
        if not body then break end

        local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
        if not ok or not data or not data.data then break end

        for _, s in ipairs(data.data) do
            -- Hanya ambil server yang tidak penuh (ada slot kosong)
            if s.id and s.playing and s.maxPlayers and s.playing < s.maxPlayers then
                table.insert(servers, {
                    jobId      = s.id,
                    players    = s.playing,
                    maxPlayers = s.maxPlayers,
                })
            end
        end

        -- nextPageCursor nil/false = tidak ada halaman lagi
        if not data.nextPageCursor or data.nextPageCursor == "" then break end
        cursor = data.nextPageCursor

        -- Jangan spam API — tunggu sebentar antar halaman
        if page < maxPages then task.wait(0.3) end
    end

    print(string.format("[hop] Got %d servers total", #servers))
    return servers
end

-- Flag yang di-set TeleportInitFailed kalau teleport gagal di sisi Roblox
local lastTeleportFailed    = false
local lastTeleportFailMsg   = nil

-- Listen sekali: kalau Roblox gagal init teleport ("failed to connect to
-- experience", "please try again", server penuh/expired, rate limit, dll)
-- event ini yang fire — bukan error dari pemanggilan TeleportToPlaceInstance.
do
    local ok = pcall(function()
        TeleportService.TeleportInitFailed:Connect(function(player, result, message)
            if player ~= LocalPlayer then return end
            lastTeleportFailed  = true
            lastTeleportFailMsg = string.format("%s: %s", tostring(result), tostring(message))
            warn("[hop] TeleportInitFailed -> " .. lastTeleportFailMsg)
        end)
    end)
    if not ok then
        warn("[hop] Gagal connect TeleportInitFailed (executor block?)")
    end
end

-- return: ok(bool), errMsg(string|nil)
-- ok=true berarti panggilan teleport diterima Roblox (belum tentu sampai) —
-- doHop tetap cek game.JobId + lastTeleportFailed untuk konfirmasi.
local function joinServer(jobId)
    addToHistory(game.JobId)
    lastTeleportFailed  = false
    lastTeleportFailMsg = nil

    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(PLACE_ID, jobId, LocalPlayer)
    end)
    if not ok then
        warn("[hop] TeleportToPlaceInstance error: " .. tostring(err))
        return false, tostring(err)
    end
    return true, nil
end

-- Fisher-Yates shuffle dengan seed yang sudah di-randomize
local function shuffleInPlace(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

local function pickNextServer()
    local servers = getServerList()
    if #servers == 0 then
        warn("[hop] Server list kosong")
        return nil
    end

    -- Shuffle agar urutan benar-benar acak (tidak tergantung urutan API)
    shuffleInPlace(servers)

    local currentJob = game.JobId

    -- Pass 1: Belum di-scan dan tidak di history (prioritas tertinggi)
    for _, s in ipairs(servers) do
        if s.jobId ~= currentJob
            and not isInHistory(s.jobId)
            and not isServerScanned(s.jobId)
        then
            print(string.format("[hop] Pick (clean): %s", s.jobId:sub(1, 8)))
            return s.jobId
        end
    end

    -- Pass 2: Belum di-scan saja (boleh ada di history lama)
    for _, s in ipairs(servers) do
        if s.jobId ~= currentJob and not isServerScanned(s.jobId) then
            print(string.format("[hop] Pick (not-scanned): %s", s.jobId:sub(1, 8)))
            return s.jobId
        end
    end

    -- Pass 3: Semua sudah di-scan — reset scanned cache dan ambil yang tidak di history
    warn("[hop] Semua server sudah di-scan, reset scanned cache")
    sharedScannedCache = {}
    lastScannedFetch = 0

    for _, s in ipairs(servers) do
        if s.jobId ~= currentJob and not isInHistory(s.jobId) then
            print(string.format("[hop] Pick (reset-scanned): %s", s.jobId:sub(1, 8)))
            return s.jobId
        end
    end

    -- Pass 4: Semua di history — reset history juga
    warn("[hop] Semua server di history, reset history")
    hopHistory = {}
    saveHopHistory()

    for _, s in ipairs(servers) do
        if s.jobId ~= currentJob then
            print(string.format("[hop] Pick (reset-all): %s", s.jobId:sub(1, 8)))
            return s.jobId
        end
    end

    return nil
end

local function doHop(reason)
    local currentJob = game.JobId
    for attempt = 1, 5 do
        Library:Notify({ Title = "Auto Hop", Description = string.format("%s (%d/5)", reason, attempt), Time = 2 })
        local nextServer = pickNextServer()
        if not nextServer then
            warn("[hop] Tidak ada server ditemukan, attempt " .. attempt)
            task.wait(3)
            continue
        end

        -- Pastikan kita tidak hop ke server yang sama
        if nextServer == currentJob then
            warn("[hop] pickNextServer returned current server, skip")
            task.wait(1)
            continue
        end

        isTeleporting = true
        print(string.format("[hop] Teleporting to %s (attempt %d)", nextServer:sub(1, 8), attempt))

        local sent, sendErr = joinServer(nextServer)
        if not sent then
            -- Panggilan teleport ditolak langsung (rate limit / argumen salah).
            -- Jangan hajar lagi cepat-cepat — backoff dulu.
            isTeleporting = false
            addToHistory(nextServer)
            warn("[hop] joinServer ditolak: " .. tostring(sendErr))
            task.wait(math.min(3 + attempt * 2, 10))
            continue
        end

        -- Tunggu teleport. Kalau TeleportInitFailed fire di tengah, stop nunggu
        -- lebih awal — server penuh/expired, percuma tunggu sampai habis.
        local waited = 0
        while waited < 10 do
            task.wait(0.5)
            waited += 0.5
            if game.JobId ~= currentJob then break end
            if lastTeleportFailed then break end
        end

        if game.JobId ~= currentJob then
            print("[hop] Teleport berhasil!")
            return true
        end

        isTeleporting = false
        addToHistory(nextServer)

        if lastTeleportFailed then
            -- "failed to connect to experience" / "please try again":
            -- server itu busuk. Skip, backoff biar nggak kena rate limit Roblox.
            warn(string.format("[hop] Teleport gagal (init failed) attempt %d: %s",
                attempt, tostring(lastTeleportFailMsg)))
            task.wait(math.min(3 + attempt * 2, 10))
        else
            -- Tidak ada init-failed tapi JobId nggak berubah — teleport nyangkut.
            warn("[hop] Teleport gagal (timeout) attempt " .. attempt)
            task.wait(2)
        end
    end
    isTeleporting = false
    Library:Notify({ Title = "Auto Hop", Description = "All attempts failed", Time = 5 })
    return false
end

-- ── SCAN ALL BOOTHS ───────────────────────────────────────────────────────────

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

local function startAutoScan()
    stopAutoScan()
    autoScanThread = task.spawn(function()
        while scanAllBooths == nil do task.wait(0.1) end
        while autoScanEnabled do
            if isTeleporting then
                task.wait(2)
                continue
            end

            local currentJob = game.JobId

            if isServerScanned(currentJob) then
                print("[auto] Server " .. currentJob:sub(1, 8) .. " already scanned")
                if autoHopEnabled then
                    doHop("Already scanned")
                    if game.JobId == currentJob then task.wait(10) end
                else
                    task.wait(5)
                end
                continue
            end

            local didScan = false

            if scanMode == "auto" or scanMode == "both" then
                local values = loadBBValues()
                if next(values) then
                    scanAllBooths(values, "auto")
                    didScan = true
                else
                    Library:Notify({ Title = "Auto Scan", Description = "Failed to load bbvalues", Time = 3 })
                end
            end

            if scanMode == "manual" or scanMode == "both" then
                local values = loadManualValues()
                if next(values) then
                    scanAllBooths(values, "manual")
                    didScan = true
                else
                    if scanMode == "manual" then
                        Library:Notify({ Title = "Auto Scan", Description = "Failed to load manual values", Time = 3 })
                    end
                end
            end

            if not didScan then task.wait(5) end
            if autoScanEnabled and not autoHopEnabled then task.wait(2) end
        end
    end)
end

scanAllBooths = function(values, source)
    source = source or "auto"

    if isTeleporting then
        print("[scanner] Skipping — teleporting")
        return
    end

    local currentJobId = game.JobId

    if isServerScanned(currentJobId) then
        print("[scanner] Server already scanned, skipping")
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
    local joinLink = string.format(
        "https://www.roblox.com/games/start?placeId=%s&gameInstanceId=%s",
        tostring(PLACE_ID), currentJobId
    )
    local deepLink = string.format(
        "roblox://placeId=%s&gameInstanceId=%s",
        tostring(PLACE_ID), currentJobId
    )

    -- ── Kumpulkan semua booth dulu ──
    local boothList = {}
    for _, booth in ipairs(stands:GetChildren()) do
        local ownerId = booth:GetAttribute("Owner")
        if ownerId ~= nil then
            table.insert(boothList, { booth = booth, ownerId = ownerId })
        end
    end

    -- ── Tutup GUI booth yang mungkin masih terbuka dari sebelumnya ──
    local function closeBoothGui()
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if not pg then return end
        local boothGui = pg:FindFirstChild("Booth")
        if boothGui then
            -- Coba destroy/hide GUI booth agar tidak carry over ke booth berikutnya
            pcall(function()
                local pb = boothGui:FindFirstChild("PlayersBooth")
                if pb then pb.Enabled = false end
            end)
            pcall(function() boothGui.Enabled = false end)
        end
    end

    -- Pastikan GUI bersih sebelum mulai
    closeBoothGui()
    task.wait(0.1)

    -- ── Scan tiap booth satu per satu (open → wait → scan → close → next) ──
    for _, entry in ipairs(boothList) do
        local booth    = entry.booth
        local ownerId  = entry.ownerId
        boothCount += 1

        -- Ambil posisi booth
        local boothX, boothY, boothZ = 0, 0, 0
        do
            local pos
            local okPivot = pcall(function() pos = booth:GetPivot().Position end)
            if (not okPivot or not pos) then
                local root = booth:FindFirstChild("Root")
                if root and root:IsA("BasePart") then pos = root.Position end
                if not pos and root then
                    local anyPart = root:FindFirstChildWhichIsA("BasePart", true)
                    if anyPart then pos = anyPart.Position end
                end
            end
            if pos then
                boothX = math.floor(pos.X * 100 + 0.5) / 100
                boothY = math.floor(pos.Y * 100 + 0.5) / 100
                boothZ = math.floor(pos.Z * 100 + 0.5) / 100
            end
        end

        -- Buka prompt booth ini, tunggu ScrollingList terisi
        do
            local root = booth:FindFirstChild("Root")
            if root then
                local holder = root:FindFirstChild("ProximityPromptHolder")
                if holder then
                    local prompt = holder:FindFirstChild("BoothProximityPrompt")
                    if prompt then
                        pcall(firePrompt, prompt)
                        waitForScrollingList(1.5)
                    end
                end
            end
        end

        local items    = scanCurrentBooth()

        -- Tutup GUI booth ini sebelum lanjut ke booth berikutnya
        closeBoothGui()
        task.wait(0.05)
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

        for _, item in ipairs(items) do
            item.sellerSales = sellerSales
            item.sellerRap   = sellerRap
            local key       = string.lower(item.name)
            local variants  = values[key]
            if not variants then continue end

            local sellPrice = parseNumber(item.price)
            local variantCount = #variants
            local valueData, isUnderrap

            if source == "manual" then
                if not sellPrice then continue end
                valueData = nil
                for _, v in ipairs(variants) do
                    if v.finisher == (item.finisher and true or false) then
                        valueData = v
                        break
                    end
                end
                if not valueData then valueData = variants[1] end
                local threshold = valueData.underThreshold or (valueData.value - DEFAULT_UNDER)
                isUnderrap = sellPrice <= threshold
            else
                valueData, isUnderrap = analyzeItem(item.name, variants, item.finisher, sellPrice, item.assetId)
            end
            if not valueData then continue end

            local realValue = valueData.value
            local category  = valueData.category
            local rarity    = valueData.rarity

            if variantCount > 1 and item.assetId and item.assetId ~= "" then
                logUnknownAsset(item.name, item.assetId, category)
            end

            table.insert(results, string.format(
                "%s | Price: %s | Value: %s | Cat: %s | Rarity: %s%s%s%s",
                item.name, item.price, tostring(realValue), category, rarity,
                item.finisher and " | FINISHER" or "",
                variantCount > 1 and string.format(" | %d variants", variantCount) or "",
                isUnderrap and " | <UNDERRAP>" or ""
            ))

            if isUnderrap then
                underrapCount += 1
                local profit = realValue - sellPrice
                local pctOff = math.floor((1 - sellPrice / realValue) * 100)
                local variantNote = ""
                if variantCount > 1 then
                    local cats = {}
                    for _, v in ipairs(variants) do
                        local label = v.category .. (v.finisher and " Finisher" or "")
                        if not table.find(cats, label) then table.insert(cats, label) end
                    end
                    variantNote = string.format("\n%d variants exist: %s\nMatched: **%s%s** (value %s)",
                        variantCount, table.concat(cats, ", "),
                        category, valueData.finisher and " Finisher" or "",
                        tostring(realValue))
                end
                local itemImage = string.format("https://bbvalues.uk/images/items/%s.webp", valueData.itemId or "")

                -- Kirim webhook + API secara async (tidak block scanning)
                local webhookPayload = {
                    embeds = {{
                        title = "Underrap Found",
                        description = string.format("**%s** selling **%d%%** below value!%s", item.name, pctOff, variantNote),
                        color = 0x00FF88,
                        thumbnail = { url = itemImage },
                        fields = {
                            { name = "Item",       value = item.name,                                    inline = true },
                            { name = "Price",      value = string.format("`%s`", tostring(item.price)),  inline = true },
                            { name = "Value",      value = string.format("`%s`", tostring(realValue)),   inline = true },
                            { name = "Rarity",     value = rarity,                                       inline = true },
                            { name = "Profit",     value = string.format("`+%s`", tostring(profit)),     inline = true },
                            { name = "Category",   value = category .. (variantCount > 1 and string.format(" (%d variants)", variantCount) or ""), inline = true },
                            { name = "Finisher",   value = item.finisher and "Yes" or "No",              inline = true },
                            { name = "Status",     value = valueData.status,                             inline = true },
                            { name = "Seller",     value = string.format("[%s](https://www.roblox.com/users/%s/profile)", username, tostring(ownerId)), inline = true },
                            { name = "Join Server", value = string.format("[Click to Join](%s)", joinLink), inline = true },
                            { name = "Join Script", value = string.format(
                                "```lua\ngame:GetService(\"TeleportService\"):TeleportToPlaceInstance(%s, \"%s\", game.Players.LocalPlayer)\n```",
                                tostring(PLACE_ID), currentJobId
                            ), inline = false },
                            { name = "Join (Without Executor)", value = string.format(
                                "Copy and paste into browser address bar:\n```\n%s\n```", deepLink
                            ), inline = false },
                        },
                        footer = { text = "imaginemeandyou | by rei" },
                        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                    }},
                }
                sendWebhook(webhookPayload) -- async via httpPostAsync

                local scanPayload = {
                    item_name    = item.name,
                    price        = sellPrice or 0,
                    real_value   = realValue,
                    seller       = username,
                    display_name = getDisplayName(ownerId) or username,
                    seller_id    = ownerId,
                    sales        = item.sellerSales or -1,
                    rap          = item.sellerRap or -1,
                    finisher     = item.finisher and 1 or 0,
                    category     = category,
                    profit       = profit,
                    job_id       = currentJobId,
                    place_id     = PLACE_ID,
                    loc_x        = boothX,
                    loc_y        = boothY,
                    loc_z        = boothZ,
                    source       = source,
                }
                postScanToAPI(scanPayload) -- async via httpPostAsync

                -- Update GUI
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
            end
        end

    end

    local output = table.concat(results, "\n")
    if writefile then writefile("booth_scan_results.txt", output) end

    markServerScanned(currentJobId)

    Library:Notify({
        Title = "Scan Complete",
        Description = string.format("%d booths, %d underrap", boothCount, underrapCount),
        Time = 5,
    })

    if autoHopEnabled then
        task.wait(0.5)
        doHop("Scan done, hopping")
    end
end

-- ── GUI ───────────────────────────────────────────────────────────────────────

local Tabs = {
    Main   = Window:AddTab("Scanner",     "search"),
    Server = Window:AddTab("Servers",     "server"),
    UISett = Window:AddTab("UI Settings", "settings"),
}

-- ── SCANNER TAB ──
local MainGroup = Tabs.Main:AddGroupbox({ Side = "Left", Name = "Scanner" })

MainGroup:AddLabel("Dual Source: Manual (Bot) + Auto (BBValues)")
MainGroup:AddDivider()

MainGroup:AddDropdown("ScanMode", {
    Values  = { "Auto (BBValues)", "Manual (Bot)", "Both" },
    Default = 1,
    Multi   = false,
    Text    = "Scan Mode",
    Tooltip = "Auto = bbvalues.uk, Manual = harga dari bot /add, Both = keduanya",
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
            -- Force refresh BBValues
            cachedBBValues = nil
            lastFetchTime = 0
            local bbVals = loadBBValues()
            if bbVals and next(bbVals) then
                for _, variants in pairs(bbVals) do bbCount += #variants end
            end
            -- Force refresh Manual
            local manVals = loadManualValues()
            if manVals and next(manVals) then
                for _, variants in pairs(manVals) do manualCount += #variants end
            end
            -- Allow re-scan current server
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
            local didScan = false
            if scanMode == "auto" or scanMode == "both" then
                local values = loadBBValues()
                if next(values) then
                    scanAllBooths(values, "auto")
                    didScan = true
                else
                    Library:Notify({ Title = "Error", Description = "Failed to load bbvalues", Time = 5 })
                end
            end
            if scanMode == "manual" or scanMode == "both" then
                local values = loadManualValues()
                if next(values) then
                    scanAllBooths(values, "manual")
                    didScan = true
                else
                    Library:Notify({ Title = "Error", Description = "Failed to load manual values", Time = 5 })
                end
            end
            if not didScan then
                Library:Notify({ Title = "Error", Description = "No values loaded", Time = 5 })
            end
        end)
    end,
    Tooltip = "Scan booths sesuai mode yang dipilih",
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
        task.spawn(function() joinServer(jobId) end)
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
        task.spawn(function() doHop("Manual hop") end)
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

-- Auto re-execute setelah teleport
if queue_on_teleport then
    pcall(function()
        local src = nil
        if readfile then
            local ok, content = pcall(readfile, "main.luau")
            if ok and content and content ~= "" then src = content end
        end
        if not src then src = 'loadstring(readfile("main.luau"))()' end
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

Library:Notify({
    Title = "BBValues Scanner",
    Description = string.format("Loaded (min value: %d) — Auto Scan + Hop ON", MIN_VALUE),
    Time = 4,
})

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
