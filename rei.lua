local CONFIG = {
    MAIN_ACCOUNT = "dl_cu",
    MODE = "FARM", -- "FARM" = ke tengah, "STAY" = diam di pojok
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local Alive = workspace:WaitForChild("Alive")

local function getBallSpawnPos()
    local map = workspace:FindFirstChild("Map")
    if not map then return Vector3.new(0, 3, 0) end
    for _, child in map:GetChildren() do
        local bs = child:FindFirstChild("BALLSPAWN")
        if bs then
            if CONFIG.MODE == "FARM" then
                return bs.Position
            else
                return bs.Position + Vector3.new(50, 0, 50)
            end
        end
    end
    return CONFIG.MODE == "FARM" and Vector3.new(0, 3, 0) or Vector3.new(50, 3, 50)
end

local function moveToPos()
    local char = LocalPlayer.Character
    if not char then return end
    char:PivotTo(CFrame.new(getBallSpawnPos()))
end

local function applyImmortal(char)
    if not char then return end
    local hum = char:WaitForChild("Humanoid", 10)
    if not hum then return end

    if CONFIG.MODE == "STAY" then
        hum:GetPropertyChangedSignal("Health"):Connect(function()
            if hum.Health < hum.MaxHealth then
                hum.Health = hum.MaxHealth
            end
        end)
        pcall(function()
            hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
        end)
        char.AncestryChanged:Connect(function(_, newParent)
            if newParent ~= Alive then
                pcall(function() char.Parent = Alive end)
            end
        end)
    else
        pcall(function()
            hum:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
        end)
    end
end

ReplicatedStorage.Remotes.LocalTeleport.OnClientEvent:Connect(function()
    task.wait(0.05)
    moveToPos()
end)

Alive.ChildAdded:Connect(function(child)
    if child.Name ~= LocalPlayer.Name then return end
    task.wait(0.1)
    moveToPos()
end)

if LocalPlayer.Character then
    applyImmortal(LocalPlayer.Character)
    moveToPos()
end

LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.2)
    applyImmortal(char)
    moveToPos()
end)

-- GUI
local CoreGui = game:GetService("CoreGui")
local old = CoreGui:FindFirstChild("BotGui")
if old then old:Destroy() end

local sg = Instance.new("ScreenGui")
sg.Name = "BotGui"
sg.ResetOnSpawn = false
sg.Parent = CoreGui

local frame = Instance.new("Frame", sg)
frame.Size = UDim2.new(0, 140, 0, 80)
frame.Position = UDim2.new(0, 8, 0.5, -40)
frame.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
frame.BackgroundTransparency = 0.05
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(45, 45, 45)
stroke.Thickness = 1

local statusLbl = Instance.new("TextLabel", frame)
statusLbl.Size = UDim2.new(1, -12, 0, 20)
statusLbl.Position = UDim2.new(0, 6, 0, 6)
statusLbl.BackgroundTransparency = 1
statusLbl.Font = Enum.Font.GothamMedium
statusLbl.TextSize = 11
statusLbl.TextColor3 = Color3.fromRGB(180, 180, 180)
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Text = "status: ..."

local modeBtn = Instance.new("TextButton", frame)
modeBtn.Size = UDim2.new(1, -12, 0, 30)
modeBtn.Position = UDim2.new(0, 6, 0, 32)
modeBtn.Font = Enum.Font.GothamMedium
modeBtn.TextSize = 11
modeBtn.BorderSizePixel = 0
modeBtn.AutoButtonColor = false
Instance.new("UICorner", modeBtn).CornerRadius = UDim.new(0, 5)

local function renderModeBtn()
    if CONFIG.MODE == "FARM" then
        modeBtn.Text = "Mode: FARM"
        modeBtn.BackgroundColor3 = Color3.fromRGB(25, 100, 55)
        modeBtn.TextColor3 = Color3.fromRGB(200, 255, 220)
    else
        modeBtn.Text = "Mode: STAY"
        modeBtn.BackgroundColor3 = Color3.fromRGB(80, 60, 20)
        modeBtn.TextColor3 = Color3.fromRGB(255, 220, 150)
    end
end
renderModeBtn()

modeBtn.MouseButton1Click:Connect(function()
    CONFIG.MODE = CONFIG.MODE == "FARM" and "STAY" or "FARM"
    renderModeBtn()
    local char = LocalPlayer.Character
    if char then
        applyImmortal(char)
        moveToPos()
    end
end)

RunService.Heartbeat:Connect(function()
    local char = LocalPlayer.Character
    if not char then statusLbl.Text = "status: no char" return end
    if char.Parent == Alive then
        statusLbl.Text = "status: alive ✓"
    else
        statusLbl.Text = "status: dead..."
    end
end)
