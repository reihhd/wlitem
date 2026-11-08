local WEBHOOK = "https://discord.com/api/webhooks/1556746057910853642/txaeSkpdpHl-o70N6qlL4GBf0-sKpHaEQIXAuHnSPnLO47AfCKruPC0ecuffu60Iraog"
local HttpService = game:GetService("HttpService")

local BallsFolder = workspace:FindFirstChild("Balls") or workspace:WaitForChild("Balls", 5)
if not BallsFolder then
    warn("[DumpBall] Balls folder not found")
    return
end

local function dumpBall(ball)
    local lines = {}
    table.insert(lines, "=== " .. ball:GetFullName() .. " ===")
    table.insert(lines, "ClassName: " .. ball.ClassName)

    if ball:IsA("BasePart") then
        table.insert(lines, "Position: " .. tostring(ball.Position))
        table.insert(lines, "Velocity: " .. tostring(ball.AssemblyLinearVelocity))
        table.insert(lines, "Transparency: " .. tostring(ball.Transparency))
        table.insert(lines, "CanCollide: " .. tostring(ball.CanCollide))
    end

    table.insert(lines, "")
    table.insert(lines, "-- Attributes --")
    local attrs = ball:GetAttributes()
    local count = 0
    for name, value in pairs(attrs) do
        table.insert(lines, string.format("  [%s] = %s (%s)", name, tostring(value), typeof(value)))
        count = count + 1
    end
    if count == 0 then
        table.insert(lines, "  (no attributes)")
    end

    table.insert(lines, "")
    table.insert(lines, "-- Children --")
    for _, child in ball:GetChildren() do
        local info = "  " .. child.Name .. " (" .. child.ClassName .. ")"
        table.insert(lines, info)
        local childAttrs = child:GetAttributes()
        for cName, cVal in pairs(childAttrs) do
            table.insert(lines, string.format("    [%s] = %s (%s)", cName, tostring(cVal), typeof(cVal)))
        end
    end

    return table.concat(lines, "\n")
end

local function dumpCharacter()
    local char = game.Players.LocalPlayer.Character
    if not char then return "(no character)" end
    local lines = {}
    table.insert(lines, "=== CHARACTER: " .. char:GetFullName() .. " ===")
    local attrs = char:GetAttributes()
    for name, value in pairs(attrs) do
        table.insert(lines, string.format("  [%s] = %s (%s)", name, tostring(value), typeof(value)))
    end
    local hl = char:FindFirstChild("Highlight")
    table.insert(lines, "Highlight: " .. tostring(hl ~= nil))
    return table.concat(lines, "\n")
end

local result = {}
table.insert(result, dumpCharacter())
table.insert(result, "")
for _, ball in BallsFolder:GetChildren() do
    table.insert(result, dumpBall(ball))
    table.insert(result, "")
end

local output = table.concat(result, "\n")

local function sendWebhook(content, username)
    local body = HttpService:JSONEncode({
        content = content,
        username = username or "BallDump"
    })
    local ok, err = pcall(function()
        request({
            Url = WEBHOOK,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = body
        })
    end)
    if not ok then
        pcall(function()
            http_request({
                Url = WEBHOOK,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = body
            })
        end)
    end
end

if #output > 1900 then
    local chunks = {}
    local current = ""
    for line in output:gmatch("[^\n]*\n?") do
        if #current + #line > 1900 then
            table.insert(chunks, current)
            current = ""
        end
        current = current .. line
    end
    if #current > 0 then table.insert(chunks, current) end

    for i, chunk in ipairs(chunks) do
        sendWebhook("```\n" .. chunk .. "\n```", "BallDump [" .. i .. "/" .. #chunks .. "]")
        task.wait(0.6)
    end
else
    sendWebhook("```\n" .. output .. "\n```")
end

print("[DumpBall] Sent to webhook!")
