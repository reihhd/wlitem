-- main_bbvalues.luau
-- Blade Ball Booth Scanner — Values langsung dari bbvalues.uk
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
local SCANS_URL   = "http://hyper.ypnode.my.id:10750/scans"
local MIN_VALUE      = 100 -- hanya scan item dengan value > ini
local DEFAULT_UNDER  = 20  -- default under deduction
local HOP_SKIP_COUNT = 20
local HOP_HISTORY_FILE = "hop_history.json"
local SCANNED_SERVERS_FILE = "scanned_servers.json"
-- ─────────────────────────────────────────────────────────────────────────────

local hopHistory = {}
local scannedServers = {}
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

local function loadScannedServers()
    if readfile then
        local ok, content = pcall(readfile, SCANNED_SERVERS_FILE)
        if ok and content ~= "" then
            local ok2, data = pcall(function() return HttpService:JSONDecode(content) end)
            if ok2 and type(data) == "table" then scannedServers = data return end
        end
    end
    scannedServers = {}
end

local function saveScannedServers()
    if writefile then
        pcall(writefile, SCANNED_SERVERS_FILE, HttpService:JSONEncode(scannedServers))
    end
end

local function markServerScanned(jobId)
    scannedServers[jobId] = os.time()
    local now = os.time()
    local cleaned = {}
    for id, t in pairs(scannedServers) do
        if now - t < 300 then cleaned[id] = t end
    end
    scannedServers = cleaned
    saveScannedServers()
end

local function isServerScanned(jobId)
    return scannedServers[jobId] ~= nil
end

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

local function httpGet(url, extraHeaders)
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
    local json = HttpService:JSONEncode(payload)
    local opts = {
        Url = WEBHOOK_URL, Method = "POST",
        Headers = { ["Content-Type"] = "application/json" }, Body = json,
    }
    if request then pcall(request, opts)
    elseif syn and syn.request then pcall(syn.request, opts)
    else pcall(function() HttpService:PostAsync(WEBHOOK_URL, json) end)
    end
end

local function postScanToAPI(data)
    local json = HttpService:JSONEncode(data)
    local opts = {
        Url = SCANS_URL, Method = "POST",
        Headers = { ["Content-Type"] = "application/json" }, Body = json,
    }
    if request then pcall(request, opts)
    elseif syn and syn.request then pcall(syn.request, opts)
    else pcall(function() HttpService:PostAsync(SCANS_URL, json) end)
    end
end

-- ── BBVALUES.UK API ───────────────────────────────────────────────────────────
-- Fetch langsung dari bbvalues.uk/api/items
-- Response: array of { id, n(name), c(category), p(price/value), r(rarity),
--                       st(status), tg(tag), ch(change24h), a(avgPrice), f(finisher) }

local BBVALUES_CACHE_FILE = "bbvalues_cache.json"
local cachedBBValues = nil      -- in-memory cache
local lastFetchTime  = 0        -- os.time() of last successful fetch
local CACHE_TTL      = 300      -- 5 menit — pakai cache kalau masih fresh

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
                    finisher = (item.s == "Finisher"), -- HANYA s=="Finisher", f adalah "has finisher variant"
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
    return httpGet("https://bbvalues.uk/api/items", {
        ["x-bbv-handshake"] = "v1-secure-request",
        ["Referer"] = "https://bbvalues.uk/values/",
    })
end

