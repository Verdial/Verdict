-- Cleanup
if _G.VerdictWindUI then
    _G.VerdictWindUI:Unload()
    _G.VerdictWindUI = nil
end

-- Services
local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local UIS         = game:GetService("UserInputService")
local Lighting    = game:GetService("Lighting")
local Workspace   = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

-- State
local conns, flags, savedSlots = {}, {}, table.create(5)
local originalLighting, freeCamUI = {}, nil
local camPos, rotX, rotY, camVel = nil, 0, 0, Vector3.zero
local defaultFOV, targetFOV, fovInput = 70, 70, {Increase=false, Decrease=false}
local moveInput = {Forward=false, Back=false, Left=false, Right=false, Up=false, Down=false}

-- Helpers
local function safeDisconnect(c)
    if c and c.Connected then pcall(c.Disconnect, c) end
end

local function clearAll()
    for k, v in pairs(conns) do
        safeDisconnect(v)
        conns[k] = nil
    end
end

local function getChar()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function getHum(char)
    char = char or getChar()
    return char:FindFirstChildOfClass("Humanoid")
end

local function getHRP(char)
    char = char or getChar()
    return char:FindFirstChild("HumanoidRootPart")
end

local function sortedPlayers()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            list[#list+1] = p.Name
        end
    end
    table.sort(list)
    return list
end

local function restoreLighting()
    for k, v in pairs(originalLighting) do
        Lighting[k] = v
    end
end

local function teleportTo(cf)
    local hrp = getHRP()
    if hrp then hrp.CFrame = cf end
end

-- UI Init
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
WindUI:ToggleAcrylic(false)

local Window = WindUI:CreateWindow({
    Title = "Verdict",
    Author = "Just a simple script ♡",
    Icon = "smartphone",
    Size = UDim2.fromOffset(360, 400),
    Theme = "Dark",
    SideBarWidth = 120,
    Draggable = false,
})

-- Main Tab
local MainTab = Window:Tab({Title = "Main", Icon = "zap"})

-- GodMode
MainTab:Toggle({
    Title = "GodMode",
    Default = false,
    Callback = function(v)
        flags.God = v
        safeDisconnect(conns.God)
        local hum = getHum()
        if not hum then return end
        if v then
            conns.God = hum.HealthChanged:Connect(function()
                if hum.Health <= 0 then
                    task.wait()
                    hum.Health = hum.MaxHealth
                end
            end)
        end
    end
})

-- Noclip
MainTab:Toggle({
    Title = "No Clip",
    Default = false,
    Callback = function(v)
        flags.noclip = v
        safeDisconnect(conns.Noclip)
        if v then
            conns.Noclip = RunService.Stepped:Connect(function()
                for _, part in ipairs(getChar():GetChildren()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                    end
                end
            end)
        else
            for _, part in ipairs(getChar():GetChildren()) do
                if part:IsA("BasePart") then
                    part.CanCollide = true
                end
            end
        end
    end
})

-- Infinite Jump
MainTab:Toggle({
    Title = "Infinite Jump",
    Default = false,
    Callback = function(v)
        flags.infiniteJump = v
        safeDisconnect(conns.infiniteJump)
        if v then
            conns.infiniteJump = UIS.JumpRequest:Connect(function()
                local hum = getHum()
                if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
            end)
        end
    end
})

-- Fullbright
MainTab:Toggle({
    Title = "Fullbright",
    Default = false,
    Callback = function(v)
        safeDisconnect(conns.Fullbright)
        if v then
            originalLighting = {
                Brightness    = Lighting.Brightness,
                ClockTime     = Lighting.ClockTime,
                FogEnd        = Lighting.FogEnd,
                GlobalShadows = Lighting.GlobalShadows,
                Ambient       = Lighting.Ambient,
            }
            conns.Fullbright = RunService.RenderStepped:Connect(function()
                Lighting.Brightness = 2
                Lighting.ClockTime = 14
                Lighting.FogEnd = 1e9
                Lighting.GlobalShadows = false
                Lighting.Ambient = Color3.new(1, 1, 1)
            end)
        else
            restoreLighting()
        end
    end
})

-- Click Teleport
MainTab:Toggle({
    Title = "Click Teleport",
    Default = false,
    Callback = function(v)
        flags.clickTeleport = v
        safeDisconnect(conns.clickTeleport)
        if v then
            local mouse = LocalPlayer:GetMouse()
            conns.clickTeleport = mouse.Button1Down:Connect(function()
                if mouse.Hit then
                    teleportTo(CFrame.new(mouse.Hit.Position + Vector3.new(0, 5, 0)))
                end
            end)
        end
    end
})

-- Teleport Tab
local TeleportTab = Window:Tab({Title = "Teleport", Icon = "map"})
local selectedPlayerName
local TeleportDropdown = TeleportTab:Dropdown({
    Title = "Pilih Pemain",
    Values = sortedPlayers(),
    Searchable = true,
    Callback = function(opt) selectedPlayerName = opt end
})

TeleportTab:Button({
    Title = "Teleport ke Pemain",
    Callback = function()
        local target = selectedPlayerName and Players:FindFirstChild(selectedPlayerName)
        local targetHRP = target and getHRP(target.Character)
        if targetHRP then
            teleportTo(targetHRP.CFrame + Vector3.new(0, 3, 0))
        end
    end
})

TeleportTab:Button({
    Title = "Refresh List",
    Callback = function()
        local list = sortedPlayers()
        TeleportDropdown:Refresh(list)
        if selectedPlayerName and table.find(list, selectedPlayerName) then
            TeleportDropdown:Select(selectedPlayerName)
        end
    end
})

-- Misc Tab
local MiscTab = Window:Tab({Title = "Misc", Icon = "eye"})
local spectateTargetName
local slotSelected = 1

-- Spectate
local SpectateDropdown = MiscTab:Dropdown({
    Title = "Spectate Player",
    Values = sortedPlayers(),
    Searchable = true,
    Callback = function(opt) spectateTargetName = opt end
})

MiscTab:Button({
    Title = "Mulai Spectate",
    Callback = function()
        local target = spectateTargetName and Players:FindFirstChild(spectateTargetName)
        if target and target.Character then
            Workspace.CurrentCamera.CameraSubject = target.Character
        end
    end
})

MiscTab:Button({
    Title = "Berhenti Spectate",
    Callback = function()
        Workspace.CurrentCamera.CameraSubject = getHum() or getChar()
    end
})

MiscTab:Button({
    Title = "Refresh List",
    Callback = function()
        local list = sortedPlayers()
        SpectateDropdown:Refresh(list)
        if spectateTargetName and table.find(list, spectateTargetName) then
            SpectateDropdown:Select(spectateTargetName)
        end
    end
})

-- Save/Load Position
MiscTab:Dropdown({
    Title = "Pilih Slot",
    Values = {"1","2","3","4","5"},
    Value = "1",
    Callback = function(opt) slotSelected = tonumber(opt) end
})

MiscTab:Button({
    Title = "Save Pos",
    Callback = function()
        local hrp = getHRP()
        if hrp then savedSlots[slotSelected] = hrp.Position end
    end
})

MiscTab:Button({
    Title = "Teleport Pos",
    Callback = function()
        local pos = savedSlots[slotSelected]
        if pos then teleportTo(CFrame.new(pos + Vector3.new(0, 5, 0))) end
    end
})

MiscTab:Button({Title = "Clear Slot", Callback = function() savedSlots[slotSelected] = nil end})
MiscTab:Button({Title = "Clear All Slots", Callback = function() table.clear(savedSlots) end})

-- FreeCam
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

local function enableFreeCam()
    local cam = Workspace.CurrentCamera
    cam.CameraType = Enum.CameraType.Scriptable
    camPos = (getHRP() and getHRP().Position) or Vector3.zero
    rotX, rotY, camVel = 0, 0, Vector3.zero
    defaultFOV = cam.FieldOfView
    targetFOV = defaultFOV

    freeCamUI = Instance.new("ScreenGui")
    freeCamUI.Name = "FreeCamUI"
    freeCamUI.ResetOnSpawn = false
    freeCamUI.IgnoreGuiInset = true
    freeCamUI.Parent = LocalPlayer:WaitForChild("PlayerGui")

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
        -- Update FOV
        if fovInput.Increase then targetFOV = math.clamp(targetFOV + dt * 60, 0, 120) end
        if fovInput.Decrease then targetFOV = math.clamp(targetFOV - dt * 60, 0, 120) end
        cam.FieldOfView += (targetFOV - cam.FieldOfView) * dt * 10

        -- Rotation
        local yaw = CFrame.Angles(0, math.rad(rotX), 0)
        local pitch = CFrame.Angles(math.rad(rotY), 0, 0)
        local look = yaw * pitch

        -- Movement
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

local function disableFreeCam()
    if freeCamUI then freeCamUI:Destroy() freeCamUI = nil end
    safeDisconnect(conns.FreeCam)
    safeDisconnect(conns.TouchStart)
    safeDisconnect(conns.TouchEnd)
    safeDisconnect(conns.TouchMove)
    Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
    Workspace.CurrentCamera.CameraSubject = getHum() or getChar()
    Workspace.CurrentCamera.FieldOfView = defaultFOV
end

MiscTab:Toggle({
    Title = "Free Cam",
    Default = false,
    Callback = function(v) if v then enableFreeCam() else disableFreeCam() end end
})

-- Unload Logic
function Window:Unload()
    clearAll()
    if freeCamUI then freeCamUI:Destroy() freeCamUI = nil end
    Workspace.CurrentCamera.CameraSubject = getHum() or getChar()
    Workspace.CurrentCamera.FieldOfView = defaultFOV
    _G.VerdictWindUI = nil
end

_G.VerdictWindUI = Window
