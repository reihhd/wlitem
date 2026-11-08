local CONFIG = {
    MAIN_ACCOUNT = "dl_cu",
    ENABLED = true,
    AIMBOT = true,
    AIMBOT_SMOOTHNESS = 0.15,
    MAX_RANGE = 200,
    CLASH_DISTANCE = 22,
    CLASH_SPEED = 0.01,
    NORMAL_SPEED = 0.05,
    ACCURACY = 2.0,
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local LastClick = 0
local LastBallHit = nil
local IsParrying = false
local BallsFolder = workspace:FindFirstChild("Balls") or workspace:WaitForChild("Balls", 5)

local NetworkStats = Stats:FindFirstChild("Network")
    and Stats.Network:FindFirstChild("ServerStatsItem")
    and Stats.Network.ServerStatsItem:FindFirstChild("Data Ping")

local smoothedSpeed = 0
local lastBallPos = nil
local lastBallPosTick = 0
local lastBallAddr = nil

local clashHlTimes = {}
local clashMode = false
local clashLastHlTick = 0
local clashStartTick = 0
local clashRearmAt = 0
local prevHighlighted = false
local hlOffSinceTick = 0

local CLASH_WINDOW = 2.0
local CLASH_TRIGGER_COUNT = 3
local CLASH_MAX_DURATION = 3.0
local CLASH_REARM_COOLDOWN = 1.5
local CLASH_EXIT_IDLE = 0.8
local CLASH_MIN_OFF = 0.025

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

local function getMainHRP()
    local main = Players:FindFirstChild(CONFIG.MAIN_ACCOUNT)
    if not main then return nil end
    local char = main.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

local function GetBall()
    if not BallsFolder then return nil end
    local children = BallsFolder:GetChildren()
    for i = 1, #children do
        local v = children[i]
        if v:GetAttribute("realBall") == true then return v end
    end
    for i = 1, #children do
        local v = children[i]
        if v:IsA("BasePart") and v.AssemblyLinearVelocity.Magnitude > 15 then return v end
    end
    return nil
end

local function IsTargeted(ball)
    if not ball then return false end
    local ok, target = pcall(ball.GetAttribute, ball, "target")
    if ok and typeof(target) == "string" and target == LocalPlayer.Name then
        return true
    end
    return false
end

local function IsEnemyNearby(myPos, range)
    local alive = workspace:FindFirstChild("Alive")
    if not alive then return false end
    for _, c in alive:GetChildren() do
        if c ~= LocalPlayer.Character then
            local hrp = c:FindFirstChild("HumanoidRootPart")
            if hrp then
                local dx = myPos.X - hrp.Position.X
                local dz = myPos.Z - hrp.Position.Z
                if math.sqrt(dx * dx + dz * dz) <= range then
                    return true
                end
            end
        end
    end
    return false
end

local function GetBallVelocity(ball)
    local zoomies = ball:FindFirstChild("zoomies")
    if zoomies then
        local ok, vel = pcall(function() return zoomies.VectorVelocity end)
        if ok and vel and vel.Magnitude > 0.5 then return vel end
    end
    return ball.AssemblyLinearVelocity
end

local function GetBallSpeed(ball, ballPos)
    local vel = GetBallVelocity(ball)
    local rawSpeed = vel.Magnitude

    local now = tick()
    if ball ~= lastBallAddr then
        lastBallAddr = ball
        lastBallPos = ballPos
        lastBallPosTick = now
        smoothedSpeed = rawSpeed
        return rawSpeed, vel
    end

    if lastBallPosTick > 0 then
        local dt = now - lastBallPosTick
        if dt > 0.001 and dt < 0.5 then
            local inst = (ballPos - lastBallPos).Magnitude / dt
            if inst < 5000 then
                smoothedSpeed = 0.4 * inst + 0.6 * smoothedSpeed
            end
        end
    end
    lastBallPos = ballPos
    lastBallPosTick = now

    local speed = rawSpeed > 0.5 and rawSpeed or smoothedSpeed
    if speed > 5000 then speed = 5000 end
    return speed, vel
end

local function ComputeRadius(ballSpeed, pingMs, accuracy)
    local pingThresh = math.clamp(pingMs / 100, 5, 17)
    local cappedDiff = math.min(math.max(ballSpeed - 9.5, 0), 650)
    local divBase = 2.4 + cappedDiff * 0.002
    local divMul = accuracy
    local speedComp = math.max(ballSpeed / (divBase * divMul), 9.5)
    return pingThresh + speedComp
end

local function getBlockButton()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local hotbar = pg:FindFirstChild("Hotbar")
    if not hotbar then return nil end
    return hotbar:FindFirstChild("Block")
end

local VIM = game:GetService("VirtualInputManager")

local function SendClick(isClashing, ball)
    if not CONFIG.ENABLED or IsParrying then return end
    local now = tick()
    local cd = isClashing and CONFIG.CLASH_SPEED or CONFIG.NORMAL_SPEED

    if not isClashing and LastBallHit == ball and (now - LastClick) < 0.5 then return end
    if (now - LastClick) < cd then return end

    IsParrying = true
    LastClick = now
    LastBallHit = ball

    local btn = getBlockButton()
    if btn then
        local pos = btn.AbsolutePosition + btn.AbsoluteSize / 2
        local x, y = pos.X, pos.Y

        local fired = pcall(function()
            VIM:SendTouchEvent(x, y, 0, game)
            task.defer(function()
                pcall(function() VIM:SendTouchEvent(x, y, 2, game) end)
            end)
        end)

        if not fired then
            fired = pcall(function()
                VIM:SendMouseButtonEvent(x, y, 0, true, game, 1)
                task.defer(function()
                    pcall(function() VIM:SendMouseButtonEvent(x, y, 0, false, game, 1) end)
                end)
            end)
        end

        if not fired then
            fired = pcall(function()
                firesignal(btn, "Activated")
            end)
        end

        if not fired then
            pcall(function()
                for _, c in pairs(getconnections(btn.Activated)) do c:Fire() end
            end)
        end
    end

    task.delay(cd, function() IsParrying = false end)
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AltFarmGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local oldGui = game:GetService("CoreGui"):FindFirstChild("AltFarmGui")
if oldGui then oldGui:Destroy() end
screenGui.Parent = game:GetService("CoreGui")

local mainFrame = Instance.new("Frame", screenGui)
mainFrame.Size = UDim2.new(0, 150, 0, 120)
mainFrame.Position = UDim2.new(0, 10, 0.5, -60)
mainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
mainFrame.BackgroundTransparency = 0.1
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)
Instance.new("UIStroke", mainFrame).Color = Color3.fromRGB(60, 60, 60)

