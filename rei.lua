-- main.luau
-- Blade Ball Booth Scanner + Auto Server Hop
-- Made by Rei

local Players         = game:GetService("Players")
local LocalPlayer     = Players.LocalPlayer
local HttpService     = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

-- ── CONFIG ────────────────────────────────────────────────────────────────────
local ROOT_PLACE_ID = 16581637217 -- Blade Ball plaza (root place)
local PLACE_ID      = ROOT_PLACE_ID -- always use root for server list & teleport
local WEBHOOK_URL = "https://discord.com/api/webhooks/1510395545141907478/cN3zzPCevXKBL4nEBefV7Z6m_ufHSUYjlBHKyPK8sZGl2VufTkamnNpxL58DWvF5z7hs"
local VALUES_URL  = "http://hyper.ypnode.my.id:10750/values.json" -- server-hosted, no ngrok
local SCANS_URL   = "http://hyper.ypnode.my.id:10750/scans"       -- POST scan results for dashboard
local HEARTBEAT_URL = "http://hyper.ypnode.my.id:10750/heartbeat"
local HOP_SKIP_COUNT  = 20
local HOP_HISTORY_FILE = "hop_history.json"
local SCANNED_SERVERS_FILE = "scanned_servers.json"
-- ─────────────────────────────────────────────────────────────────────────────

local hopHistory = {}
local scannedServers = {} -- track which servers have been scanned
local isTeleporting = false -- guard against duplicate scans during teleport

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
    -- Clean old entries (older than 5 minutes)
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
    Title = "Booth Scanner",
    Footer = "Made by Rei",
    Icon = 95816097006870,
    NotifySide = "Right",
    ShowCustomCursor = true,
})

-- ── UTILITY ───────────────────────────────────────────────────────────────────

local function httpGet(url)
    local headers = {
        ["User-Agent"] = "Mozilla/5.0",
        ["Accept"] = "application/json",
        ["ngrok-skip-browser-warning"] = "true",
    }
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
        -- fallback: use username
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

local function sendHeartbeat()
    local json = HttpService:JSONEncode({ username = LocalPlayer.Name, job_id = game.JobId })
    local opts = {
        Url = HEARTBEAT_URL, Method = "POST",
        Headers = { ["Content-Type"] = "application/json" }, Body = json,
    }
    if request then pcall(request, opts)
    elseif syn and syn.request then pcall(syn.request, opts)
    else pcall(function() HttpService:PostAsync(HEARTBEAT_URL, json) end)
    end
end

-- Heartbeat loop: send every 2 minutes
task.spawn(function()
    while true do
        pcall(sendHeartbeat)
        task.wait(120)
    end
end)

-- ── VALUES ────────────────────────────────────────────────────────────────────

local MANUAL_URL = "http://hyper.ypnode.my.id:10750/items.json"

local function loadValues()
    print("[values] Fetching: " .. VALUES_URL)
    local body = httpGet(VALUES_URL)
    if not body then
        warn("[values] httpGet returned nil")
        return {}
    end
    -- Guard: ngrok returned HTML instead of JSON
    if body:sub(1, 1) ~= "{" and body:sub(1, 1) ~= "[" then
        warn("[values] Response is not JSON (got HTML?): " .. body:sub(1, 100))
        return {}
    end
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok then
        warn("[values] JSONDecode failed: " .. tostring(data))
        return {}
    end
    if not data or not data.items then
        warn("[values] No 'items' field")
        return {}
    end
    local normalized = {}
    local count = 0
    for k, v in pairs(data.items) do
        if not v.disabled then
            -- Keys from /values.json may be "Name" or "Name|fin"
            local rawName = v.name or k:gsub("|fin$", "")
            local fin = v.finisher and true or false
            local nkey = string.lower(rawName) .. (fin and "|1" or "|0")
            normalized[nkey] = {
                value    = v.value,
                under    = v.under or 0,
                category = v.category or "unknown",
                finisher = fin,
                source   = "manual",
            }
            count += 1
        end
    end
    print("[values] Loaded " .. count .. " items")
    return normalized
end