local function loadBBValues()
    -- 1. Kalau in-memory cache masih fresh, pakai itu
    if cachedBBValues and (os.time() - lastFetchTime) < CACHE_TTL then
        print("[bbvalues] Using in-memory cache (" .. (os.time() - lastFetchTime) .. "s old)")
        return cachedBBValues
    end

    -- 2. Coba fetch dari API (dengan retry)
    local MAX_RETRIES = 3
    local body = nil
    for attempt = 1, MAX_RETRIES do
        print(string.format("[bbvalues] Fetch attempt %d/%d...", attempt, MAX_RETRIES))
        body = fetchBBValuesRaw()
        local data = parseBBValuesBody(body)
        if data and #data > 100 then
            -- Berhasil! Simpan cache
            print("[bbvalues] API fetch OK: " .. #data .. " items")
            saveBBValuesCache(body)
            local values, count = buildValuesLookup(data)
            if count > 0 then
                cachedBBValues = values
                lastFetchTime = os.time()
                return values
            end
        end
        -- Gagal — log error
        if body then
            local preview = body:sub(1, 80):gsub("%s+", " ")
            warn(string.format("[bbvalues] Attempt %d failed: %s", attempt, preview))
        else
            warn(string.format("[bbvalues] Attempt %d failed: nil response", attempt))
        end
        if attempt < MAX_RETRIES then
            local delay = attempt * 3 -- 3s, 6s
            print("[bbvalues] Retrying in " .. delay .. "s...")
            task.wait(delay)
        end
    end

    -- 3. API gagal semua — coba in-memory cache (meski expired)
    if cachedBBValues then
        local age = os.time() - lastFetchTime
        warn(string.format("[bbvalues] API failed, using expired in-memory cache (%ds old)", age))
        Library:Notify({ Title = "BBValues", Description = string.format("API down, using cache (%dm old)", math.floor(age / 60)), Time = 5 })
        return cachedBBValues
    end

    -- 4. Tidak ada in-memory cache — coba file cache
    local fileData = loadBBValuesFromFile()
    if fileData then
        local values, count = buildValuesLookup(fileData)
        if count > 0 then
            cachedBBValues = values
            lastFetchTime = os.time() - CACHE_TTL + 60 -- mark as "almost expired" so next call retries
            warn("[bbvalues] API failed, using file cache")
            Library:Notify({ Title = "BBValues", Description = "API down, using saved cache", Time = 5 })
            return values
        end
    end

    -- 5. Benar-benar gagal
    warn("[bbvalues] All attempts failed, no cache available")
    return {}
end

-- Analisis smart variant matching
-- 
-- Fakta dari bbvalues.uk API:
--   s = "Finisher"  → item ini ADALAH versi finisher (contoh: Frog Finisher = 2.5M)
--   s = "None"      → item ini bukan finisher (contoh: Frog biasa = 1M)
--   f = true/false  → item ini PUNYA variant finisher (bukan berarti item ini finisher!)
--
-- Di booth Blade Ball:
--   Frame.Finisher.Visible = true  → item yang dijual adalah versi finisher
--   Frame.Finisher.Visible = false → item yang dijual bukan finisher
--
-- Strategi matching:
--   1. Kalau booth punya finisher → cari variant dengan s="Finisher"
--   2. Kalau booth TIDAK punya finisher → cari variant dengan s!="Finisher"
--   3. Kalau ada multiple variant non-finisher (beda category: Sword/Emote/Explosion)
--      → cek harga jual, cocokkan ke variant yang value-nya paling dekat
--   4. Hanya report underrap kalau harga jual di bawah SEMUA variant yang cocok

local function analyzeItem(variants, hasFinisher, sellPrice)
    if not sellPrice then
        return nil, false
    end

    -- Step 1: Filter berdasarkan finisher status booth
    local finisherMatch = {}   -- variant yang cocok finisher status
    local finisherOther = {}   -- variant yang beda finisher status
    for _, v in ipairs(variants) do
        if v.finisher == hasFinisher then
            table.insert(finisherMatch, v)
        else
            table.insert(finisherOther, v)
        end
    end

    -- Pool utama: yang cocok finisher status, fallback ke semua
    local pool = #finisherMatch > 0 and finisherMatch or variants

    -- Step 2: Kalau cuma 1 variant di pool, langsung cek underrap
    if #pool == 1 then
        local v = pool[1]
        local threshold = v.value - DEFAULT_UNDER
        local isUnderrap = sellPrice <= threshold

        -- Safety: cek apakah harga jual cocok dengan variant LAIN (beda finisher/category)
        if isUnderrap then
            for _, other in ipairs(finisherOther) do
                local low  = other.value - DEFAULT_UNDER
                local high = other.value * 1.5
                if sellPrice >= low and sellPrice <= high then
                    return other, false -- harga cocok variant lain, bukan underrap
                end
            end
        end

        return v, isUnderrap
    end

    -- Step 3: Multiple variant di pool (beda category: Sword/Emote/Explosion)
    -- Cari variant yang value-nya paling DEKAT dengan harga jual
    -- Ini menghindari false positive: dijual 300, Sword=2500, Emote=300 → match Emote
    local closestVariant = nil
    local closestDiff = math.huge
    for _, v in ipairs(pool) do
        local diff = math.abs(v.value - sellPrice)
        if diff < closestDiff then
            closestDiff = diff
            closestVariant = v
        end
    end

    -- Cek juga variant di luar pool (beda finisher) untuk safety
    for _, v in ipairs(finisherOther) do
        local diff = math.abs(v.value - sellPrice)
        if diff < closestDiff then
            closestDiff = diff
            closestVariant = v
        end
    end

    -- Kalau harga jual dekat dengan closest variant → bukan underrap
    if closestVariant then
        local low  = closestVariant.value - DEFAULT_UNDER
        local high = closestVariant.value * 1.5
        if sellPrice >= low and sellPrice <= high then
            return closestVariant, false -- harga wajar untuk variant ini
        end
    end

    -- Step 4: Harga jual tidak dekat dengan variant manapun
    -- Cek apakah underrap terhadap variant TERMURAH di pool
    -- (pakai termurah supaya aman — kalau di bawah yang termurah pun, baru underrap)
    local cheapest = pool[1]
    for i = 2, #pool do
        if pool[i].value < cheapest.value then
            cheapest = pool[i]
        end
    end

    local threshold = cheapest.value - DEFAULT_UNDER
    local isUnderrap = sellPrice <= threshold

    -- Final safety: cek semua variant (termasuk beda finisher)
    if isUnderrap then
        for _, v in ipairs(variants) do
            if sellPrice >= (v.value * 0.5) and sellPrice <= (v.value * 1.5) then
                return v, false -- harga masuk range wajar variant ini
            end
        end
    end

    return cheapest, isUnderrap
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

local function scanCurrentBooth()
    local list = getScrollingList()
    if not list then return {} end
    local items = {}
    for _, entry in ipairs(list:GetChildren()) do
        local itemName, amount, hasFinisher = "", "", false
        local frame = entry:FindFirstChild("Frame")
        if frame then
            local nl = frame:FindFirstChild("ItemName")
            if nl and (nl:IsA("TextLabel") or nl:IsA("TextBox")) then itemName = nl.Text end
            local fin = frame:FindFirstChild("Finisher")
            if fin and fin:IsA("GuiObject") then hasFinisher = fin.Visible end
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
            table.insert(items, { name = itemName, price = amount, finisher = hasFinisher })
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

-- ── SCAN ALL BOOTHS ───────────────────────────────────────────────────────────

local autoHopEnabled  = false
local autoScanEnabled = false
local autoScanThread  = nil

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

            local values = loadBBValues()
            if next(values) then
                scanAllBooths(values)
            else
                Library:Notify({ Title = "Auto Scan", Description = "Failed to load bbvalues, retry in 5s", Time = 3 })
                task.wait(5)
            end
            if autoScanEnabled and not autoHopEnabled then
                task.wait(2)
            end
        end
    end)
