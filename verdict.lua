--// Cleanup
if _G.VerdictWindUI then
    _G.VerdictWindUI:Unload()
    _G.VerdictWindUI = nil
end

--// Services
local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local UIS         = game:GetService("UserInputService")
local Lighting    = game:GetService("Lighting")
local Workspace   = game:GetService("Workspace")

--// Vars
local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera
local conns       = {}
local flags       = {}
local savedSlots  = {}

--// Helpers
local function safeDisconnect(conn) if conn then conn:Disconnect() end end

local function clearAll()
    for k, v in pairs(conns) do
        safeDisconnect(v)
        conns[k] = nil
    end
end

local function safeSetTitle(elem, text)
    pcall(function()
        if elem and elem.SetTitle then elem:SetTitle(text) end
    end)
end

local function getChar(plr)
    plr = plr or LocalPlayer
    return plr.Character or plr.CharacterAdded:Wait()
end

local function getHum(plr)
    local c = getChar(plr)
    return c:FindFirstChildOfClass("Humanoid")
end

local function getHRP(plr)
    local c = getChar(plr)
    return c:FindFirstChild("HumanoidRootPart")
end

local function teleportTo(cf)
    local hrp = getHRP(LocalPlayer)
    if hrp then hrp.CFrame = cf end
end

local function sortedPlayers()
    local list = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then table.insert(list, plr.Name) end
    end
    table.sort(list)
    return list
end

--// Save original lighting
local originalLighting = {}
local function saveLighting()
    originalLighting = {
        Brightness    = Lighting.Brightness,
        ClockTime     = Lighting.ClockTime,
        FogEnd        = Lighting.FogEnd,
        GlobalShadows = Lighting.GlobalShadows,
        Ambient       = Lighting.Ambient
    }
end

local function restoreLighting()
    for k, v in pairs(originalLighting) do
        pcall(function() Lighting[k] = v end)
    end
    -- re-enable post effects yang sempat dimatikan
    for _, eff in ipairs(Lighting:GetChildren()) do
        if eff:IsA("PostEffect") then
            eff.Enabled = true
        end
    end
end

--// FPS Cap API Helpers (Power Saving Mode)
local function capSupported()
    return typeof(setfpscap) == "function"
        or typeof(set_fps_cap) == "function"
        or (syn and typeof(syn.set_fps_cap) == "function")
end

local function doSetCap(n)
    if typeof(setfpscap) == "function" then
        setfpscap(n)
    elseif typeof(set_fps_cap) == "function" then
        set_fps_cap(n)
    elseif syn and typeof(syn.set_fps_cap) == "function" then
        syn.set_fps_cap(n)
    end
end

local originalCap = 60
if capSupported() then
    originalCap = (typeof(getfpscap) == "function" and getfpscap())
        or (typeof(get_fps_cap) == "function" and get_fps_cap())
        or (syn and typeof(syn.get_fps_cap) == "function" and syn.get_fps_cap())
        or 60
end

--// BoostFPS (Dropdown + Apply/Restore)
local function optimizeLite(obj)
    if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Smoke")
    or obj:IsA("Fire") or obj:IsA("Beam") or obj:IsA("Highlight") then
        pcall(function() obj.Enabled = false end)
    elseif obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight") then
        pcall(function() obj.Enabled = false end)
    end
end

local function optimizeBalanced(obj)
    optimizeLite(obj)
    if obj:IsA("Decal") or obj:IsA("Texture") then
        -- jangan destroy biar nggak bikin GC spike
        pcall(function() obj.Transparency = 1 end)
    elseif obj:IsA("BasePart") or obj:IsA("UnionOperation") or obj:IsA("MeshPart") then
        pcall(function()
            obj.Material    = Enum.Material.Plastic
            obj.Reflectance = 0
        end)
    end
end

