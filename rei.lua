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
local UserInputService = game:GetService("UserInputService")
local Stats = game:GetService("Stats")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local LastClick = 0
local LastBallHit = nil
local IsParrying = false
local BallsFolder = workspace:FindFirstChild("Balls") or workspace:WaitForChild("Balls", 5)
local Alive = workspace:FindFirstChild("Alive")

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
local parried = false

local CLASH_WINDOW = 2.0
local CLASH_TRIGGER_COUNT = 3
local CLASH_MAX_DURATION = 3.0
local CLASH_REARM_COOLDOWN = 1.5
local CLASH_EXIT_IDLE = 0.8
local CLASH_MIN_OFF = 0.025

local _PARRY_PATCH = {
    keyTable = nil,
    transformFn = nil,
    parryHash = nil,
    parryRemote = nil,
    ready = false,
}

task.spawn(function()
    local ok, err = pcall(function()
        local Controllers = ReplicatedStorage:WaitForChild("Controllers", 15)
        if not Controllers then return end

        local SC
        for _, child in ipairs(Controllers:GetChildren()) do
            if child.Name:sub(1, 16) == "SwordsController" then
                SC = child
                break
            end
        end
        if not SC then return end

        local PRY = SC:WaitForChild("PRY", 15)
        if not PRY then return end

        local Parry_Function = require(PRY)
        local getupvals = debug.getupvalues or getupvalues
        if not getupvals then return end

        local ups = getupvals(Parry_Function)
        if not ups or #ups < 8 then return end

        _PARRY_PATCH.keyTable = ups[3]
        _PARRY_PATCH.transformFn = ups[4]
        _PARRY_PATCH.parryHash = ups[8]
    end)
    if not ok then warn("[PARRY] init error:", tostring(err)) end
end)

local _reverted = {}
local _original = {}

local function _is_valid(args)
    return #args == 8 and type(args[2]) == "string" and type(args[3]) == "string"
        and type(args[4]) == "number" and typeof(args[5]) == "CFrame"
        and type(args[6]) == "table" and type(args[7]) == "table"
        and type(args[8]) == "boolean"
end

local function _hook(remote)
    if not _reverted[remote] then
        if not _original[getrawmetatable(remote)] then
            _original[getrawmetatable(remote)] = true
            local _meta = getrawmetatable(remote)
            setreadonly(_meta, false)
            local _old = _meta.__index
            _meta.__index = function(self, key)
                if (key == "FireServer" and self:IsA("RemoteEvent")) or
                   (key == "InvokeServer" and self:IsA("RemoteFunction")) then
                    return function(_, ...)
                        local _arguments = {...}
                        if _is_valid(_arguments) then
                            if not _reverted[self] then
                                _reverted[self] = _arguments
                                _PARRY_PATCH.ready = true
                                _PARRY_PATCH.parryRemote = self
                            end
                        end
                        return _old(self, key)(_, unpack(_arguments))
                    end
                end
                return _old(self, key)
            end
            setreadonly(_meta, true)
        end
    end
end

for _, _remote in pairs(ReplicatedStorage:GetDescendants()) do
    if _remote:IsA("RemoteEvent") or _remote:IsA("RemoteFunction") then
        _hook(_remote)
    end
end

function _PARRY_PATCH.fire(curveCFrame, screenPositions, mouseLocation)
    if not _PARRY_PATCH.ready then return false end
    local kt = _PARRY_PATCH.keyTable
    if not kt then return false end
    local keyIndex = kt[1]
    local currentKey = kt[2] and kt[2][keyIndex]
    if not currentKey then return false end

    local tok, transformed = pcall(_PARRY_PATCH.transformFn, currentKey, "TIME")
    if not tok or not transformed then
        tok, transformed = pcall(_PARRY_PATCH.transformFn, currentKey)
        if not tok or not transformed then return false end
    end

    local serverTime = workspace:GetServerTimeNow() * 100
    local timeStr = tostring(math.floor(serverTime))
    local tc = {}
    for i = 1, #timeStr do
        local ki = (i - 1) % #transformed + 1
        local kb = string.byte(transformed, ki)
        local tb = (string.byte(timeStr, i) + i) % 256
        tc[i] = string.char(bit32.bxor(tb, kb))
    end
    local token = table.concat(tc)

    local fok = pcall(function()
        _PARRY_PATCH.parryRemote:FireServer(
            _PARRY_PATCH.parryHash,
            currentKey,
            token,
            0.5,
            curveCFrame,
            screenPositions,
            mouseLocation,
            false
        )
    end)
    return fok
end

local function isAlive()
    Alive = workspace:FindFirstChild("Alive")
    if not Alive then return false end
    local char = LocalPlayer.Character
    if not char then return false end
    return Alive:FindFirstChild(LocalPlayer.Name) == char
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
    if not Alive then return false end
    for _, c in Alive:GetChildren() do
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

