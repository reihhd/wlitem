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
    for _, child in ball:GetChildren() dolocal BallsFolder = workspace:FindFirstChild("Balls") or workspace:WaitForChild("Balls", 5)
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
        if child:IsA("BasePart") then
            info = info .. " Pos=" .. tostring(child.Position)
        end
        table.insert(lines, info)

        local childAttrs = child:GetAttributes()
        for cName, cVal in pairs(childAttrs) do
            table.insert(lines, string.format("    [%s] = %s (%s)", cName, tostring(cVal), typeof(cVal)))
        end
    end

    return table.concat(lines, "\n")
end

local result = {}
for _, ball in BallsFolder:GetChildren() do
    table.insert(result, dumpBall(ball))
    table.insert(result, "\n")
end

local output = table.concat(result, "\n")

if setclipboard then
    setclipboard(output)
    print("[DumpBall] Copied to clipboard!")
else
    print("[DumpBall] setclipboard not available, printing:")
end
print(output)

        local info = "  " .. child.Name .. " (" .. child.ClassName .. ")"
        if child:IsA("BasePart") then
            info = info .. " Pos=" .. tostring(child.Position)
        end
        table.insert(lines, info)

        local childAttrs = child:GetAttributes()
        for cName, cVal in pairs(childAttrs) do
            table.insert(lines, string.format("    [%s] = %s (%s)", cName, tostring(cVal), typeof(cVal)))
        end
    end

    return table.concat(lines, "\n")
end

local result = {}
for _, ball in BallsFolder:GetChildren() do
    table.insert(result, dumpBall(ball))
    table.insert(result, "\n")
end

local output = table.concat(result, "\n")

if setclipboard then
    setclipboard(output)
    print("[DumpBall] Copied to clipboard!")
else
    print("[DumpBall] setclipboard not available, printing:")
end
print(output)
