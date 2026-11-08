local CONFIG = {
    MAIN_ACCOUNT = "dl_cu",
    PING_BASED = true,
    PING_OFFSET = 1.95,
    DISTANCE_TO_PARRY = 0.65,
    EMERGENCY_RADIUS = 20,
    CLASH_DISTANCE = 22,
    CLASH_SPEED = 0.01,
    NORMAL_SPEED = 0.05,
    MAX_RANGE = 200,
    ENABLED = true,
    AIMBOT = true,
    AIMBOT_SMOOTHNESS = 0.15,
    VISUALS = true,
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

local r, m
if CONFIG.VISUALS then
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
        if children[i]:GetAttribute("realBall") == true then return children[i] end
    end
    for i = 1, #children do
        if children[i]:IsA("BasePart") and children[i].AssemblyLinearVelocity.Magnitude > 15 then return children[i] end
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
        for _, c in pairs(getconnections(btn.Activated)) do c:Fire() end
        for _, c in pairs(getconnections(btn.MouseButton1Click)) do c:Fire() end
        for _, c in pairs(getconnections(btn.MouseButton1Down)) do c:Fire() end
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

local targetConnection = nil
local function watchBallTarget(ball)
    if targetConnection then targetConnection:Disconnect(); targetConnection = nil end
    if ball then
        targetConnection = ball:GetAttributeChangedSignal("target"):Connect(function()
            LastBallHit = nil
            IsParrying = false
        end)
    end
end

if BallsFolder then
    BallsFolder.ChildAdded:Connect(function()
        local ball = GetBall()
        if ball then
            watchBallTarget(ball)
            LastBallHit = nil
            IsParrying = false
        end
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

    local myName = LocalPlayer.Name
    local target = getBallTarget(Ball)
    if target ~= myName then
        if r then r.Transparency = 1 end
        return
    end

    if getBallFrom(Ball) == CONFIG.MAIN_ACCOUNT then return end

    local BallPos = Ball.Position
    local PlayerPos = Root.Position
    local Velocity = Ball.AssemblyLinearVelocity
    local Speed = Velocity.Magnitude
    local Distance = (PlayerPos - BallPos).Magnitude

    if Distance > CONFIG.MAX_RANGE then return end

    local dirToPlayer = (PlayerPos - BallPos).Unit
    local dot = dirToPlayer:Dot(Velocity.Unit)

    if dot < 0 then LastBallHit = nil end

    local IsClashing = Distance <= CONFIG.CLASH_DISTANCE

    frameCounter = frameCounter + 1
    if r and frameCounter % 2 == 0 then
        r.Transparency = 0.3
        UpdateVisuals(Root, Distance, IsClashing and "clash" or "target")
    end

    if IsClashing then
        SendClick(true, Ball)
    elseif dot > 0 then
        local Ping = (NetworkStats and NetworkStats.Value / 1000) or 0.04
        local TimeToHit = Distance / math.max(Speed, 1)
        local Threshold = CONFIG.DISTANCE_TO_PARRY + (Ping * CONFIG.PING_OFFSET)
        if Speed > 150 then Threshold = Threshold * 1.15 end
        if TimeToHit <= Threshold or Distance <= CONFIG.EMERGENCY_RADIUS then
            SendClick(false, Ball)
        end
    end
end)

LocalPlayer.CharacterAdded:Connect(function()
    LastBallHit = nil
    IsParrying = false
end)