local divisorMul = 0.7 + (CONFIG.ACCURACY - 1) * 0.0035353535353535

local function ComputeRadius(ballSpeed, pingMs)
    local pingThresh = math.clamp(pingMs / 10, 5, 17)
    local cappedDiff = math.min(math.max(ballSpeed - 9.5, 0), 650)
    local divBase = (2.4 + cappedDiff * 0.002) * divisorMul
    local speedComp = math.max(ballSpeed / divBase, 9.5)
    return pingThresh + speedComp
end

local function SendParry()
    if not CONFIG.ENABLED or IsParrying then return end

    IsParrying = true

    local cam = Camera
    local curveCF = cam.CFrame

    local screenPositions = {}
    if Alive then
        for _, entity in Alive:GetChildren() do
            if entity.PrimaryPart then
                local ok2, sp = pcall(function()
                    return cam:WorldToScreenPoint(entity.PrimaryPart.Position)
                end)
                if ok2 then
                    screenPositions[entity.Name] = sp
                end
            end
        end
    end

    local mouseLocation
    local ok, mouse = pcall(function()
        return UserInputService:GetMouseLocation()
    end)
    if ok and mouse then
        mouseLocation = {mouse.X, mouse.Y}
    else
        local vp = cam.ViewportSize
        mouseLocation = {vp.X / 2, vp.Y / 2}
    end

    _PARRY_PATCH.fire(curveCF, screenPositions, mouseLocation)

    task.delay(0.5, function() IsParrying = false end)
end

local CoreGui = game:GetService("CoreGui")
local oldGui = CoreGui:FindFirstChild("AltFarmGui")
if oldGui then oldGui:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AltFarmGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = CoreGui

local mainFrame = Instance.new("Frame", screenGui)
mainFrame.Size = UDim2.new(0, 130, 0, 90)
mainFrame.Position = UDim2.new(0, 8, 0.5, -45)
mainFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
mainFrame.BackgroundTransparency = 0.05
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 6)

local stroke = Instance.new("UIStroke", mainFrame)
stroke.Color = Color3.fromRGB(45, 45, 45)
stroke.Thickness = 1

local statusDot = Instance.new("Frame", mainFrame)
statusDot.Size = UDim2.new(0, 6, 0, 6)
statusDot.Position = UDim2.new(0, 8, 0, 8)
statusDot.BorderSizePixel = 0
statusDot.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
Instance.new("UICorner", statusDot).CornerRadius = UDim.new(1, 0)

task.spawn(function()
    while not _PARRY_PATCH.ready do task.wait(0.5) end
    statusDot.BackgroundColor3 = Color3.fromRGB(0, 180, 60)
end)

local function makeToggle(parent, yPos, label, default, callback)
    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(1, -12, 0, 30)
    btn.Position = UDim2.new(0, 6, 0, yPos)
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 11
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)

    local state = default
    local function render()
        btn.Text = label
        if state then
            btn.BackgroundColor3 = Color3.fromRGB(25, 100, 55)
            btn.TextColor3 = Color3.fromRGB(200, 255, 220)
        else
            btn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
            btn.TextColor3 = Color3.fromRGB(120, 120, 120)
        end
        callback(state)
    end
    render()
    btn.MouseButton1Click:Connect(function()
        state = not state
        render()
    end)
end

makeToggle(mainFrame, 20, "Parry", CONFIG.ENABLED, function(v) CONFIG.ENABLED = v end)
makeToggle(mainFrame, 54, "Aimbot", CONFIG.AIMBOT, function(v) CONFIG.AIMBOT = v end)

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
        parried = false
    end)
end

RunService.PreSimulation:Connect(function()
    if not CONFIG.ENABLED then return end
    if not _PARRY_PATCH.ready then return end
    if not isAlive() then return end

    local Root = getHRP()
    if not Root then return end

    local Ball = GetBall()
    if not Ball then return end

    local zoomies = Ball:FindFirstChild("zoomies")
    if not zoomies then return end

    if parried then return end

    Ball:GetAttributeChangedSignal("target"):Once(function()
        parried = false
    end)

    local BallPos = Ball.Position
    local PlayerPos = Root.Position
    local Distance = (PlayerPos - BallPos).Magnitude

    if Distance > CONFIG.MAX_RANGE then return end

    local Velocity = GetBallVelocity(Ball)
    local Speed = Velocity.Magnitude
    if Speed < 1 then return end

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

    if clashMode then
        SendParry()
        parried = true
        return
    end

    local Ping = (NetworkStats and NetworkStats:GetValue() / 10) or 4
    local TriggerRadius = ComputeRadius(Speed, Ping)

    if Distance <= TriggerRadius then
        SendParry()
        parried = true
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
    parried = false
end)