local function applyBoost(mode)
    saveLighting()

    -- matikan post effects (Bloom, ColorCorrection, DepthOfField, dll)
    for _, eff in ipairs(Lighting:GetChildren()) do
        if eff:IsA("PostEffect") then
            eff.Enabled = false
        end
    end

    -- terapkan optimisasi sekali di awal
    if mode == "Lite" then
        for _, o in ipairs(workspace:GetDescendants()) do optimizeLite(o) end
        safeDisconnect(conns.boostWatcher)
        conns.boostWatcher = workspace.DescendantAdded:Connect(optimizeLite)

    elseif mode == "Balanced" then
        for _, o in ipairs(workspace:GetDescendants()) do optimizeBalanced(o) end
        safeDisconnect(conns.boostWatcher)
        conns.boostWatcher = workspace.DescendantAdded:Connect(optimizeBalanced)

    elseif mode == "Ultra" then
        for _, o in ipairs(workspace:GetDescendants()) do optimizeBalanced(o) end
        safeDisconnect(conns.boostWatcher)
        conns.boostWatcher = workspace.DescendantAdded:Connect(optimizeBalanced)
        -- pengaturan ultra (lighting & streaming)
        pcall(function()
            Lighting.GlobalShadows   = false
            Lighting.Brightness      = 1
            Lighting.FogEnd          = 1e9
            Lighting.Ambient         = Color3.new(1, 1, 1)
            Workspace.StreamingEnabled   = true
            Workspace.StreamingMinRadius = 64
        end)
    end
end

local function restoreBoost()
    safeDisconnect(conns.boostWatcher)
    restoreLighting()
end

--// UI Init
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
WindUI:ToggleAcrylic(false)

local Window = WindUI:CreateWindow({
    Title        = "Verdict",
    Author       = "Just a simple script ♡",
    Icon         = "smartphone",
    Size         = UDim2.fromOffset(360, 400),
    Theme        = "Dark",
    SideBarWidth = 120,
    Draggable    = false
})

--// Main Tab
local MainTab = Window:Tab({ Title = "Main", Icon = "zap" })
MainTab:Section({ Title = "Player" })

MainTab:Toggle({
    Title = "No Clip",
    Default = false,
    Callback = function(v)
        flags.noclip = v
        safeDisconnect(conns.noclip)
        if v then
            conns.noclip = RunService.Stepped:Connect(function()
                local char = getChar()
                for _, part in ipairs(char:GetChildren()) do
                    if part:IsA("BasePart") then part.CanCollide = false end
                end
            end)
        end
    end
})

MainTab:Toggle({
    Title = "Disable Player Collision",
    Default = false,
    Callback = function(v)
        flags.noCollision = v
        safeDisconnect(conns.noCollision)
        if v then
            conns.noCollision = RunService.Heartbeat:Connect(function()
                for _, plr in ipairs(Players:GetPlayers()) do
                    if plr ~= LocalPlayer and plr.Character then
                        for _, part in ipairs(plr.Character:GetDescendants()) do
                            if part:IsA("BasePart") then part.CanCollide = false end
                        end
                    end
                end
            end)
        else
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer and plr.Character then
                    for _, part in ipairs(plr.Character:GetDescendants()) do
                        if part:IsA("BasePart") then part.CanCollide = true end
                    end
                end
            end
        end
    end
})

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

--// Auto Jump
MainTab:Toggle({
    Title = "Auto Jump",
    Default = false,
    Callback = function(v)
        flags.autoJump = v
        safeDisconnect(conns.autoJump)
        if flags.autoJumpButton then
            flags.autoJumpButton:Destroy()
            flags.autoJumpButton = nil
        end
        if not v then return end

        -- buat tombol di pojok kanan bawah
        local gui = Instance.new("ScreenGui")
        gui.Name = "AutoJumpGUI"
        gui.ResetOnSpawn = false
        gui.Parent = game:GetService("CoreGui")

        local btn = Instance.new("TextButton")
        btn.Text = "⭮"
        btn.Font = Enum.Font.GothamBold
        btn.TextScaled = true
        btn.Size = UDim2.new(0, 55, 0, 55)
        btn.AnchorPoint = Vector2.new(1, 1)
        btn.Position = UDim2.new(1, -25, 1, -25)
        btn.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.BorderSizePixel = 0
        btn.ZIndex = 9999
        btn.Parent = gui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = btn

        flags.autoJumpEnabled = true
        flags.autoJumpButton = gui

        btn.MouseButton1Click:Connect(function()
            flags.autoJumpEnabled = not flags.autoJumpEnabled
            btn.BackgroundColor3 = flags.autoJumpEnabled
                and Color3.fromRGB(100, 255, 100)
                or  Color3.fromRGB(255, 100, 100)
        end)

        local hum
        local wasGrounded = false

        conns.autoJump = RunService.Heartbeat:Connect(function()
            if not flags.autoJumpEnabled then return end

            hum = getHum()
            if not hum or hum.Health <= 0 then return end

            local grounded = hum.FloorMaterial ~= Enum.Material.Air

            -- Deteksi perubahan dari udara -> tanah
            if grounded and not wasGrounded then
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end

            wasGrounded = grounded
        end)
    end
})