-- Load manual items from /items.json (new CRUD endpoint)
local function loadManualItems()
    print("[manual] Fetching: " .. MANUAL_URL)
    local body = httpGet(MANUAL_URL)
    if not body then
        warn("[manual] httpGet returned nil")
        return {}
    end
    if body:sub(1, 1) ~= "{" then
        warn("[manual] Response is not JSON")
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
    local normalized = {}
    local count = 0
    for _, item in ipairs(data.items) do
        if not item.disabled and item.name and item.value then
            local fin = item.finisher and true or false
            local key = string.lower(item.name) .. (fin and "|1" or "|0")
            normalized[key] = {
                value    = item.value,
                under    = item.under or 0,
                category = item.category or "unknown",
                finisher = fin,
                source   = "manual",
            }
            count += 1
        end
    end
    print("[manual] Loaded " .. count .. " manual items")
    return normalized
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
    -- shuffle
    for i = #servers, 2, -1 do
        local j = math.random(i)
        servers[i], servers[j] = servers[j], servers[i]
    end
    local currentJob = game.JobId
    -- First pass: skip current, history, and already-scanned servers
    for _, s in ipairs(servers) do
        if s.jobId ~= currentJob and not isInHistory(s.jobId) and not isServerScanned(s.jobId) then
            return s.jobId
        end
    end
    -- Second pass: allow already-scanned but not in history
    for _, s in ipairs(servers) do
        if s.jobId ~= currentJob and not isInHistory(s.jobId) then
            return s.jobId
        end
    end
    -- All in history — reset
    warn("[hop] All servers in history, resetting")
    hopHistory = {}
    saveHopHistory()
    for _, s in ipairs(servers) do
        if s.jobId ~= currentJob then return s.jobId end
    end
    return nil
end

-- Aggressive hop: try multiple servers quickly
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
            return true -- teleport succeeded
        end
        -- Failed — mark this server as bad and try another
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

-- forward declare — assigned BEFORE startAutoScan is ever called
local scanAllBooths = nil