local title = Instance.new("TextLabel", mainFrame)
title.Size = UDim2.new(1, 0, 0, 22)
title.BackgroundTransparency = 1
title.Text = "Alt Farm"
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextSize = 12

local function makeBtn(parent, yPos, label, default, callback)
    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(1, -16, 0, 28)
    btn.Position = UDim2.new(0, 8, 0, yPos)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.BorderSizePixel = 0
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    local state = default
    local function update()
        btn.Text = state and (label .. "  ✓") or (label .. "  ✗")
        btn.BackgroundColor3 = state and Color3.fromRGB(0, 140, 70) or Color3.fromRGB(80, 25, 25)
        btn.TextColor3 = Color3.new(1, 1, 1)
        callback(state)
    end
    update()
    btn.MouseButton1Click:Connect(function()
        state = not state
        update()
    end)
end

makeBtn(mainFrame, 26, "Auto Parry", CONFIG.ENABLED, function(v) CONFIG.ENABLED = v end)
makeBtn(mainFrame, 58, "Aimbot Main", CONFIG.AIMBOT, function(v) CONFIG.AIMBOT = v end)

local accLabel = Instance.new("TextLabel", mainFrame)
accLabel.Size = UDim2.new(1, -16, 0, 16)
accLabel.Position = UDim2.new(0, 8, 0, 92)
accLabel.BackgroundTransparency = 1
accLabel.Text = "Accuracy: " .. CONFIG.ACCURACY
accLabel.TextColor3 = Color3.fromRGB(160, 160, 160)
accLabel.Font = Enum.Font.Gotham
accLabel.TextSize = 10
accLabel.TextXAlignment = Enum.TextXAlignment.Left

local minimizeBtn = Instance.new("TextButton", mainFrame)
minimizeBtn.Size = UDim2.new(0, 18, 0, 18)
minimizeBtn.Position = UDim2.new(1, -22, 0, 2)
minimizeBtn.Text = "—"
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.TextSize = 11
minimizeBtn.TextColor3 = Color3.new(1, 1, 1)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
minimizeBtn.BorderSizePixel = 0
Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0, 4)
local minimized = false
minimizeBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    mainFrame.Size = minimized and UDim2.new(0, 150, 0, 22) or UDim2.new(0, 150, 0, 120)
    minimizeBtn.Text = minimized and "+" or "—"
end)

