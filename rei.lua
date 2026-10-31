-- main.luau
-- Blade Ball Booth Scanner — Headless (No GUI)
-- Dual Source: Manual (Bot) + Auto (BBValues)
-- Auto Scan + Auto Hop — langsung aktif
-- Made by Rei

local Players         = game:GetService("Players")
local LocalPlayer     = Players.LocalPlayer
local HttpService     = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local RunService      = game:GetService("RunService")

-- ── CONFIG ────────────────────────────────────────────────────────────────────
local ROOT_PLACE_ID = 16581637217
local PLACE_ID      = ROOT_PLACE_ID
local WEBHOOK_URL   = "https://discord.com/api/webhooks/1510395545141907478/cN3zzPCevXKBL4nEBefV7Z6m_ufHSUYjlBHKyPK8sZGl2VufTkamnNpxL58DWvF5z7hs"
local SCANS_URL     = "http://hyper.ypnode.my.id:10750/scans"
local HEARTBEAT_URL = "http://hyper.ypnode.my.id:10750/heartbeat"
local VALUES_URL    = "http://hyper.ypnode.my.id:10750/values.json"
local MIN_VALUE      = 100
local DEFAULT_UNDER  = 10
local HOP_SKIP_COUNT = 20
local SCAN_MODE      = "both" -- "auto", "manual", "both"

-- File persistence
local HOP_HISTORY_FILE     = "hop_history.json"
local SCANNED_SERVERS_FILE = "scanned_servers.json"
local BBVALUES_CACHE_FILE  = "bbvalues_cache.json"

-- Tuning — scan secepat mungkin
local BOOTH_WAIT       = 0     -- tanpa delay setelah fire prompt
local SCAN_COOLDOWN    = 0     -- langsung hop setelah scan selesai
local HOP_TELEPORT_WAIT = 5    -- wait setelah teleport attempt
local HEARTBEAT_INTERVAL = 120 -- kirim heartbeat tiap 2 menit
local CACHE_TTL          = 300 -- bbvalues cache 5 menit
local SCANNED_EXPIRE     = 300 -- server dianggap "sudah scan" selama 5 menit
-- ─────────────────────────────────────────────────────────────────────────────

-- ── STATE ─────────────────────────────────────────────────────────────────────
local hopHistory = {}
local scannedServers = {}
local isTeleporting = false

-- BBValues cache
local cachedBBValues = nil
local lastFetchTime  = 0

-- Player info cache (avoid repeated API calls)
local usernameCache = {}

-- ── UTILITY: FILE I/O ────────────────────────────────────────────────────────

local function readJsonFile(file)
    if not readfile then return nil end
    local ok, content = pcall(readfile, file)
    if not ok or not content or content == "" then return nil end
    local ok2, data = pcall(function() return HttpService:JSONDecode(content) end)
    return ok2 and type(data) == "table" and data or nil
end

local function writeJsonFile(file, data)
    if writefile then
        pcall(writefile, file, HttpService:JSONEncode(data))
    end
end

-- ── HOP HISTORY ───────────────────────────────────────────────────────────────

local function loadHopHistory()
    hopHistory = readJsonFile(HOP_HISTORY_FILE) or {}
end

local function saveHopHistory()
    writeJsonFile(HOP_HISTORY_FILE, hopHistory)
end

