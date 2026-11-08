local CONFIG = {
    MAIN_ACCOUNT = "dl_cu",
    PING_BASED = true,
    PING_OFFSET = 1.95,
    DISTANCE_TO_PARRY = 0.55,
    EMERGENCY_RADIUS = 10,
    MAX_RANGE = 200,
    PARRY_COOLDOWN = 0.5,
    SPEED_DIVISOR_MULTIPLIER = 1.1,
    ENABLED = true,
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Stats = game:GetService("Stats")
local Debris = game:GetService("Debris")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local lastParryTick = 0
local isParrying = false
local lastBallHit = nil
local previousVelocity = {}
local lerpRadians = 0
local curvingTime = tick()
local lastWarping = tick()
local tornadoTime = tick()

local NetworkStats = Stats:FindFirstChild("Network")
    and Stats.Network:FindFirstChild("ServerStatsItem")
    and Stats.Network.ServerStatsItem:FindFirstChild("Data Ping")

local function getPing()
    if NetworkStats then return NetworkStats:GetValue() / 1000 end
    return 0.04
end

local function getPingMs()
    if NetworkStats then return NetworkStats:GetValue() end
    return 40
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

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function doParry()
    if isParrying then return end
    local now = tick()
    if (now - lastParryTick) < CONFIG.PARRY_COOLDOWN then return end
    isParrying = true
    lastParryTick = now
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
    task.defer(function()
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
    end)
    task.delay(CONFIG.PARRY_COOLDOWN, function()
        isParrying = false
    end)
end

local function isCurvedBall(ball, hrp)
    if not ball then return false end
    local zoomies = ball:FindFirstChild("zoomies")
    if not zoomies then return false end

    local ping = getPingMs()
    local velocity = zoomies.VectorVelocity
    local ballDir = velocity.Unit
    local playerPos = hrp.Position
    local ballPos = ball.Position
    local direction = (playerPos - ballPos).Unit
    local dot = direction:Dot(ballDir)
    local speed = velocity.Magnitude
    local distance = (playerPos - ballPos).Magnitude
    local reachTime = distance / math.max(speed, 1) - (ping / 1000)

    table.insert(previousVelocity, velocity)
    if #previousVelocity > 4 then table.remove(previousVelocity, 1) end

    if ball:FindFirstChild("AeroDynamicSlashVFX") then
        Debris:AddItem(ball.AeroDynamicSlashVFX, 0)
        tornadoTime = tick()
    end

    local runtime = workspace:FindFirstChild("Runtime")
    if runtime and runtime:FindFirstChild("Tornado") then
        local duration = (runtime.Tornado:GetAttribute("TornadoTime") or 1) + 0.314
        if (tick() - tornadoTime) < duration then return true end
    end

    local speedThreshold = math.min(speed / 100, 40)
    local ballDistThreshold = 15 - math.min(distance / 1000, 15) + speedThreshold

    if speed > 160 and reachTime > (ping / 10 + 0.03) then
        if speed < 300 then
            ballDistThreshold = math.max(ballDistThreshold - 15, 15)
        elseif speed <= 600 then
            ballDistThreshold = math.max(ballDistThreshold - 17, 17)
        elseif speed <= 1000 then
            ballDistThreshold = math.max(ballDistThreshold - 19, 19)
        else
            ballDistThreshold = math.max(ballDistThreshold - 20, 20)
        end
    end

    if distance < ballDistThreshold then return false end

    local adjustedReachTime = reachTime + 0.03
    if speed < 300 then
        if (tick() - curvingTime) < (adjustedReachTime / 1.2) then return true end
    elseif speed < 450 then
        if (tick() - curvingTime) < (adjustedReachTime / 1.21) then return true end
    elseif speed < 600 then
        if (tick() - curvingTime) < (adjustedReachTime / 1.335) then return true end
    else
        if (tick() - curvingTime) < (adjustedReachTime / 1.5) then return true end
    end

    local dotThreshold = 0 - ping / 1000
    local dirDiff = (ballDir - velocity.Unit)
    local dirSimilarity = direction:Dot(dirDiff.Unit)
    if (dot - dirSimilarity) < dotThreshold then return true end

    local clampedDot = math.clamp(dot, -1, 1)
    local radians = math.deg(math.asin(clampedDot))
    lerpRadians = lerp(lerpRadians, radians, 0.8)

    if speed < 300 then
        if lerpRadians < 0.02 then lastWarping = tick() end
        if (tick() - lastWarping) < (adjustedReachTime / 1.19) then return true end
    else
        if lerpRadians < 0.018 then lastWarping = tick() end
        if (tick() - lastWarping) < (adjustedReachTime / 1.5) then return true end
    end

    if #previousVelocity == 4 then
        for i = 1, 2 do
            local prevDir = (ballDir - previousVelocity[i].Unit).Unit
            local prevDot = direction:Dot(prevDir)
            if (dot - prevDot) < dotThreshold then return true end
        end
    end

    local horizDir = Vector3.new(playerPos.X - ballPos.X, 0, playerPos.Z - ballPos.Z)
    if horizDir.Magnitude > 0 then
        horizDir = horizDir.Unit
        local horizBallDir = Vector3.new(ballDir.X, 0, ballDir.Z)
        if horizBallDir.Magnitude > 0 then
            horizBallDir = horizBallDir.Unit
            local backAngle = math.deg(math.acos(math.clamp((-horizDir):Dot(horizBallDir), -1, 1)))
            if backAngle < 60 then return true end
        end
    end

    return (dot < dotThreshold)
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
            previousVelocity = {}
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
    if isCurvedBall(ball, hrp) then return end
    if ball:FindFirstChild("ComboCounter") then return end

    local ping = getPing()
    local timeToHit = distance / speed
    local pingMs = getPingMs()
    local pingThreshold = math.clamp(pingMs / 100, 5, 17)
    local cappedSpeedDiff = math.min(math.max(speed - 9.5, 0), 650)
    local speedDivisorBase = 2.4 + cappedSpeedDiff * 0.002

    local effectiveMultiplier
    if speed < 200 then
        effectiveMultiplier = 0.7 + (math.random(40, 100) - 1) * (0.35 / 99)
    else
        effectiveMultiplier = 0.7 + (math.random(10, 100) - 1) * (0.35 / 99)
    end

    local parryAccuracy = pingThreshold + math.max(speed / (speedDivisorBase * effectiveMultiplier), 9.5)

    local predictionThreshold = CONFIG.DISTANCE_TO_PARRY
    if CONFIG.PING_BASED then predictionThreshold = predictionThreshold + (ping * CONFIG.PING_OFFSET) end
    if speed > 150 then predictionThreshold = predictionThreshold * 1.15 end

    if distance <= CONFIG.EMERGENCY_RADIUS or timeToHit <= predictionThreshold or distance <= parryAccuracy then
        doParry()
        lastBallHit = ball
    end
end)

LocalPlayer.CharacterAdded:Connect(function()
    lastBallHit = nil
    isParrying = false
    previousVelocity = {}
    lerpRadians = 0
end)