RunService.RenderStepped:Connect(function()
    if not CONFIG.AIMBOT then return end
    if not isAlive() then return end
    local myHrp = getHRP()
    if not myHrp then return end
    local mainHrp = getMainHRP()
    if not mainHrp then return end
    local targetPos = mainHrp.Position + Vector3.new(0, 1.5, 0)
    local targetCF = CFrame.lookAt(Camera.CFrame.Position, targetPos)
    Camera.CFrame = Camera.CFrame:Lerp(targetCF, CONFIG.AIMBOT_SMOOTHNESS)
end)

if BallsFolder then
    BallsFolder.ChildAdded:Connect(function()
        LastBallHit = nil
        IsParrying = false
        lastBallAddr = nil
        smoothedSpeed = 0
        clashMode = false
        clashHlTimes = {}
    end)
end

RunService.PostSimulation:Connect(function()
    if not CONFIG.ENABLED then return end
    if not isAlive() then return end

    local Root = getHRP()
    if not Root then return end

    local Ball = GetBall()
    if not Ball then return end

    local BallPos = Ball.Position
    local PlayerPos = Root.Position
    local Distance = (PlayerPos - BallPos).Magnitude

    if Distance > CONFIG.MAX_RANGE then return end

    local Speed, Velocity = GetBallSpeed(Ball, BallPos)
    if Speed < 1 then return end

    local dirToPlayer = (PlayerPos - BallPos).Unit
    local dot = dirToPlayer:Dot(Velocity.Unit)

    local Targeted = IsTargeted(Ball)

    local ballFrom = ""
    local okF, valF = pcall(Ball.GetAttribute, Ball, "from")
    if okF and typeof(valF) == "string" then ballFrom = valF end
    if ballFrom == CONFIG.MAIN_ACCOUNT then return end

    local nowTick = tick()
    local nowHL = Targeted
    local rose = nowHL and not prevHighlighted
    local fell = not nowHL and prevHighlighted

    if fell then hlOffSinceTick = nowTick end

    local debounceOK = (nowTick - hlOffSinceTick) >= CLASH_MIN_OFF
    local rearmOK = nowTick >= clashRearmAt
    local enemyNearby = IsEnemyNearby(PlayerPos, CONFIG.CLASH_DISTANCE)

    if rose and debounceOK and rearmOK and not clashMode and enemyNearby then
        table.insert(clashHlTimes, nowTick)
        clashLastHlTick = nowTick
        while #clashHlTimes > 0 and (nowTick - clashHlTimes[1]) > CLASH_WINDOW do
            table.remove(clashHlTimes, 1)
        end
        if #clashHlTimes >= CLASH_TRIGGER_COUNT then
            clashMode = true
            clashStartTick = nowTick
        end
    end

    if nowHL then clashLastHlTick = nowTick end

    if clashMode then
        local exitIdle = (nowTick - clashLastHlTick) > CLASH_EXIT_IDLE
        local exitMax = (nowTick - clashStartTick) > CLASH_MAX_DURATION
        local exitEnemy = not enemyNearby
        local exitHL = not nowHL and hlOffSinceTick > 0 and (nowTick - hlOffSinceTick) > 0.15
        if exitIdle or exitMax or exitEnemy or exitHL then
            clashMode = false
            clashHlTimes = {}
            clashRearmAt = nowTick + CLASH_REARM_COOLDOWN
        end
    end

    prevHighlighted = nowHL

    if not Targeted then
        LastBallHit = nil
        return
    end

    if dot < 0 then LastBallHit = nil; return end

    if clashMode then
        SendClick(true, Ball)
        return
    end

    local Ping = (NetworkStats and NetworkStats:GetValue() / 1000) or 0.04
    local PingMs = Ping * 1000
    local TriggerRadius = ComputeRadius(Speed, PingMs, CONFIG.ACCURACY)

    if TriggerRadius < 5 then TriggerRadius = 5 end
    if TriggerRadius > 300 then TriggerRadius = 300 end

    local ETA = Distance / Speed
    local etaThresh = TriggerRadius / Speed
    local leadTime = 0.012 + math.min(Speed / 50000, 0.008)
    etaThresh = etaThresh + leadTime

    local etaReady = dot > 0.25 and ETA <= etaThresh
    local insideRadius = Distance <= TriggerRadius

    if etaReady or insideRadius then
        SendClick(false, Ball)
    end
end)

LocalPlayer.CharacterAdded:Connect(function()
    LastBallHit = nil
    IsParrying = false
    lastBallAddr = nil
    smoothedSpeed = 0
    clashMode = false
    clashHlTimes = {}
    prevHighlighted = false
end)
