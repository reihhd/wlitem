-- main.luau
-- Blade Ball Booth Scanner + Auto Server Hop
-- Made by Rei

local Players         = game:GetService("Players")
local LocalPlayer     = Players.LocalPlayer
local HttpService     = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

-- ── CONFIG ────────────────────────────────────────────────────────────────────
local ROOT_PLACE_ID = 13866929223 -- Blade Ball plaza (root place)
local PLACE_ID      = ROOT_PLACE_ID -- always use root for server list & teleport
local WEBHOOK_URL = "https://discord.com/api/webhooks/1510395545141907478/cN3zzPCevXKBL4nEBefV7Z6m_ufHSUYjlBHKyPK8sZGl2VufTkamnNpxL58DWvF5z7hs"
local VALUES_URL  = "http://hyper.ypnode.my.id:10750/values.json" -- server-hosted, no ngrok
local SCANS_URL   = "http://hyper.ypnode.my.id:10750/scans"       -- POST scan results for dashboard
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

-- ── VALUES ────────────────────────────────────────────────────────────────────

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
            normalized[string.lower(k)] = v
            count += 1
        end
    end
    print("[values] Loaded " .. count .. " items")
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

local cachedServerList = {}
local cachedServerTime = 0
local CACHE_TTL = 15 -- cache server list for 15 seconds

local function fetchServerPage(url)
    for attempt = 1, 2 do
        local body = httpGet(url)
        if body and (body:sub(1, 1) == "{" or body:sub(1, 1) == "[") then
            local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
            if ok and data and data.data then return data end
        end
        warn("[hop] Page fetch attempt " .. attempt .. " failed, retrying in " .. attempt .. "s")
        task.wait(attempt)
    end
    return nil
end

local function getServerList(forceRefresh)
    -- Return cached if fresh enough
    if not forceRefresh and #cachedServerList > 0 and (os.time() - cachedServerTime) < CACHE_TTL then
        return cachedServerList
    end
    for fullAttempt = 1, 2 do
        local servers = {}
        local cursor = ""
        local maxPages = 3 -- 300 servers is enough, faster
        local failed = false
        for page = 1, maxPages do
            local url = string.format(
                "https://games.roblox.com/v1/games/%s/servers/Public?limit=100%s",
                tostring(PLACE_ID),
                cursor ~= "" and ("&cursor=" .. cursor) or ""
            )
            local data = fetchServerPage(url)
            if not data then
                warn("[hop] Failed page " .. page .. " attempt " .. fullAttempt)
                failed = true
                break
            end
            for _, s in ipairs(data.data) do
                if s.playing and s.maxPlayers and s.id and s.playing < s.maxPlayers then
                    table.insert(servers, { jobId = s.id, players = s.playing, maxPlayers = s.maxPlayers })
                end
            end
            if not data.nextPageCursor or data.nextPageCursor == "" then break end
            cursor = data.nextPageCursor
            task.wait(0.3)
        end
        if not failed and #servers > 0 then
            print("[hop] Fetched " .. #servers .. " servers")
            cachedServerList = servers
            cachedServerTime = os.time()
            return servers
        end
        warn("[hop] Attempt " .. fullAttempt .. " got 0 servers, retrying in 3s")
        task.wait(3)
    end
    warn("[hop] All attempts failed")
    return {}
end

local function joinServer(jobId)
    addToHistory(game.JobId)
    TeleportService:TeleportToPlaceInstance(PLACE_ID, jobId, LocalPlayer)
end

local function pickNextServer(forceRefresh)
    local servers = getServerList(forceRefresh)
    if #servers == 0 then
        warn("[hop] getServerList returned 0 servers")
        return nil
    end
    -- sort by most players first (more booths)
    table.sort(servers, function(a, b) return a.players > b.players end)
    local currentJob = game.JobId
    -- First pass: skip current, history, and already-scanned servers
    for _, s in ipairs(servers) do
        if s.jobId ~= currentJob and not isInHistory(s.jobId) and not isServerScanned(s.jobId) then
            print("[hop] Picked unscanned: " .. s.jobId:sub(1, 8) .. " (" .. s.players .. "p)")
            return s.jobId
        end
    end
    -- Second pass: allow already-scanned but not in history
    for _, s in ipairs(servers) do
        if s.jobId ~= currentJob and not isInHistory(s.jobId) then
            print("[hop] Picked (may re-scan): " .. s.jobId:sub(1, 8))
            return s.jobId
        end
    end
    -- All in history — reset and try again
    warn("[hop] All " .. #servers .. " in history, resetting")
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
        -- Force refresh server list on retry
        local nextServer = pickNextServer(attempt > 1)
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
            if next(values) then
                scanAllBooths(values)
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

scanAllBooths = function(values)
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
            local valueData = values[key]
            if not valueData then continue end

            local realValue = valueData.value
            local underVal  = valueData.under or 0
            -- threshold = value - under (under=0 means default: value - 30)
            local deduction = (underVal > 0) and underVal or 30
            local threshold = realValue - deduction
            local category  = valueData.category or "unknown"
            local sellPrice = parseNumber(item.price)
            local isUnderrap = threshold ~= nil and sellPrice ~= nil and sellPrice <= threshold

            table.insert(results, string.format(
                "%s | Price: %s | Value: %s | Cat: %s%s%s",
                item.name, item.price, tostring(realValue), category,
                item.finisher and " | FINISHER" or "",
                isUnderrap and " | <UNDERRAP>" or ""
            ))

            if isUnderrap then
                underrapCount += 1
                local profit = threshold - sellPrice
                local pctOff = math.floor((1 - sellPrice / threshold) * 100)
                sendWebhook({
                    embeds = {{
                        title = "🎯 UNDERRAP FOUND",
                        description = string.format("**%s** is selling **%d%%** below %s!", item.name, pctOff, underVal > 0 and "under threshold" or "value"),
                        color = 0x00FF88,
                        fields = {
                            { name = "📦 Item",       value = item.name,                                    inline = true },
                            { name = "💰 Price",      value = string.format("`%s`", tostring(item.price)),  inline = true },
                            { name = "💎 Value",      value = string.format("`%s`", tostring(realValue)),   inline = true },
                            { name = "🔻 Under",      value = string.format("`%s`", underVal > 0 and tostring(underVal) or "—"), inline = true },
                            { name = "📈 Profit",     value = string.format("`+%s`", tostring(profit)),     inline = true },
                            { name = "🏷️ Category",  value = category,                                     inline = true },
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
                -- Also POST to bot API for C++ dashboard
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
    Text = "Scan All Booths",
    Func = function()
        local values = loadValues()
        if not next(values) then
            Library:Notify({ Title = "Error", Description = "Failed to load values", Time = 5 })
            return
        end
        task.spawn(scanAllBooths, values)
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
