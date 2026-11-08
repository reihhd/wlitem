local CONFIG = {
    MAIN_ACCOUNT = "dl_cu",
    ENABLED = true,
    AIMBOT = true,
    AIMBOT_SMOOTHNESS = 0.15,
    VISUALS = true,
    MAX_RANGE = 200,
    CLASH_DISTANCE = 22,
    CLASH_SPEED = 0.01,
    NORMAL_SPEED = 0.05,
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Stats = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local LastClick = 0
local LastBallHit = nil
local IsParrying = false
local frameCounter = 0
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

local r, m
if CONFIG.VISUALS then
    for _, v in workspace:GetChildren() do
        if v.Name == "AltFarmCircle" then v:Destroy() end
    end
    r = Instance.new("Part")
    r.Name = "AltFarmCircle"
    r.Parent = workspace
    r.Anchored, r.CanCollide = true, false
    r.Transparency, r.Material = 0.3, Enum.Material.Neon
    m = Instance.new("SpecialMesh", r)
    m.MeshId = "rbxassetid://3270017"
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

local function ComputeV1Radius(ballSpeed, pingMs)
    local pingThresh = math.clamp(pingMs / 100, 5, 17)
    local cappedDiff = math.min(math.max(ballSpeed - 9.5, 0), 650)
    local divBase = 2.4 + cappedDiff * 0.002
    local speedComp = math.max(ballSpeed / divBase, 9.5)
    return pingThresh + speedComp
end

local function getBlockButton()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local hotbar = pg:FindFirstChild("Hotbar")
    if not hotbar then return nil end
    return hotbar:FindFirstChild("Block")
end

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
        local fired = false

        if not fired then
            fired = pcall(function()
                firesignal(btn, "Activated")
            end)
        end

        if not fired then
            fired = pcall(function()
                firesignal(btn, "MouseButton1Click")
            end)
        end

        if not fired then
            fired = pcall(function()
                fireclick(btn)
            end)
        end

        if not fired then
            pcall(function()
                for _, c in pairs(getconnections(btn.Activated)) do c:Fire() end
                for _, c in pairs(getconnections(btn.MouseButton1Click)) do c:Fire() end
            end)
        end
    end

    task.delay(cd, function() IsParrying = false end)
end

local function UpdateVisuals(root, distance, state)
    if not CONFIG.VISUALS or not r then return end
    r.CFrame = root.CFrame * CFrame.new(0, -2.6, 0) * CFrame.Angles(math.rad(90), 0, 0)
    local targetSize = math.clamp(distance * 0.8, 5, 65)
    m.Scale = m.Scale:Lerp(Vector3.new(targetSize, targetSize, 0.5), 0.5)
    if state == "clash" then
        r.Color = Color3.fromRGB(255, 0, 0)
        r.Transparency = 0.05
    elseif state == "target" then
        r.Color = Color3.fromRGB(0, 255, 255)
        r.Transparency = 0.1
    else
        r.Color = Color3.fromRGB(150, 240, 255)
        r.Transparency = 0.5
    end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AltFarmGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local oldGui = game:GetService("CoreGui"):FindFirstChild("AltFarmGui")
if oldGui then oldGui:Destroy() end
screenGui.Parent = game:GetService("CoreGui")

local mainFrame = Instance.new("Frame", screenGui)
mainFrame.Size = UDim2.new(0, 160, 0, 150)
mainFrame.Position = UDim2.new(0, 10, 0.5, -75)
mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
mainFrame.BackgroundTransparency = 0.15
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)
local stroke = Instance.new("UIStroke", mainFrame)
stroke.Color = Color3.fromRGB(80, 80, 80)
stroke.Thickness = 1

local title = Instance.new("TextLabel", mainFrame)
title.Size = UDim2.new(1, 0, 0, 24)
title.BackgroundTransparency = 1
title.Text = "Alt Farm"
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextSize = 13

local statusLabel = Instance.new("TextLabel", mainFrame)
statusLabel.Size = UDim2.new(1, -16, 0, 14)
statusLabel.Position = UDim2.new(0, 8, 0, 118)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "..."
statusLabel.TextColor3 = Color3.fromRGB(140, 140, 140)
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 10
statusLabel.TextXAlignment = Enum.TextXAlignment.Left

local function makeToggle(parent, yPos, label, default, callback)
    local row = Instance.new("Frame", parent)
    row.Size = UDim2.new(1, -16, 0, 26)
    row.Position = UDim2.new(0, 8, 0, yPos)
    row.BackgroundTransparency = 1
    local lbl = Instance.new("TextLabel", row)
    lbl.Size = UDim2.new(0.65, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = Color3.fromRGB(200, 200, 200)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    local btn = Instance.new("TextButton", row)
    btn.Size = UDim2.new(0.3, 0, 0, 20)
    btn.Position = UDim2.new(0.7, 0, 0.5, -10)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.BorderSizePixel = 0
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
    local state = default
    local function update()
        btn.Text = state and "ON" or "OFF"
        btn.BackgroundColor3 = state and Color3.fromRGB(0, 170, 80) or Color3.fromRGB(120, 30, 30)
        btn.TextColor3 = Color3.new(1, 1, 1)
        callback(state)
    end
    update()
    btn.MouseButton1Click:Connect(function()
        state = not state
        update()
    end)
    return function() return state end, function(v) state = v; update() end
end

makeToggle(mainFrame, 28, "Auto Parry", CONFIG.ENABLED, function(v) CONFIG.ENABLED = v end)
makeToggle(mainFrame, 58, "Aimbot Main", CONFIG.AIMBOT, function(v) CONFIG.AIMBOT = v end)
makeToggle(mainFrame, 88, "Visuals", CONFIG.VISUALS, function(v)
    CONFIG.VISUALS = v
    if r then r.Transparency = v and 0.3 or 1 end
end)

local minimizeBtn = Instance.new("TextButton", mainFrame)
minimizeBtn.Size = UDim2.new(0, 20, 0, 20)
minimizeBtn.Position = UDim2.new(1, -24, 0, 2)
minimizeBtn.Text = "—"
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.TextSize = 12
minimizeBtn.TextColor3 = Color3.new(1, 1, 1)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
minimizeBtn.BorderSizePixel = 0
Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0, 4)
local minimized = false
minimizeBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    mainFrame.Size = minimized and UDim2.new(0, 160, 0, 24) or UDim2.new(0, 160, 0, 150)
    minimizeBtn.Text = minimized and "+" or "—"
end)

task.spawn(function()
    local method = "none"
    if pcall(function() return firesignal end) and firesignal then
        method = "firesignal"
    elseif pcall(function() return fireclick end) and fireclick then
        method = "fireclick"
    elseif pcall(function() return getconnections end) and getconnections then
        method = "getconnections"
    end
    statusLabel.Text = "Method: " .. method
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
    if not CONFIG.ENABLED then
        if r then r.Transparency = 1 end
        return
    end
    if not isAlive() then
        if r then r.Transparency = 1 end
        return
    end

    local Root = getHRP()
    if not Root then
        if r then r.Transparency = 1 end
        return
    end

    local Ball = GetBall()
    if not Ball then
        if r then r.Transparency = 1 end
        return
    end

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

    frameCounter = frameCounter + 1
    if r and frameCounter % 2 == 0 then
        if Targeted then
            UpdateVisuals(Root, Distance, clashMode and "clash" or "target")
        else
            if r then r.Transparency = 1 end
        end
    end

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
    local TriggerRadius = ComputeV1Radius(Speed, PingMs)

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
