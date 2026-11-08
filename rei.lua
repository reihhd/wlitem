local CONFIG = {
    MAIN_ACCOUNT = "dl_cu",
    PING_BASED = true,
    PING_OFFSET = 1.95,
    DISTANCE_TO_PARRY = 0.55,
    EMERGENCY_RADIUS = 20,
    MAX_RANGE = 200,
    PARRY_COOLDOWN = 0.5,
    ENABLED = true,
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Stats = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer
local lastParryTick = 0
local isParrying = false
local lastBallHit = nil

local NetworkStats = Stats:FindFirstChild("Network")
    and Stats.Network:FindFirstChild("ServerStatsItem")
    and Stats.Network.ServerStatsItem:FindFirstChild("Data Ping")

local function getPing()
    if NetworkStats then return NetworkStats:GetValue() / 1000 end
    return 0.04
end

local function getBallsFolder()
    return workspace:FindFirstChild("Balls")
end

local function isAlive()
    local alive = workspace:FindFirstChild("Alive")
    if not alive then return false end
    local char = LocalPlayer.Character
    if not char then return false end
    return alive:FindFirstChild(LocalPlayer.Name) == char
end

local function getHRP()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

local function GetBall()
    local folder = getBallsFolder()
    if not folder then return nil end
    for _, v in folder:GetChildren() do
        if v:GetAttribute("realBall") == true then return v end
    end
    for _, v in folder:GetChildren() do
        if v:IsA("BasePart") and v.AssemblyLinearVelocity.Magnitude > 15 then return v end
    end
    return nil
end

local function getBallTarget(ball)
    local ok, val = pcall(ball.GetAttribute, ball, "target")
    if ok and typeof(val) == "string" then return val end
    return ""
end

local function getBallFrom(ball)
    local ok, val = pcall(ball.GetAttribute, ball, "from")
    if ok and typeof(val) == "string" then return val end
    return ""
end

local function getBlockButton()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local hotbar = pg:FindFirstChild("Hotbar")
    if not hotbar then return nil end
    return hotbar:FindFirstChild("Block")
end

local function doParry()
    if isParrying then return end
    local now = tick()
    if (now - lastParryTick) < CONFIG.PARRY_COOLDOWN then return end
    isParrying = true
    lastParryTick = now

    local btn = getBlockButton()
    if btn then
        for _, c in pairs(getconnections(btn.Activated)) do c:Fire() end
        for _, c in pairs(getconnections(btn.MouseButton1Click)) do c:Fire() end
        for _, c in pairs(getconnections(btn.MouseButton1Down)) do c:Fire() end
    end

    task.delay(CONFIG.PARRY_COOLDOWN, function()
        isParrying = false
    end)
end

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.L then
        CONFIG.ENABLED = not CONFIG.ENABLED
    end
end)

local targetConnection = nil

local function watchBallTarget(ball)
    if targetConnection then targetConnection:Disconnect(); targetConnection = nil end
    if ball then
        targetConnection = ball:GetAttributeChangedSignal("target"):Connect(function()
            lastBallHit = nil
            isParrying = false
        end)
    end
end

local ballsFolder = getBallsFolder()
if ballsFolder then
    ballsFolder.ChildAdded:Connect(function()
        local ball = GetBall()
        if ball then
            watchBallTarget(ball)
            lastBallHit = nil
            isParrying = false
        end
    end)
end

RunService.PostSimulation:Connect(function()
    if not CONFIG.ENABLED then return end
    if not isAlive() then return end

    local hrp = getHRP()
    if not hrp then return end

    local ball = GetBall()
    if not ball or not ball:IsA("BasePart") then return end

    if getBallTarget(ball) ~= LocalPlayer.Name then return end
    if getBallFrom(ball) == CONFIG.MAIN_ACCOUNT then return end

    local ballPos = ball.Position
    local playerPos = hrp.Position
    local distance = (playerPos - ballPos).Magnitude
    if distance > CONFIG.MAX_RANGE then return end

    local velocity
    local zoomies = ball:FindFirstChild("zoomies")
    if zoomies then velocity = zoomies.VectorVelocity else velocity = ball.AssemblyLinearVelocity end

    local speed = velocity.Magnitude
    if speed < 1 then return end

    local dirToPlayer = (playerPos - ballPos).Unit
    local dot = dirToPlayer:Dot(velocity.Unit)

    if dot < 0 then lastBallHit = nil; return end
    if lastBallHit == ball then return end

    local ping = getPing()
    local timeToHit = distance / speed

    local predictionThreshold = CONFIG.DISTANCE_TO_PARRY
    if CONFIG.PING_BASED then predictionThreshold = predictionThreshold + (ping * CONFIG.PING_OFFSET) end
    if speed > 150 then predictionThreshold = predictionThreshold * 1.15 end

    if distance <= CONFIG.EMERGENCY_RADIUS or timeToHit <= predictionThreshold then
        doParry()
        lastBallHit = ball
    end
end)

LocalPlayer.CharacterAdded:Connect(function()
    lastBallHit = nil
    isParrying = false
end)