local function addToHistory(jobId)
    hopHistory[#hopHistory + 1] = jobId
    while #hopHistory > HOP_SKIP_COUNT do table.remove(hopHistory, 1) end
    saveHopHistory()
end

local function isInHistory(jobId)
    for _, id in ipairs(hopHistory) do
        if id == jobId then return true end
    end
    return false
end

-- ── SCANNED SERVERS ───────────────────────────────────────────────────────────

local function loadScannedServers()
    scannedServers = readJsonFile(SCANNED_SERVERS_FILE) or {}
end

local function saveScannedServers()
    writeJsonFile(SCANNED_SERVERS_FILE, scannedServers)
end

local function markServerScanned(jobId)
    local now = os.time()
    scannedServers[jobId] = now
    local cleaned = {}
    for id, t in pairs(scannedServers) do
        if now - t < SCANNED_EXPIRE then cleaned[id] = t end
    end
    scannedServers = cleaned
    saveScannedServers()
end

local function isServerScanned(jobId)
    local t = scannedServers[jobId]
    if not t then return false end
    if os.time() - t >= SCANNED_EXPIRE then
        scannedServers[jobId] = nil
        return false
    end
    return true
end

-- ── HTTP ──────────────────────────────────────────────────────────────────────

local function httpRequest(url, method, body, extraHeaders)
    local headers = {
        ["User-Agent"] = "Mozilla/5.0",
        ["Accept"] = "application/json",
    }
    if extraHeaders then
        for k, v in pairs(extraHeaders) do headers[k] = v end
    end
    if body then
        headers["Content-Type"] = "application/json"
    end
    local opts = { Url = url, Method = method or "GET", Headers = headers, Body = body }
    if request then
        local ok, res = pcall(request, opts)
        if ok and res then return res.Body end
    end
    if syn and syn.request then
        local ok, res = pcall(syn.request, opts)
        if ok and res then return res.Body end
    end
    -- Fallback HttpService
    if method == "GET" or not method then
        local ok, res = pcall(function() return HttpService:GetAsync(url) end)
        return ok and res or nil
    else
        local ok, res = pcall(function() return HttpService:PostAsync(url, body or "") end)
        return ok and res or nil
    end
end

local function httpGet(url, extraHeaders)
    return httpRequest(url, "GET", nil, extraHeaders)
end

local function httpPost(url, data)
    httpRequest(url, "POST", HttpService:JSONEncode(data))
end

-- ── API CALLS (fire-and-forget via task.spawn) ────────────────────────────────

local function sendWebhook(payload)
    pcall(httpPost, WEBHOOK_URL, payload)
end

local function postScanToAPI(data)
    pcall(httpPost, SCANS_URL, data)
end

local function sendHeartbeat()
    pcall(httpPost, HEARTBEAT_URL, {
        username = LocalPlayer.Name,
        job_id   = game.JobId,
    })
end

-- ── PLAYER INFO (cached) ─────────────────────────────────────────────────────

local function getUsername(userId)
    if usernameCache[userId] then return usernameCache[userId] end
    local ok, name = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
    local result = ok and name or tostring(userId)
    usernameCache[userId] = result
    return result
end

local function getDisplayName(userId)
    local player = Players:GetPlayerByUserId(userId)
    return player and player.DisplayName or nil
end

local function parseNumber(str)
    if not str then return nil end
    return tonumber(tostring(str):gsub(",", ""):gsub("%s+", ""))
end

-- ── BBVALUES.UK API ───────────────────────────────────────────────────────────

local function parseBBValuesBody(body)
    if not body or body == "" or body:sub(1, 1) ~= "[" then return nil end
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    return (ok and type(data) == "table") and data or nil
end

local function buildValuesLookup(data)
    local values = {}
    local count = 0
    for _, item in ipairs(data) do
        local name, value = item.n, item.p
        if name and value and value > MIN_VALUE then
            local key = string.lower(name)
            local entry = {
                value    = value,
                category = item.c or "unknown",
                rarity   = item.r or "NORMAL",
                status   = item.st or "stable",
                finisher = (item.s == "Finisher"),
                source   = item.s or "None",
            }
            if not values[key] then
                values[key] = { entry }
            else
                values[key][#values[key] + 1] = entry
            end
            count += 1
        end
    end
    print("[bbvalues] " .. count .. " items loaded")
    return values, count
end

local function loadBBValues()
    -- 1. In-memory cache fresh
    if cachedBBValues and (os.time() - lastFetchTime) < CACHE_TTL then
        return cachedBBValues
    end

    -- 2. Fetch dari API (retry 3x)
    for attempt = 1, 3 do
        local body = httpGet("https://bbvalues.uk/api/items", {
            ["x-bbv-handshake"] = "v1-secure-request",
            ["Referer"] = "https://bbvalues.uk/values/",
        })
        local data = parseBBValuesBody(body)
        if data and #data > 100 then
            if writefile then pcall(writefile, BBVALUES_CACHE_FILE, body) end
            local values, count = buildValuesLookup(data)
            if count > 0 then
                cachedBBValues = values
                lastFetchTime = os.time()
                return values
            end
        end
        if attempt < 3 then task.wait(attempt * 3) end
    end

    -- 3. Expired in-memory cache
    if cachedBBValues then
        warn("[bbvalues] API failed, using expired cache")
        return cachedBBValues
    end

    -- 4. File cache
    if readfile then
        local ok, content = pcall(readfile, BBVALUES_CACHE_FILE)
        if ok and content then
            local fileData = parseBBValuesBody(content)
            if fileData and #fileData > 100 then
                local values, count = buildValuesLookup(fileData)
                if count > 0 then
                    cachedBBValues = values
                    lastFetchTime = os.time() - CACHE_TTL + 60
                    warn("[bbvalues] Using file cache")
                    return values
                end
            end
        end
    end

    warn("[bbvalues] All attempts failed")
    return {}
end

-- ── MANUAL VALUES (dari Bot) ──────────────────────────────────────────────────

local function loadManualValues()
    local body = httpGet(VALUES_URL, {})
    if not body or body:sub(1, 1) ~= "{" then return {} end
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok or not data or not data.items then return {} end

    local values = {}
    local count = 0
    for k, v in pairs(data.items) do
        if (not v.disabled or v.disabled == 0) and v.value and v.value > MIN_VALUE then
            local rawName = v.name or k:gsub("|fin$", "")
            local fin = v.finisher == true or v.finisher == 1
            local key = string.lower(rawName)
            local underThreshold = v.under or 0
            if underThreshold == 0 then underThreshold = v.value - DEFAULT_UNDER end
            local entry = {
                value          = v.value,
                category       = v.category or "sword",
                rarity         = "MANUAL",
                status         = "manual",
                finisher       = fin,
                source         = "manual",
                underThreshold = underThreshold,
            }
            if not values[key] then
                values[key] = { entry }
            else
                values[key][#values[key] + 1] = entry
            end
            count += 1
        end
    end
    print("[manual] " .. count .. " items loaded")
    return values, count
end

-- ── SMART VARIANT MATCHING ────────────────────────────────────────────────────

local function analyzeItem(variants, hasFinisher, sellPrice)
    if not sellPrice then return nil, false end

    local finMatch, finOther = {}, {}
    for _, v in ipairs(variants) do
        if v.finisher == hasFinisher then
            finMatch[#finMatch + 1] = v
        else
            finOther[#finOther + 1] = v
        end
    end

    local pool = #finMatch > 0 and finMatch or variants

    -- Single variant
    if #pool == 1 then
        local v = pool[1]
        local isUnder = sellPrice <= (v.value - DEFAULT_UNDER)
        if isUnder then
            for _, other in ipairs(finOther) do
                if sellPrice >= (other.value - DEFAULT_UNDER) and sellPrice <= (other.value * 1.5) then
                    return other, false
                end
            end
        end
        return v, isUnder
    end

    -- Multiple variants — count categories
    local catSet = {}
    for _, v in ipairs(pool) do catSet[v.category or "unknown"] = true end
    local catCount = 0
    for _ in pairs(catSet) do catCount += 1 end

    -- Find closest variant by score
    local closest, bestScore = nil, math.huge
    local allVariants = {}
    for _, v in ipairs(pool) do allVariants[#allVariants + 1] = v end
    for _, v in ipairs(finOther) do allVariants[#allVariants + 1] = v end

    for _, v in ipairs(allVariants) do
        local diff = math.abs(v.value - sellPrice)
        local score = catCount > 1 and (diff / math.max(v.value, 1)) or diff
        if score < bestScore then
            bestScore = score
            closest = v
        end
    end

    -- Price in reasonable range of closest
    if closest and sellPrice >= (closest.value - DEFAULT_UNDER) and sellPrice <= (closest.value * 1.5) then
        return closest, false
    end

    -- Check underrap against cheapest in pool
    local cheapest = pool[1]
    for i = 2, #pool do
        if pool[i].value < cheapest.value then cheapest = pool[i] end
    end

    local isUnder = sellPrice <= (cheapest.value - DEFAULT_UNDER)
    if isUnder then
        local rangeMul = catCount > 1 and 0.6 or 0.5
        for _, v in ipairs(variants) do
            if sellPrice >= (v.value * rangeMul) and sellPrice <= (v.value * 1.5) then
                return v, false
            end
        end
    end

    return cheapest, isUnder
end

-- ── BOOTH SCANNING ────────────────────────────────────────────────────────────

local function firePrompt(prompt)
    if typeof(prompt) ~= "Instance" or not prompt:IsA("ProximityPrompt") then return end
    if fireproximityprompt then
        fireproximityprompt(prompt)
        return
    end
    pcall(function()
        prompt:InputHoldBegin()
        task.wait(0.02)
        prompt:InputHoldEnd()
    end)
end

local function scanCurrentBooth()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local booth = pg:FindFirstChild("Booth")
    if not booth then return nil end
    local pb = booth:FindFirstChild("PlayersBooth")
    if not pb then return nil end
    local list = pb:FindFirstChild("ScrollingList")
    if not list then return nil end

    local items = {}
    for _, entry in ipairs(list:GetChildren()) do
        local itemName, amount, hasFinisher = "", "", false
        local frame = entry:FindFirstChild("Frame")
        if frame then
            local nl = frame:FindFirstChild("ItemName")
            if nl then itemName = nl.Text or "" end
            local fin = frame:FindFirstChild("Finisher")
            if fin and fin:IsA("GuiObject") then hasFinisher = fin.Visible end
        end
        local bb = entry:FindFirstChild("BuyButton")
        if bb then
            local li = bb:FindFirstChild("List")
            if li then
                local al = li:FindFirstChild("Amount")
                if al then amount = al.Text or "" end
            end
        end
        if itemName ~= "" then
            items[#items + 1] = { name = itemName, price = amount, finisher = hasFinisher }
        end
    end
    return items
end

-- ── SERVER HOP ────────────────────────────────────────────────────────────────

local function getServerList()
    local body = httpGet(string.format(
        "https://games.roblox.com/v1/games/%d/servers/Public?limit=100", PLACE_ID
    ))
    if not body then return {} end
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok or not data or not data.data then return {} end
    local servers = {}
    for _, s in ipairs(data.data) do
        servers[#servers + 1] = { jobId = s.id, players = s.playing, maxPlayers = s.maxPlayers }
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
    -- Shuffle
    for i = #servers, 2, -1 do
        local j = math.random(i)
        servers[i], servers[j] = servers[j], servers[i]
    end
    local cur = game.JobId
    for _, s in ipairs(servers) do
        if s.jobId ~= cur and not isInHistory(s.jobId) and not isServerScanned(s.jobId) then
            return s.jobId
        end
    end
    for _, s in ipairs(servers) do
        if s.jobId ~= cur and not isInHistory(s.jobId) then
            return s.jobId
        end
    end
    -- Reset history
    hopHistory = {}
    saveHopHistory()
    for _, s in ipairs(servers) do
        if s.jobId ~= cur then return s.jobId end
    end
    return nil
end

local function doHop(reason)
    local cur = game.JobId
    for attempt = 1, 5 do
        print("[hop] " .. reason .. " (" .. attempt .. "/5)")
        local nextId = pickNextServer()
        if not nextId then
            task.wait(3)
            continue
        end
        isTeleporting = true
        joinServer(nextId)
        task.wait(HOP_TELEPORT_WAIT)
        if game.JobId ~= cur then return true end
        isTeleporting = false
        addToHistory(nextId)
        task.wait(1)
    end
    isTeleporting = false
    warn("[hop] All 5 attempts failed")
    return false
end

-- ── SCAN ALL BOOTHS ───────────────────────────────────────────────────────────

local function scanAllBooths(values, source, shouldMark)
    source = source or "auto"
    if shouldMark == nil then shouldMark = true end
    if isTeleporting then return 0 end

    local currentJobId = game.JobId

    local stands = workspace:FindFirstChild("Spawn")
        and workspace.Spawn:FindFirstChild("Hub")
        and workspace.Spawn.Hub:FindFirstChild("Stands")
    if not stands then
        warn("[scanner] Stands not found")
        return 0
    end

    local boothCount, underrapCount = 0, 0
    local joinLink = string.format(
        "https://www.roblox.com/games/start?placeId=%s&gameInstanceId=%s",
        tostring(PLACE_ID), currentJobId
    )
    local deepLink = string.format(
        "roblox://placeId=%s&gameInstanceId=%s",
        tostring(PLACE_ID), currentJobId
    )

    for _, booth in ipairs(stands:GetChildren()) do
        if isTeleporting then break end
        local ownerId = booth:GetAttribute("Owner")
        if ownerId == nil then continue end
        boothCount += 1

        -- Fire proximity prompt
        local root = booth:FindFirstChild("Root")
        if root then
            local holder = root:FindFirstChild("ProximityPromptHolder")
            if holder then
                local prompt = holder:FindFirstChild("BoothProximityPrompt")
                if prompt then
                    firePrompt(prompt)
                    if BOOTH_WAIT > 0 then task.wait(BOOTH_WAIT) end
                end
            end
        end

        local items = scanCurrentBooth()
        if not items then continue end
        local username = getUsername(ownerId)

        for _, item in ipairs(items) do
            local key = string.lower(item.name)
            local variants = values[key]
            if not variants then continue end

            local sellPrice = parseNumber(item.price)
            local valueData, isUnderrap

            if source == "manual" then
                if not sellPrice then continue end
                valueData = nil
                local wantFin = item.finisher and true or false
                for _, v in ipairs(variants) do
                    if v.finisher == wantFin then valueData = v break end
                end
                if not valueData then valueData = variants[1] end
                local threshold = valueData.underThreshold or (valueData.value - DEFAULT_UNDER)
                isUnderrap = sellPrice <= threshold
            else
                valueData, isUnderrap = analyzeItem(variants, item.finisher, sellPrice)
            end

            if not valueData then continue end

            if isUnderrap then
                underrapCount += 1
                local realValue = valueData.value
                local profit = realValue - sellPrice
                local pctOff = math.floor((1 - sellPrice / realValue) * 100)
                local sourceLabel = source == "manual" and "Manual" or "BBValues"
                local variantCount = #variants

                local variantNote = ""
                if variantCount > 1 then
                    local catList = {}
                    for _, v in ipairs(variants) do
                        local label = v.category .. (v.finisher and " ✨" or "")
                        if not table.find(catList, label) then catList[#catList + 1] = label end
                    end
                    variantNote = string.format("\n⚠️ %d variants: %s\nMatched: **%s%s** (%s)",
                        variantCount, table.concat(catList, ", "),
                        valueData.category, valueData.finisher and " Finisher" or "",
                        tostring(realValue))
                end

                -- Webhook (fire-and-forget — tidak blocking scan)
                task.spawn(sendWebhook, {
                    embeds = {{
                        title = "🎯 UNDERRAP (" .. sourceLabel .. ")",
                        description = string.format("**%s** selling **%d%%** below value!%s", item.name, pctOff, variantNote),
                        color = 0x00FF88,
                        fields = {
                            { name = "📦 Item",     value = item.name,                                   inline = true },
                            { name = "💰 Price",    value = string.format("`%s`", tostring(item.price)), inline = true },
                            { name = "💎 Value",    value = string.format("`%s`", tostring(realValue)),  inline = true },
                            { name = "📈 Profit",   value = string.format("`+%s`", tostring(profit)),    inline = true },
                            { name = "🏷️ Category", value = valueData.category,                          inline = true },
                            { name = "⚔️ Finisher", value = item.finisher and "✨ Yes" or "No",          inline = true },
                            { name = "👤 Seller",   value = string.format("[%s](https://www.roblox.com/users/%s/profile)", username, tostring(ownerId)), inline = true },
                            { name = "🔗 Join",     value = string.format("[Click](%s)", joinLink),      inline = true },
                            { name = "📋 Script",   value = string.format(
                                "```lua\ngame:GetService(\"TeleportService\"):TeleportToPlaceInstance(%s, \"%s\", game.Players.LocalPlayer)\n```",
                                tostring(PLACE_ID), currentJobId
                            ), inline = false },
                            { name = "🌐 Browser",  value = string.format("```\n%s\n```", deepLink), inline = false },
                        },
                        footer = { text = sourceLabel .. " · " .. currentJobId },
                        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                    }},
                })

                -- API scan post (fire-and-forget)
                task.spawn(postScanToAPI, {
                    item_name    = item.name,
                    price        = sellPrice or 0,
                    real_value   = realValue,
                    seller       = username,
                    display_name = getDisplayName(ownerId) or username,
                    finisher     = item.finisher and 1 or 0,
                    category     = valueData.category,
                    profit       = profit,
                    job_id       = currentJobId,
                    place_id     = PLACE_ID,
                    source       = source,
                })
            end
        end

        -- Yield setiap 10 booth agar Roblox tidak freeze
        if boothCount % 10 == 0 then RunService.Heartbeat:Wait() end
    end

    if shouldMark then markServerScanned(currentJobId) end
    print(string.format("[scan] %d booths, %d underrap (%s)", boothCount, underrapCount, source))
    return underrapCount
end

-- ══════════════════════════════════════════════════════════════════════════════
-- ── MAIN ──────────────────────────────────────────────────────────────────────
-- ══════════════════════════════════════════════════════════════════════════════

-- Auto teleport ke plaza jika di sub-place
if game.PlaceId ~= ROOT_PLACE_ID then
    warn("[init] Wrong place (" .. tostring(game.PlaceId) .. "), teleporting to plaza...")
    task.wait(1)
    TeleportService:Teleport(ROOT_PLACE_ID, LocalPlayer)
    return
end

-- Load persistent state
loadHopHistory()
loadScannedServers()

print("══════════════════════════════════════════")
print("  Booth Scanner — Headless Mode")
print("  Mode: " .. SCAN_MODE)
print("  JobId: " .. game.JobId:sub(1, 12))
print("══════════════════════════════════════════")

-- Heartbeat loop (background)
task.spawn(function()
    while true do
        pcall(sendHeartbeat)
        task.wait(HEARTBEAT_INTERVAL)
    end
end)

-- Main scan + hop loop — langsung aktif
task.spawn(function()
    task.wait(3) -- tunggu game load

    while true do
        if isTeleporting then
            task.wait(2)
            continue
        end

        local currentJob = game.JobId

        -- Skip jika sudah di-scan
        if isServerScanned(currentJob) then
            print("[auto] " .. currentJob:sub(1, 8) .. " already scanned → hopping")
            local hopped = doHop("Already scanned")
            if not hopped then
                -- Gagal hop — tunggu lalu coba lagi
                warn("[auto] Hop failed, retrying in 15s...")
                task.wait(15)
            end
            continue
        end

        -- Load values sekali saja untuk kedua source
        local bbValues, manualValues = nil, nil

        if SCAN_MODE == "auto" or SCAN_MODE == "both" then
            bbValues = loadBBValues()
            if not bbValues or not next(bbValues) then
                warn("[scan] Failed to load bbvalues")
                bbValues = nil
            end
        end

        if SCAN_MODE == "manual" or SCAN_MODE == "both" then
            manualValues = loadManualValues()
            if not manualValues or not next(manualValues) then
                if SCAN_MODE == "manual" then
                    warn("[scan] Failed to load manual values")
                end
                manualValues = nil
            end
        end

        if not bbValues and not manualValues then
            warn("[scan] No values available, retrying in 5s...")
            task.wait(5)
            continue
        end

        -- Scan — jangan mark server scanned dulu, biar kedua source bisa scan
        if bbValues then
            scanAllBooths(bbValues, "auto", false) -- false = jangan mark scanned
        end
        if manualValues then
            scanAllBooths(manualValues, "manual", false)
        end

        -- Sekarang mark scanned
        markServerScanned(currentJob)
        print("[scan] Server " .. currentJob:sub(1, 8) .. " fully scanned, hopping...")

        -- Hop ke server berikutnya
        local hopped = doHop("Scan done")
        if not hopped then
            warn("[auto] Hop failed after scan, retrying in 15s...")
            task.wait(15)
        end
    end
end)
