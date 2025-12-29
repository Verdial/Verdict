-- FreeCam cinematic improvement
-- Perbaikan: smoothing rotasi & posisi, input mouse/keyboard, FOV easing,
-- restore MouseBehavior, perbaikan restore CameraSubject & FOV hanya jika enable sebelumnya
-- Bahasa: komentar bahasa Indonesia

local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local freeCamUI, camPos
local targetRotX, targetRotY, smoothRotX, smoothRotY
local camVel, moveInput, fovInput
local defaultFOV, targetFOV
local conns = {}
local mouseLocked = false
local prevMouseBehavior = nil

local function safeDisconnect(c)
    if c and c.Connected then
        pcall(c.Disconnect, c)
    end
end

local function getChar()
    return LocalPlayer and (LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait())
end

local function getHum(char)
    char = char or getChar()
    return char and char:FindFirstChildOfClass("Humanoid")
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
    if not LocalPlayer then return end
    local cam = Workspace.CurrentCamera
    if not cam then return end

    -- simpan FOV asli hanya saat enable
    defaultFOV = cam.FieldOfView
    targetFOV = defaultFOV

    -- init posisi & rotasi
    local char = getChar()
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    camPos = (hrp and hrp.Position) or (cam and cam.CFrame.Position) or Vector3.zero

    targetRotX, targetRotY = 0, 0 -- rotX = yaw (deg), rotY = pitch (deg)
    smoothRotX, smoothRotY = 0, 0
    camVel = Vector3.zero
    moveInput = {Forward=false, Back=false, Left=false, Right=false, Up=false, Down=false, Sprint=false, Slow=false}
    fovInput = {Increase=false, Decrease=false}

    -- cinematic params
    local sensitivity = 0.18            -- mouse/touch sensitivity
    local rotationSmoothing = 12       -- higher = snappier, lower = smoother
    local positionSmoothing = 8
    local baseSpeed = 32
    local sprintMul = 2.2
    local slowMul = 0.35
    local maxPitch = 88

    -- UI controls (touch-friendly)
    freeCamUI = Instance.new("ScreenGui")
    freeCamUI.Name = "FreeCamUI"
    freeCamUI.ResetOnSpawn = false
    freeCamUI.IgnoreGuiInset = true
    freeCamUI.Parent = LocalPlayer:WaitForChild("PlayerGui")

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

    local fovFrame = Instance.new("Frame")
    fovFrame.Size = UDim2.fromScale(0.1, 0.25)
    fovFrame.Position = UDim2.fromScale(0.9, 0.8)
    fovFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    fovFrame.BackgroundTransparency = 1
    fovFrame.Parent = freeCamUI

    makeCircleBtn("+", UDim2.fromScale(0.5, 0.3), UDim2.fromScale(0.7, 0.35), fovFrame, function(s) fovInput.Increase = s end)
    makeCircleBtn("-", UDim2.fromScale(0.5, 0.7), UDim2.fromScale(0.7, 0.35), fovFrame, function(s) fovInput.Decrease = s end)

    -- store previous mouse behavior to restore later
    prevMouseBehavior = UIS.MouseBehavior

    -- input handlers
    local isDragging = false
    local lastPos = nil

    conns.InputBegan = UIS.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            -- right click to look around (lock mouse)
            mouseLocked = true
            lastPos = UIS:GetMouseLocation()
            -- lock center to avoid leaving window
            pcall(function() UIS.MouseBehavior = Enum.MouseBehavior.LockCenter end)
        elseif input.UserInputType == Enum.UserInputType.Touch and input.Position.X > Workspace.CurrentCamera.ViewportSize.X/2 then
            isDragging = true
            lastPos = input.Position
        elseif input.UserInputType == Enum.UserInputType.Keyboard then
            local k = input.KeyCode
            if k == Enum.KeyCode.W then moveInput.Forward = true end
            if k == Enum.KeyCode.S then moveInput.Back = true end
            if k == Enum.KeyCode.A then moveInput.Left = true end
            if k == Enum.KeyCode.D then moveInput.Right = true end
            if k == Enum.KeyCode.E or k == Enum.KeyCode.Space then moveInput.Up = true end
            if k == Enum.KeyCode.Q or k == Enum.KeyCode.LeftControl then moveInput.Down = true end
            if k == Enum.KeyCode.LeftShift or k == Enum.KeyCode.RightShift then moveInput.Sprint = true end
            if k == Enum.KeyCode.LeftAlt or k == Enum.KeyCode.RightAlt then moveInput.Slow = true end
        end
    end)

    conns.InputEnded = UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            mouseLocked = false
            pcall(function() UIS.MouseBehavior = prevMouseBehavior end)
        elseif input.UserInputType == Enum.UserInputType.Touch then
            isDragging = false
        elseif input.UserInputType == Enum.UserInputType.Keyboard then
            local k = input.KeyCode
            if k == Enum.KeyCode.W then moveInput.Forward = false end
            if k == Enum.KeyCode.S then moveInput.Back = false end
            if k == Enum.KeyCode.A then moveInput.Left = false end
            if k == Enum.KeyCode.D then moveInput.Right = false end
            if k == Enum.KeyCode.E or k == Enum.KeyCode.Space then moveInput.Up = false end
            if k == Enum.KeyCode.Q or k == Enum.KeyCode.LeftControl then moveInput.Down = false end
            if k == Enum.KeyCode.LeftShift or k == Enum.KeyCode.RightShift then moveInput.Sprint = false end
            if k == Enum.KeyCode.LeftAlt or k == Enum.KeyCode.RightAlt then moveInput.Slow = false end
        end
    end)

    conns.InputChanged = UIS.InputChanged:Connect(function(input, gpe)
        if gpe then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement and mouseLocked then
            local delta = UIS:GetMouseLocation() - (lastPos or UIS:GetMouseLocation())
            lastPos = UIS:GetMouseLocation()
            targetRotX = targetRotX - delta.X * sensitivity
            targetRotY = math.clamp(targetRotY - delta.Y * sensitivity, -maxPitch, maxPitch)
        elseif input.UserInputType == Enum.UserInputType.Touch and isDragging then
            local delta = input.Position - (lastPos or input.Position)
            lastPos = input.Position
            targetRotX = targetRotX - delta.X * (sensitivity * 0.9)
            targetRotY = math.clamp(targetRotY - delta.Y * (sensitivity * 0.9), -maxPitch, maxPitch)
        elseif input.UserInputType == Enum.UserInputType.MouseWheel then
            -- mouse wheel to change FOV quickly
            targetFOV = math.clamp(targetFOV - input.Position.Z * 2, 8, 140)
        end
    end)

    -- allow mouse to change without locking (also update on touch)
    conns.TouchStart = UIS.TouchStarted:Connect(function(input, gpe)
        -- handled by InputBegan/InputChanged; kept for compatibility
    end)

    -- main update loop
    conns.FreeCam = RunService.RenderStepped:Connect(function(dt)
        -- FOV handling (smooth)
        if fovInput.Increase then targetFOV = math.clamp(targetFOV + dt * 60, 8, 140) end
        if fovInput.Decrease then targetFOV = math.clamp(targetFOV - dt * 60, 8, 140) end
        cam.FieldOfView = cam.FieldOfView + (targetFOV - cam.FieldOfView) * math.clamp(dt * 8, 0, 1)

        -- smooth rotation interpolation
        local tRot = math.clamp(1 - math.exp(-rotationSmoothing * dt), 0, 1)
        smoothRotX = smoothRotX + (targetRotX - smoothRotX) * tRot
        smoothRotY = smoothRotY + (targetRotY - smoothRotY) * tRot

        -- build look CFrame from yaw (rotX) and pitch (rotY)
        local yaw = math.rad(smoothRotX)
        local pitch = math.rad(smoothRotY)
        -- yaw around Y, pitch around X -> CFrame.Angles(pitch, yaw, 0)
        local lookCFrame = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
        local lookVector = (lookCFrame * CFrame.new(0, 0, -1)).Position - (lookCFrame * CFrame.new()).Position
        local rightVector = (lookCFrame * CFrame.new(1, 0, 0)).Position - (lookCFrame * CFrame.new()).Position
        local upVector = Vector3.yAxis

        -- movement direction from inputs
        local dir = Vector3.zero
        if moveInput.Forward then dir = dir + lookVector end
        if moveInput.Back then dir = dir - lookVector end
        if moveInput.Left then dir = dir - rightVector end
        if moveInput.Right then dir = dir + rightVector end
        if moveInput.Up then dir = dir + upVector end
        if moveInput.Down then dir = dir - upVector end

        -- normalize direction to keep consistent speed on diagonals
        if dir.Magnitude > 0 then dir = dir.Unit end

        -- speed adjustments
        local currentSpeed = baseSpeed
        if moveInput.Sprint then currentSpeed = currentSpeed * sprintMul end
        if moveInput.Slow then currentSpeed = currentSpeed * slowMul end

        -- apply smoothing to velocity for inertia
        local desiredVel = dir * currentSpeed
        camVel = camVel:Lerp(desiredVel, math.clamp(dt * positionSmoothing, 0, 1))
        camPos = camPos + camVel * dt

        -- small cinematic offset (tilt/dolly) based on velocity
        local lateral = Vector3.new(camVel.X, 0, camVel.Z)
        local dollyOffset = -lateral.Unit * math.clamp(lateral.Magnitude / 80, 0, 0.6) * 0.5
        if lateral.Magnitude == 0 then dollyOffset = Vector3.zero end

        -- set camera CFrame with subtle pitch/roll based on movement for cinematic feel
        local finalCFrame = CFrame.lookAt(camPos + dollyOffset, camPos + dollyOffset + lookVector)
        cam.CFrame = cam.CFrame:Lerp(finalCFrame, math.clamp(1 - math.exp(-12 * dt), 0, 1))
    end)

    -- switch camera type to scriptable
    cam.CameraType = Enum.CameraType.Scriptable
end

function FreeCam:Disable()
    -- destroy UI
    if freeCamUI then
        freeCamUI:Destroy()
        freeCamUI = nil
    end

    -- disconnect all connections
    for _, c in pairs(conns) do safeDisconnect(c) end
    conns = {}

    local cam = Workspace.CurrentCamera
    if cam then
        cam.CameraType = Enum.CameraType.Custom
        -- restore CameraSubject properly (humanoid preferred)
        local humanoid = getHum()
        if humanoid then
            cam.CameraSubject = humanoid
        else
            local char = getChar()
            if char then
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    cam.CFrame = CFrame.new(hrp.Position) -- best-effort
                end
            end
        end

        -- hanya balikin FOV kalau sebelumnya Enable pernah dijalankan
        if defaultFOV then
            cam.FieldOfView = defaultFOV
            defaultFOV = nil
            targetFOV = nil
        end
    end

    -- restore mouse behavior if we changed it
    if prevMouseBehavior then
        pcall(function() UIS.MouseBehavior = prevMouseBehavior end)
        prevMouseBehavior = nil
    end
end

return FreeCam