MainTab:Section({ Title = "Visual" })

MainTab:Toggle({
    Title = "Fullbright",
    Default = false,
    Callback = function(v)
        safeDisconnect(conns.fullbright)
        if v then
            saveLighting()
            conns.fullbright = RunService.RenderStepped:Connect(function()
                Lighting.Brightness    = 2
                Lighting.ClockTime     = 14
                Lighting.FogEnd        = 1e9
                Lighting.GlobalShadows = false
                Lighting.Ambient       = Color3.new(1, 1, 1)
            end)
        else
            restoreLighting()
        end
    end
})

MainTab:Section({ Title = "Utility" })

MainTab:Toggle({
    Title = "Click Teleport",
    Default = false,
    Callback = function(v)
        flags.clickTp = v
        safeDisconnect(conns.clickTp)
        if v then
            local mouse = LocalPlayer:GetMouse()
            conns.clickTp = mouse.Button1Down:Connect(function()
                if mouse.Hit then teleportTo(CFrame.new(mouse.Hit.Position + Vector3.new(0, 5, 0))) end
            end)
        end
    end
})

--// Teleport Tab
local TeleTab = Window:Tab({ Title = "Teleport", Icon = "map" })
TeleTab:Section({ Title = "Player Teleport" })

local selectedPlayer
local TeleDropdown = TeleTab:Dropdown({
    Title = "Pilih Pemain",
    Values = sortedPlayers(),
    Searchable = true,
    Callback = function(opt) selectedPlayer = opt end
})

TeleTab:Button({
    Title = "Teleport ke Pemain",
    Callback = function()
        if selectedPlayer then
            local target = Players:FindFirstChild(selectedPlayer)
            local hrp = target and getHRP(target)
            if hrp then teleportTo(hrp.CFrame + Vector3.new(0, 3, 0)) end
        end
    end
})

TeleTab:Button({
    Title = "Refresh List",
    Callback = function()
        local list = sortedPlayers()
        TeleDropdown:Refresh(list)
        if selectedPlayer and table.find(list, selectedPlayer) then
            TeleDropdown:Select(selectedPlayer)
        else
            selectedPlayer = nil
        end
    end
})

--// Misc Tab
local MiscTab = Window:Tab({ Title = "Misc", Icon = "eye" })

--// Spectate
MiscTab:Section({ Title = "Spectate" })

local spectTarget
local SpectDropdown = MiscTab:Dropdown({
    Title = "Spectate Player",
    Values = sortedPlayers(),
    Searchable = true,
    Callback = function(opt) spectTarget = opt end
})

MiscTab:Button({
    Title = "Mulai Spectate",
    Callback = function()
        local target = spectTarget and Players:FindFirstChild(spectTarget)
        if target and target.Character then
            Camera.CameraSubject = target.Character
        end
    end
})

MiscTab:Button({
    Title = "Berhenti Spectate",
    Callback = function()
        Camera.CameraSubject = getHum() or getChar()
    end
})

MiscTab:Button({
    Title = "Refresh List",
    Callback = function()
        local list = sortedPlayers()
        SpectDropdown:Refresh(list)
        if spectTarget and table.find(list, spectTarget) then
            SpectDropdown:Select(spectTarget)
        else
            spectTarget = nil
        end
    end
})

--// Position
MiscTab:Section({ Title = "Position" })

