local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local freeCamUI, camPos, rotX, rotY, camVel, defaultFOV, targetFOV
local conns, moveInput, fovInput = {}, {}, {}

local function safeDisconnect(c)
    if c and c.Connected then pcall(c.Disconnect, c) end
end

local function getChar()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function getHum(char)
    char = char or getChar()
    return char:FindFirstChildOfClass("Humanoid")
end

local function makeCircleBtn(text, pos, size, parent, callback)
    local btn = Instance.new("TextButton")
    btn.Size, btn.Position = size, pos
    btn.AnchorPoint = Vector2.new(0.5, 0.5)
    btn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    btn.BackgroundTransparency = 0.4
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Text, btn.Font, btn.TextSize = text, Enum.Font.GothamBold, 22
    btn.Parent = parent
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = btn
    btn.MouseButton1Down:Connect(function() callback(true) end)
    btn.MouseButton1Up:Connect(function() callback(false) end)
    return btn
end

local FreeCam = {}

function FreeCam:Enable()
    local cam = Workspace.CurrentCamera
    cam.CameraType = Enum.CameraType.Scriptable
    camPos = (getChar() and getChar():FindFirstChild("HumanoidRootPart") and getChar().HumanoidRootPart.Position) or Vector3.zero
    rotX, rotY, camVel = 0, 0, Vector3.zero
    
    -- ✅ Simpan FOV asli kamera
    defaultFOV = cam.FieldOfView
    targetFOV = defaultFOV

    freeCamUI = Instance.new("ScreenGui")
    freeCamUI.Name = "FreeCamUI"
    freeCamUI.ResetOnSpawn = false
    freeCamUI.IgnoreGuiInset = true
    freeCamUI.Parent = LocalPlayer:WaitForChild("PlayerGui")

    moveInput = {Forward=false, Back=false, Left=false, Right=false, Up=false, Down=false}
    fovInput = {Increase=false, Decrease=false}

    -- Movement Pad
    local dpadFrame = Instance.new("Frame")
    dpadFrame.Size = UDim2.fromScale(0.25, 0.25)
    dpadFrame.Position = UDim2.fromScale(0.2, 0.8)
    dpadFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    dpadFrame.BackgroundTransparency = 1
    dpadFrame.Parent = freeCamUI

    makeCircleBtn("▲", UDim2.fromScale(0.5, 0.2), UDim2.fromScale(0.25, 0.25), dpadFrame, function(s) moveInput.Forward = s end)
    makeCircleBtn("▼", UDim2.fromScale(0.5, 0.8), UDim2.fromScale(0.25, 0.25), dpadFrame, function(s) moveInput.Back = s end)
    makeCircleBtn("◀", UDim2.fromScale(0.2, 0.5), UDim2.fromScale(0.25, 0.25), dpadFrame, function(s) moveInput.Left = s end)
    makeCircleBtn("▶", UDim2.fromScale(0.8, 0.5), UDim2.fromScale(0.25, 0.25), dpadFrame, function(s) moveInput.Right = s end)
    makeCircleBtn("+", UDim2.fromScale(0.2, 0.2), UDim2.fromScale(0.2, 0.2), dpadFrame, function(s) moveInput.Up = s end)
    makeCircleBtn("-", UDim2.fromScale(0.8, 0.8), UDim2.fromScale(0.2, 0.2), dpadFrame, function(s) moveInput.Down = s end)

    -- FOV Pad
    local fovFrame = Instance.new("Frame")
    fovFrame.Size = UDim2.fromScale(0.1, 0.25)
    fovFrame.Position = UDim2.fromScale(0.9, 0.8)
    fovFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    fovFrame.BackgroundTransparency = 1
    fovFrame.Parent = freeCamUI

    makeCircleBtn("+", UDim2.fromScale(0.5, 0.3), UDim2.fromScale(0.7, 0.35), fovFrame, function(s) fovInput.Increase = s end)
    makeCircleBtn("-", UDim2.fromScale(0.5, 0.7), UDim2.fromScale(0.7, 0.35), fovFrame, function(s) fovInput.Decrease = s end)

    -- Touch Drag
    local isDragging, lastPos = false, nil
    conns.TouchStart = UIS.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.UserInputType == Enum.UserInputType.Touch and input.Position.X > cam.ViewportSize.X/2 then
            isDragging, lastPos = true, input.Position
        end
    end)
    conns.TouchEnd = UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then isDragging = false end
    end)
    conns.TouchMove = UIS.InputChanged:Connect(function(input, gpe)
        if isDragging and input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - lastPos
            lastPos = input.Position
            rotX -= delta.X * 0.2
            rotY = math.clamp(rotY - delta.Y * 0.2, -80, 80)
        end
    end)

    -- Render Loop
    conns.FreeCam = RunService.RenderStepped:Connect(function(dt)
        if fovInput.Increase then targetFOV = math.clamp(targetFOV + dt * 60, 0, 120) end
        if fovInput.Decrease then targetFOV = math.clamp(targetFOV - dt * 60, 0, 120) end
        
        -- ✅ Perbaikan: gunakan "=" bukan "+="
        cam.FieldOfView = cam.FieldOfView + (targetFOV - cam.FieldOfView) * dt * 10

        local yaw = CFrame.Angles(0, math.rad(rotX), 0)
        local pitch = CFrame.Angles(math.rad(rotY), 0, 0)
        local look = yaw * pitch

        local dir = Vector3.zero
        if moveInput.Forward then dir += look.LookVector end
        if moveInput.Back then dir -= look.LookVector end
        if moveInput.Left then dir -= look.RightVector end
        if moveInput.Right then dir += look.RightVector end
        if moveInput.Up then dir += Vector3.yAxis end
        if moveInput.Down then dir -= Vector3.yAxis end

        camVel = camVel:Lerp(dir * 40, dt * 5)
        camPos += camVel * dt
        cam.CFrame = CFrame.lookAt(camPos, camPos + look.LookVector)
    end)
end

function FreeCam:Disable()
    if freeCamUI then freeCamUI:Destroy() freeCamUI = nil end
    for _, c in pairs(conns) do safeDisconnect(c) end
    conns = {}
    local cam = Workspace.CurrentCamera
    cam.CameraType = Enum.CameraType.Custom
    cam.CameraSubject = getHum() or getChar()
    
    -- ✅ Balikin FOV ke nilai asli
    cam.FieldOfView = defaultFOV
end

return FreeCam