end

scanAllBooths = function(values)
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
    local joinLink = string.format(
        "https://www.roblox.com/games/start?placeId=%s&gameInstanceId=%s",
        tostring(PLACE_ID), currentJobId
    )
    local deepLink = string.format(
        "roblox://placeId=%s&gameInstanceId=%s",
        tostring(PLACE_ID), currentJobId
    )

    for _, booth in ipairs(stands:GetChildren()) do
        local ownerId = booth:GetAttribute("Owner")
        if ownerId == nil then continue end
        boothCount += 1

        local prompt = nil
        local root = booth:FindFirstChild("Root")
        if root then
            local holder = root:FindFirstChild("ProximityPromptHolder")
            if holder then prompt = holder:FindFirstChild("BoothProximityPrompt") end
        end
        if prompt then firePrompt(prompt) task.wait(0.1) end

        local items    = scanCurrentBooth()
        local username = getUsername(ownerId)

        table.insert(results, string.format("=== Booth: %s (%s) ===", username, tostring(ownerId)))

        for _, item in ipairs(items) do
            local key       = string.lower(item.name)
            local variants  = values[key]
            if not variants then continue end

            -- Analisis smart: cek apakah harga jual cocok dengan variant manapun
            local sellPrice = parseNumber(item.price)
            local variantCount = #variants
            local valueData, isUnderrap = analyzeItem(variants, item.finisher, sellPrice)
            if not valueData then continue end -- tidak bisa parse harga
            local realValue = valueData.value
            local category  = valueData.category
            local rarity    = valueData.rarity

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
                        local label = v.category .. (v.finisher and " ✨" or "")
                        if not table.find(cats, label) then table.insert(cats, label) end
                    end
                    variantNote = string.format("\n⚠️ %d variants exist: %s\nMatched: **%s%s** (value %s)",
                        variantCount, table.concat(cats, ", "),
                        category, valueData.finisher and " Finisher" or "",
                        tostring(realValue))
                end
                sendWebhook({
                    embeds = {{
                        title = "🎯 UNDERRAP FOUND (BBValues)",
                        description = string.format("**%s** selling **%d%%** below value!%s", item.name, pctOff, variantNote),
                        color = 0x00FF88,
                        fields = {
                            { name = "📦 Item",       value = item.name,                                    inline = true },
                            { name = "💰 Price",      value = string.format("`%s`", tostring(item.price)),  inline = true },
                            { name = "💎 Value",      value = string.format("`%s`", tostring(realValue)),   inline = true },
                            { name = "🏷️ Rarity",    value = rarity,                                       inline = true },
                            { name = "📈 Profit",     value = string.format("`+%s`", tostring(profit)),     inline = true },
                            { name = "🏷️ Category",  value = category .. (variantCount > 1 and string.format(" (%d variants)", variantCount) or ""), inline = true },
                            { name = "⚔️ Finisher",  value = item.finisher and "✨ Yes" or "No",           inline = true },
                            { name = "📊 Status",     value = valueData.status,                             inline = true },
                            { name = "👤 Seller",    value = string.format("[%s](https://www.roblox.com/users/%s/profile)", username, tostring(ownerId)), inline = true },
                            { name = "🔗 Join Server", value = string.format("[Click to Join](%s)", joinLink), inline = true },
                            { name = "📋 Join Script", value = string.format(
                                "```lua\ngame:GetService(\"TeleportService\"):TeleportToPlaceInstance(%s, \"%s\", game.Players.LocalPlayer)\n```",
                                tostring(PLACE_ID), currentJobId
                            ), inline = false },
                            { name = "🌐 Join (Tanpa Executor)", value = string.format(
                                "Copy lalu paste ke address bar browser:\n```\n%s\n```", deepLink
                            ), inline = false },
                            { name = "🆔 Job ID", value = string.format("`%s`", currentJobId), inline = false },
                        },
                        footer = { text = "BBValues Scanner · " .. currentJobId },
                        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                    }},
                })
                postScanToAPI({
                    item_name  = item.name,
                    price      = sellPrice or 0,
                    real_value = realValue,
                    seller     = username,
                    display_name = getDisplayName(ownerId) or username,
                    finisher   = item.finisher and 1 or 0,
                    category   = category,
                    profit     = profit,
                    job_id     = currentJobId,
                    place_id   = PLACE_ID,
                })
                task.wait(0.1)
            end
        end

        task.wait(0)
        table.insert(results, "")
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
local MainGroup = Tabs.Main:AddGroupbox({ Side = "Left", Name = "Scanner (BBValues)" })

