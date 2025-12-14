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
    return c: FindFirstChildOfClass("Humanoid")
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
        if plr ~= LocalPlayer then table.insert(list, plr. Name) end
    end
    table.sort(list)
    return list
end

--// Aimbot Helpers
local function isAlive(char)
    local hum = char:FindFirstChildOfClass("Humanoid")
    return hum and hum. Health > 0
end

local function getClosestTarget()
    local closest
    local shortest = flags.aimbotFOV or 120
    local screenCenter = Vector2.new(
        Camera.ViewportSize.X / 2,
        Camera.ViewportSize.Y / 2
    )

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            if flags.aimbotTeamCheck and plr.Team == LocalPlayer.Team then
                continue
            end

            local char = plr.Character
            local part = char and char:FindFirstChild(flags.aimbotLockPart or "Head")

            if char and part and (not flags.aimbotAliveCheck or isAlive(char)) then
                local pos, onscreen = Camera:WorldToViewportPoint(part.Position)
                if onscreen then
                    local dist = (Vector2.new(pos.X, pos.Y) - screenCenter).Magnitude
                    if dist < shortest then
                        shortest = dist
                        closest = part
                    end
                end
            end
        end
    end

    return closest
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
            eff. Enabled = true
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
        conns.boostWatcher = workspace. DescendantAdded:Connect(optimizeLite)

    elseif mode == "Balanced" then
        for _, o in ipairs(workspace:GetDescendants()) do optimizeBalanced(o) end
        safeDisconnect(conns.boostWatcher)
        conns.boostWatcher = workspace. DescendantAdded:Connect(optimizeBalanced)

    elseif mode == "Ultra" then
        for _, o in ipairs(workspace:GetDescendants()) do optimizeBalanced(o) end
        safeDisconnect(conns.boostWatcher)
        conns.boostWatcher = workspace.DescendantAdded:Connect(optimizeBalanced)
        -- pengaturan ultra (lighting & streaming)
        pcall(function()
            Lighting.GlobalShadows   = false
            Lighting.Brightness      = 1
            Lighting. FogEnd          = 1e9
            Lighting. Ambient         = Color3.new(1, 1, 1)
            Workspace.StreamingEnabled   = true
            Workspace.StreamingMinRadius = 64
        end)
    end
end

local function restoreBoost()
    safeDisconnect(conns. boostWatcher)
    restoreLighting()
end

--// UI Init
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
WindUI: ToggleAcrylic(false)

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
                    if part: IsA("BasePart") then part. CanCollide = false end
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
                        if part: IsA("BasePart") then part.CanCollide = true end
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
                if hum then hum: ChangeState(Enum.HumanoidStateType.Jumping) end
            end)
        end
    end
})


MainTab:Section({ Title = "Visual" })

MainTab:Toggle({
    Title = "Fullbright",
    Default = false,
    Callback = function(v)
        safeDisconnect(conns. fullbright)
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

--// Combat Tab
local CombatTab = Window:Tab({ Title = "Combat", Icon = "crosshair" })
CombatTab:Section({ Title = "Aimbot" })

CombatTab:Toggle({
    Title = "Aimbot",
    Default = false,
    Callback = function(v)
        flags.aimbot = v
        safeDisconnect(conns.aimbot)
        if v then
            conns. aimbot = RunService.RenderStepped:Connect(function()
                local target = getClosestTarget()
                if target then
                    local camPos = Camera.CFrame.Position
                    local targetPos = target.Position
                    local newCF = CFrame.new(camPos, targetPos)
                    Camera.CFrame = Camera. CFrame: Lerp(newCF, flags.aimbotSmoothness or 0.15)
                end
            end)
        end
    end
})

local fovSlider
fovSlider = CombatTab: Slider({
    Title = "FOV [ " .. tostring(flags.aimbotFOV or 120) .. " ]",
    Value = { Min = 40, Max = 300, Default = 120, Step = 10 },
    Callback = function(val)
        flags.aimbotFOV = val
        safeSetTitle(fovSlider, "FOV [ " .. tostring(val) .. " ]")
    end
})

local smoothSlider
smoothSlider = CombatTab:Slider({
    Title = "Smoothness [ " .. string.format("%.2f", flags.aimbotSmoothness or 0.15) .. " ]",
    Value = { Min = 0.01, Max = 0.5, Default = 0.15, Step = 0.01 },
    Callback = function(val)
        flags.aimbotSmoothness = val
        safeSetTitle(smoothSlider, "Smoothness [ " ..  string.format("%.2f", val) .. " ]")
    end
})

CombatTab: Dropdown({
    Title = "Lock Part",
    Values = { "Head", "Torso", "HumanoidRootPart" },
    Default = "Head",
    Callback = function(opt) flags.aimbotLockPart = opt end
})

CombatTab:Toggle({
    Title = "Team Check",
    Default = false,
    Callback = function(v) flags.aimbotTeamCheck = v end
})

CombatTab:Toggle({
    Title = "Alive Check",
    Default = true,
    Callback = function(v) flags.aimbotAliveCheck = v end
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
            if hrp then teleportTo(hrp. CFrame + Vector3.new(0, 3, 0)) end
        end
    end
})

TeleTab:Button({
    Title = "Refresh List",
    Callback = function()
        local list = sortedPlayers()
        TeleDropdown: Refresh(list)
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
            Camera. CameraSubject = target.Character
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

local FreeCam = loadstring(game: HttpGet("https://raw.githubusercontent.com/Verdial/Verdict/refs/heads/main/fc_core.lua"))()
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
                    local x = -d. X * 0.002 * flags.sensitivity
                    local y = -d.Y * 0.002 * flags.sensitivity
                    Camera.CFrame = Camera.CFrame * CFrame. Angles(0, x, 0) * CFrame.Angles(y, 0, 0)
                end
            end)
        elseif UIS.TouchEnabled then
            conns.inputHandler = UIS.TouchMoved:Connect(function(touch)
                local pos = touch.Position
                if pos.X < Camera.ViewportSize.X * 0.5 then return end
                local d = touch.Delta
                local x = -d.X * 0.002 * flags.sensitivity
                local y = -d.Y * 0.002 * flags.sensitivity
                Camera.CFrame = Camera.CFrame * CFrame. Angles(0, x, 0) * CFrame.Angles(y, 0, 0)
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
Window: Unload(function()
    clearAll()
    Camera. CameraSubject = getHum() or getChar()
    if capSupported() then
        doSetCap(originalCap) -- reset FPS cap saat UI ditutup
    end
    restoreBoost()
    _G.VerdictWindUI = nil
end)

_G.VerdictWindUI = Window