local slotSelected = 1
MiscTab:Dropdown({
    Title = "Pilih Slot",
    Values = { "1","2","3","4","5" },
    Value  = "1",
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

MiscTab:Button({
    Title = "Clear Slot",
    Callback = function() savedSlots[slotSelected] = nil end
})

MiscTab:Button({
    Title = "Clear All Slots",
    Callback = function() table.clear(savedSlots) end
})

--// Camera
MiscTab:Section({ Title = "Camera" })

local FreeCam = loadstring(game:HttpGet("https://raw.githubusercontent.com/Verdial/Verdict/refs/heads/main/fc_core.lua"))()
MiscTab:Toggle({
    Title = "Free Cam",
    Default = false,
    Callback = function(v)
        if v then FreeCam:Enable() else FreeCam:Disable() end
    end
})

flags.sensitivity = 1.0
local sensitivitySlider

MiscTab:Toggle({
    Title = "Smooth Camera",
    Default = false,
    Callback = function(v)
        flags.smoothCam = v
        safeDisconnect(conns.smoothCam)
        safeDisconnect(conns.inputHandler)
        if not v then return end

        local lastCF = Camera.CFrame
        conns.smoothCam = RunService.RenderStepped:Connect(function()
            local goal = Camera.CFrame
            lastCF = lastCF:Lerp(goal, 0.25)
            Camera.CFrame = lastCF
        end)

        if UIS.MouseEnabled then
            conns.inputHandler = UIS.InputChanged:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseMovement then
                    local d = input.Delta
                    local x = -d.X * 0.002 * flags.sensitivity
                    local y = -d.Y * 0.002 * flags.sensitivity
                    Camera.CFrame = Camera.CFrame * CFrame.Angles(0, x, 0) * CFrame.Angles(y, 0, 0)
                end
            end)
        elseif UIS.TouchEnabled then
            conns.inputHandler = UIS.TouchMoved:Connect(function(touch)
                local pos = touch.Position
                if pos.X < Camera.ViewportSize.X * 0.5 then return end
                local d = touch.Delta
                local x = -d.X * 0.002 * flags.sensitivity
                local y = -d.Y * 0.002 * flags.sensitivity
                Camera.CFrame = Camera.CFrame * CFrame.Angles(0, x, 0) * CFrame.Angles(y, 0, 0)
            end)
        end
    end
})

sensitivitySlider = MiscTab:Slider({
    Title = "Sensitivity [ " .. tostring(flags.sensitivity) .. " ]",
    Desc  = "Atur seberapa responsif kamera saat digeser",
    Value = { Min = 0.1, Max = 10.0, Default = flags.sensitivity, Step = 0.1 },
    Callback = function(val)
        flags.sensitivity = val
        safeSetTitle(sensitivitySlider, "Sensitivity [ " .. string.format("%.1f", val) .. " ]")
    end
})

--// Utility
MiscTab:Section({ Title = "Utility" })

-- Power Saving Mode (FPS 30)
MiscTab:Toggle({
    Title = "Power Saving Mode",
    Default = false,
    Callback = function(v)
        if not capSupported() then
            warn("⚠️ Exploit tidak support FPS cap API.")
            return
        end
        if v then doSetCap(24) else doSetCap(originalCap) end
    end
})

-- BoostFPS (Dropdown + Apply / Restore)
MiscTab:Section({ Title = "Performance" })

local boostMode = "Lite"
local BoostDropdown = MiscTab:Dropdown({
    Title = "BoostFPS Mode",
    Values = { "Lite", "Balanced", "Ultra" },
    Default = "Lite",
    Callback = function(opt) boostMode = opt end
})

MiscTab:Button({
    Title = "Apply Boost",
    Callback = function()
        restoreBoost()
        applyBoost(boostMode)
    end
})

MiscTab:Button({
    Title = "Restore Boost",
    Callback = function()
        restoreBoost()
    end
})

--// Unload
Window:Unload(function()
    clearAll()
    Camera.CameraSubject = getHum() or getChar()
    if capSupported() then
        doSetCap(originalCap) -- reset FPS cap saat UI ditutup
    end
    restoreBoost()
    _G.VerdictWindUI = nil
end)

_G.VerdictWindUI = Window