MainGroup:AddLabel("Values dari bbvalues.uk (min > " .. MIN_VALUE .. ")")
MainGroup:AddDivider()

MainGroup:AddButton({
    Text = "Scan All Booths",
    Func = function()
        local values = loadBBValues()
        if not next(values) then
            Library:Notify({ Title = "Error", Description = "Failed to load bbvalues", Time = 5 })
            return
        end
        task.spawn(scanAllBooths, values)
    end,
    Tooltip = "Scan all booths using bbvalues.uk prices",
})

MainGroup:AddDivider()

MainGroup:AddToggle("AutoScan", {
    Default = false,
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
    Default = false,
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
SaveManager:LoadAutoloadConfig()

-- ── INIT ──────────────────────────────────────────────────────────────────────

loadHopHistory()
loadScannedServers()

if game.PlaceId ~= ROOT_PLACE_ID then
    Library:Notify({ Title = "Wrong Place", Description = "Teleporting to Plaza...", Time = 5 })
    task.wait(2)
    TeleportService:Teleport(ROOT_PLACE_ID, LocalPlayer)
    return
end

Library:Notify({ Title = "BBValues Scanner", Description = string.format("Loaded (min value: %d)", MIN_VALUE), Time = 3 })

task.spawn(function()
    task.wait(1)
    autoHopEnabled  = Toggles.AutoHop.Value
    autoScanEnabled = Toggles.AutoScan.Value
    print("[init] AutoScan=" .. tostring(autoScanEnabled) .. " AutoHop=" .. tostring(autoHopEnabled))
    if autoScanEnabled then
        Library:Notify({ Title = "Auto Scan", Description = "Resuming from saved config", Time = 4 })
        startAutoScan()
    end
end)