local function startAutoScan()
    stopAutoScan()
    autoScanThread = task.spawn(function()
        -- wait until scanAllBooths is assigned (it's defined later in the file)
        while scanAllBooths == nil do task.wait(0.1) end
        while autoScanEnabled do
            -- Guard: don't scan if we're teleporting
            if isTeleporting then
                print("[auto] Teleporting, skipping scan")
                task.wait(2)
                continue
            end

            local currentJob = game.JobId

            -- Skip if this server was already scanned
            if isServerScanned(currentJob) then
                print("[auto] Server " .. currentJob:sub(1, 8) .. " already scanned")
                if autoHopEnabled then
                    doHop("Already scanned")
                    if game.JobId == currentJob then
                        task.wait(10) -- all hops failed, cooldown
                    end
                else
                    task.wait(5)
                end
                continue
            end

            local values = loadValues()
            local manualValues = loadManualItems()
            if next(values) or next(manualValues) then
                scanAllBooths(values, manualValues)
            else
                Library:Notify({ Title = "Auto Scan", Description = "Failed to load values, retry in 5s", Time = 3 })
                task.wait(5)
            end
            if autoScanEnabled and not autoHopEnabled then
                task.wait(2)
            end
        end
    end)
end

scanAllBooths = function(values, manualValues)
    manualValues = manualValues or {}
    -- Guard: don't scan if teleporting
    if isTeleporting then
        print("[scanner] Skipping scan — teleporting")
        return
    end

    local currentJobId = game.JobId

    -- Guard: don't scan same server twice
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
            local sellPrice = parseNumber(item.price)

            -- Manual lookup: exact finisher match first, then fallback
            local finKey = key .. (item.finisher and "|1" or "|0")
            local manualData = manualValues[finKey]
            if not manualData then
                -- fallback: try the other variant
                local altKey = key .. (item.finisher and "|0" or "|1")
                manualData = manualValues[altKey]
            end

            -- Auto lookup: exact finisher match first, then fallback
            local autoData = values[finKey]
            if not autoData then
                local altKey = key .. (item.finisher and "|0" or "|1")
                autoData = values[altKey]
            end

            -- Check manual underrap
            local manualUnderrap = false
            local manualRealValue, manualThreshold, manualCategory, manualUnderVal, manualProfit
            if manualData then
                manualRealValue = manualData.value
                manualUnderVal  = manualData.under or 0
                local manualDeduction = (manualUnderVal > 0) and manualUnderVal or 30
                manualThreshold = manualRealValue - manualDeduction
                manualCategory  = manualData.category or "unknown"
                if sellPrice and sellPrice <= manualThreshold then
                    manualUnderrap = true
                    manualProfit = manualThreshold - sellPrice
                end
            end

            -- Check auto underrap
            local autoUnderrap = false
            local autoRealValue, autoThreshold, autoCategory, autoUnderVal, autoProfit
            if autoData then
                autoRealValue = autoData.value
                autoUnderVal  = autoData.under or 0
                local autoDeduction = (autoUnderVal > 0) and autoUnderVal or 30
                autoThreshold = autoRealValue - autoDeduction
                autoCategory  = autoData.category or "unknown"
                if sellPrice and sellPrice <= autoThreshold then
                    autoUnderrap = true
                    autoProfit = autoThreshold - sellPrice
                end
            end

            -- Determine what to report: manual first, then auto fallback
            local isUnderrap = manualUnderrap or autoUnderrap
            local primaryValue = manualData and manualRealValue or (autoData and autoRealValue or nil)
            local primaryCat   = manualData and manualCategory or (autoData and autoCategory or "unknown")
            local primaryUnder = manualData and manualUnderVal or (autoData and autoUnderVal or 0)

            if not primaryValue then continue end

            table.insert(results, string.format(
                "%s | Price: %s | Value: %s | Cat: %s%s%s",
                item.name, item.price, tostring(primaryValue), primaryCat,
                item.finisher and " | FINISHER" or "",
                isUnderrap and " | <UNDERRAP>" or ""
            ))

            if isUnderrap then
                underrapCount += 1

                -- Webhook uses the primary (manual if available, else auto) data
                local webhookValue = manualUnderrap and manualRealValue or autoRealValue
                local webhookThreshold = manualUnderrap and manualThreshold or autoThreshold
                local webhookProfit = manualUnderrap and manualProfit or autoProfit
                local webhookUnder = manualUnderrap and manualUnderVal or autoUnderVal
                local pctOff = math.floor((1 - sellPrice / webhookThreshold) * 100)

                sendWebhook({
                    embeds = {{
                        title = "🎯 UNDERRAP FOUND",
                        description = string.format("**%s** is selling **%d%%** below %s!", item.name, pctOff, webhookUnder > 0 and "under threshold" or "value"),
                        color = 0x00FF88,
                        fields = {
                            { name = "📦 Item",       value = item.name,                                    inline = true },
                            { name = "💰 Price",      value = string.format("`%s`", tostring(item.price)),  inline = true },
                            { name = "💎 Value",      value = string.format("`%s`", tostring(webhookValue)),   inline = true },
                            { name = "🔻 Under",      value = string.format("`%s`", webhookUnder > 0 and tostring(webhookUnder) or "—"), inline = true },
                            { name = "📈 Profit",     value = string.format("`+%s`", tostring(webhookProfit)),     inline = true },
                            { name = "🏷️ Category",  value = primaryCat,                                     inline = true },
                            { name = "⚔️ Finisher",  value = item.finisher and "✨ Yes" or "No",           inline = true },
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
                        footer = { text = "Underrap Scanner · " .. currentJobId },
                        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                    }},
                })

                -- POST to bot API: send manual scan if manual found underrap
                if manualUnderrap then
                    postScanToAPI({
                        item_name  = item.name,
                        price      = sellPrice or 0,
                        real_value = manualRealValue,
                        seller     = username,
                        display_name = getDisplayName(ownerId) or username,
                        finisher   = item.finisher and 1 or 0,
                        category   = manualCategory,
                        profit     = manualProfit,
                        job_id     = currentJobId,
                        place_id   = PLACE_ID,
                        source     = "manual",
                    })
                end

                -- POST to bot API: send auto scan if auto found underrap
                -- (always send auto separately, even if manual also found it)
                if autoUnderrap then
                    postScanToAPI({
                        item_name  = item.name,
                        price      = sellPrice or 0,
                        real_value = autoRealValue,
                        seller     = username,
                        display_name = getDisplayName(ownerId) or username,
                        finisher   = item.finisher and 1 or 0,
                        category   = autoCategory,
                        profit     = autoProfit,
                        job_id     = currentJobId,
                        place_id   = PLACE_ID,
                        source     = "auto",
                    })
                end

                -- If only manual found underrap (no auto), still send as the primary
                -- If only auto found underrap (no manual), already sent above
                -- If neither has manual data nor auto data, we already continued above

                task.wait(0.1)
            end
        end

        task.wait(0)
        table.insert(results, "")
    end

    local output = table.concat(results, "\n")
    if writefile then writefile("booth_scan_results.txt", output) end

    -- Mark this server as scanned AFTER completing scan
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

MainGroup:AddButton({
    Text = "🔄 Refresh Values",
    Func = function()
        task.spawn(function()
            Library:Notify({ Title = "Refresh", Description = "Fetching values...", Time = 2 })

            local autoVals = loadValues()
            local manualVals = loadManualItems()

            local autoCount = 0
            local manualCount = 0
            if autoVals then for _ in pairs(autoVals) do autoCount += 1 end end
            if manualVals then for _ in pairs(manualVals) do manualCount += 1 end end

            -- Clear scanned status for current server so it can be re-scanned
            local currentJob = game.JobId
            if scannedServers[currentJob] then
                scannedServers[currentJob] = nil
                saveScannedServers()
            end

            Library:Notify({
                Title = "Refresh Complete",
                Description = string.format("Auto: %d | Manual: %d", autoCount, manualCount),
                Time = 5,
            })
        end)
    end,
    Tooltip = "Force fetch ulang Auto + Manual values",
})

MainGroup:AddDivider()

MainGroup:AddButton({
    Text = "Scan All Booths",
    Func = function()
        local values = loadValues()
        local manualVals = loadManualItems()
        if not next(values) and not next(manualVals) then
            Library:Notify({ Title = "Error", Description = "Failed to load values", Time = 5 })
            return
        end
        task.spawn(scanAllBooths, values, manualVals)
    end,
    Tooltip = "Scan all booths and send webhook on underrap",
})

MainGroup:AddDivider()

-- NOTE: Callback here handles manual toggle clicks.
-- Init (on script load) is handled separately in the INIT section below.
-- OnChanged is NOT used — Callback is sufficient for runtime changes.
MainGroup:AddToggle("AutoScan", {
    Default = false,
    Text = "Auto Scan",
    Tooltip = "Continuously scan booths. State is saved.",
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
    Tooltip = string.format("Hop to next server after scan (skip last %d). Works with or without Auto Scan.", HOP_SKIP_COUNT),
    Callback = function(val)
        autoHopEnabled = val
        -- If auto hop enabled but auto scan is not running, start auto scan too
        -- (auto hop needs the scan loop to function)
        if val and not autoScanEnabled then
            autoScanEnabled = true
            Toggles.AutoScan:SetValue(true)
            startAutoScan()
            Library:Notify({ Title = "Auto Hop", Description = "Auto Scan enabled automatically", Time = 3 })
        end
    end,
})

MainGroup:AddDivider()

-- Webhook & Values URL are hardcoded — no GUI input needed

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
ThemeManager:SetFolder("BoothScanner")
SaveManager:SetFolder("BoothScanner")
SaveManager:BuildConfigSection(Tabs.UISett)
ThemeManager:ApplyToTab(Tabs.UISett)
SaveManager:LoadAutoloadConfig()

-- ── INIT ──────────────────────────────────────────────────────────────────────
-- LoadAutoloadConfig applies saved toggle values but does NOT fire Callbacks.
-- We read the toggle values directly after a short wait and start if needed.

loadHopHistory()
loadScannedServers()

-- ── QUEUE ON TELEPORT (auto re-execute after hop) ─────────────────────────────
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

-- ── AUTO TELEPORT TO PLAZA ────────────────────────────────────────────────────
-- If we're in a sub-place (not the root plaza), teleport back to plaza
if game.PlaceId ~= ROOT_PLACE_ID then
    Library:Notify({ Title = "Wrong Place", Description = "Teleporting to Plaza...", Time = 5 })
    warn("[init] Current PlaceId=" .. tostring(game.PlaceId) .. " != ROOT=" .. tostring(ROOT_PLACE_ID) .. ", teleporting to plaza")
    task.wait(2)
    TeleportService:Teleport(ROOT_PLACE_ID, LocalPlayer)
    -- Script will restart after teleport, so stop here
    return
end

Library:Notify({ Title = "Booth Scanner", Description = "Loaded", Time = 3 })

task.spawn(function()
    task.wait(1) -- let Obsidian finish applying saved config

    -- Sync runtime vars from saved toggle state
    autoHopEnabled  = Toggles.AutoHop.Value
    autoScanEnabled = Toggles.AutoScan.Value

    print("[init] AutoScan=" .. tostring(autoScanEnabled) .. " AutoHop=" .. tostring(autoHopEnabled))
    print("[init] VALUES_URL=" .. VALUES_URL)

    if autoScanEnabled then
        Library:Notify({ Title = "Auto Scan", Description = "Resuming from saved config", Time = 4 })
        startAutoScan()
    end
end)
