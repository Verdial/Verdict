-- Cleanup previous instance
if _G.VerdictObsidianUI then
    if type(_G.VerdictObsidianUI.Unload) == "function" then
        pcall(function() _G.VerdictObsidianUI:Unload() end)
    end
    _G.VerdictObsidianUI = nil
end

-- Services (cached)
local Srv = {
    Players    = game:GetService("Players"),
    RunService = game:GetService("RunService"),
    UIS        = game:GetService("UserInputService"),
    Lighting   = game:GetService("Lighting"),
    Workspace  = game:GetService("Workspace"),
}
local Players, RunService, UIS, Lighting, Workspace = Srv.Players, Srv.RunService, Srv.UIS, Srv.Lighting, Srv.Workspace
local workspace = Workspace -- keep consistent lowercase usage below

-- Vars
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local conns = {}
local flags = {
    aimbotFOV = 120,
    aimbotSmoothness = 0.15,
    aimbotLockPart = "Head",
    aimbotAliveCheck = true,
    sensitivity = 1.0,
}
local savedSlots = {}
local originalLighting = {}
local originalCap = 60

-- Helpers
local function safeCall(fn, ...)
    return pcall(fn, ...)
end

local function safeDisconnect(conn)
    if conn then
        safeCall(function() conn:Disconnect() end)
    end
end

local function setConnection(key, conn)
    if conns[key] then safeDisconnect(conns[key]) end
    conns[key] = conn
end

local function clearAll()
    for k, v in pairs(conns) do
        safeDisconnect(v)
        conns[k] = nil
    end
end

local function safeSetTitle(elem, text)
    safeCall(function()
        if elem and elem.SetTitle then elem:SetTitle(text) end
    end)
end

-- getChar: if wait == true, yields until character exists. Otherwise returns character or nil.
local function getChar(plr, wait)
    plr = plr or LocalPlayer
    if not plr then return nil end
    if plr.Character then return plr.Character end
    if wait then
        return plr.CharacterAdded:Wait()
    end
    return nil
end

local function getHum(plr, wait)
    local char = getChar(plr, wait)
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function getHRP(plr, wait)
    local char = getChar(plr, wait)
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function teleportTo(cf)
    local hrp = getHRP(LocalPlayer)
    if hrp and cf then
        hrp.CFrame = cf
    end
end

local function sortedPlayers()
    local out = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            table.insert(out, p.Name)
        end
    end
    table.sort(out)
    return out
end

-- Aimbot helpers
local function isAlive(char)
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

local function getClosestTarget()
    if not Camera then return nil end
    local closest = nil
    local shortest = flags.aimbotFOV or 120
    local vpSize = Camera.ViewportSize
    local screenCenter = Vector2.new(vpSize.X * 0.5, vpSize.Y * 0.5)

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            if flags.aimbotTeamCheck and LocalPlayer and plr.Team == LocalPlayer.Team then
                -- skip teammates
            else
                local char = plr.Character
                if char then
                    local part = char:FindFirstChild(flags.aimbotLockPart or "Head")
                    if part and (not flags.aimbotAliveCheck or isAlive(char)) then
                        local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
                        if onScreen then
                            local d = (Vector2.new(pos.X, pos.Y) - screenCenter).Magnitude
                            if d < shortest then
                                shortest = d
                                closest = part
                            end
                        end
                    end
                end
            end
        end
    end

    return closest
end

-- Lighting save/restore
local function saveLighting()
    originalLighting = {
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        FogEnd = Lighting.FogEnd,
        GlobalShadows = Lighting.GlobalShadows,
        Ambient = Lighting.Ambient,
    }
end

local function restoreLighting()
    for k, v in pairs(originalLighting) do
        safeCall(function() Lighting[k] = v end)
    end
    for _, eff in ipairs(Lighting:GetChildren()) do
        if eff:IsA("PostEffect") then
            eff.Enabled = true
        end
    end
end

-- FPS Cap API helpers
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

-- try to read original cap safely
if capSupported() then
    originalCap = (typeof(getfpscap) == "function" and getfpscap())
        or (typeof(get_fps_cap) == "function" and get_fps_cap())
        or (syn and typeof(syn.get_fps_cap) == "function" and syn.get_fps_cap())
        or 60
end

-- BoostFPS helpers
local function optimizeLite(obj)
    if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Smoke")
    or obj:IsA("Fire") or obj:IsA("Beam") or obj:IsA("Highlight") then
        safeCall(function() obj.Enabled = false end)
    elseif obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight") then
        safeCall(function() obj.Enabled = false end)
    end
end

local function optimizeBalanced(obj)
    optimizeLite(obj)
    if obj:IsA("Decal") or obj:IsA("Texture") then
        safeCall(function() obj.Transparency = 1 end)
    elseif obj:IsA("BasePart") or obj:IsA("UnionOperation") or obj:IsA("MeshPart") then
        safeCall(function()
            obj.Material = Enum.Material.Plastic
            obj.Reflectance = 0
        end)
    end
end

local function applyBoost(mode)
    saveLighting()
    -- disable post effects
    for _, eff in ipairs(Lighting:GetChildren()) do
        if eff:IsA("PostEffect") then
            eff.Enabled = false
        end
    end

    -- initial pass + connect watcher
    if mode == "Lite" then
        for _, o in ipairs(workspace:GetDescendants()) do optimizeLite(o) end
        setConnection("boostWatcher", workspace.DescendantAdded:Connect(optimizeLite))

    elseif mode == "Balanced" then
        for _, o in ipairs(workspace:GetDescendants()) do optimizeBalanced(o) end
        setConnection("boostWatcher", workspace.DescendantAdded:Connect(optimizeBalanced))

    elseif mode == "Ultra" then
        for _, o in ipairs(workspace:GetDescendants()) do optimizeBalanced(o) end
        setConnection("boostWatcher", workspace.DescendantAdded:Connect(optimizeBalanced))
        safeCall(function()
            Lighting.GlobalShadows = false
            Lighting.Brightness = 1
            Lighting.FogEnd = 1e9
            Lighting.Ambient = Color3.new(1, 1, 1)
            workspace.StreamingEnabled = true
            workspace.StreamingMinRadius = 64
        end)
    end
end

local function restoreBoost()
    safeDisconnect(conns.boostWatcher)
    restoreLighting()
end

-- UI Init (Obsidian)
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library, ThemeManager, SaveManager

local ok, lib = pcall(function()
    return loadstring(game:HttpGet(repo .. "Library.lua"))()
end)

if ok and type(lib) == "table" then
    Library = lib
    safeCall(function() ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))() end)
    safeCall(function() SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))() end)
else
    error("Unable to load Obsidian UI library.")
end

-- Create window
local Window = Library:CreateWindow({
    Title = "Verdict",
    Footer = "Just a simple script ♡",
    Icon = 95816097006870,
    NotifySide = "Right",
    ShowCustomCursor = true,
})

-- Tabs
local Tabs = {
    Main = Window:AddTab("Main", "user"),
    Combat = Window:AddTab("Combat", "crosshair"),
    Teleport = Window:AddTab("Teleport", "map"),
    Misc = Window:AddTab("Misc", "eye"),
    UISettings = Window:AddTab("UI Settings", "settings"),
}

-- Main -> Player groupbox
local PlayerBox = Tabs.Main:AddLeftGroupbox("Player", "boxes")

PlayerBox:AddToggle("NoClip", {
    Text = "No Clip",
    Default = false,
    Callback = function(v)
        flags.noclip = v
        safeDisconnect(conns.noclip)
        if v then
            -- Use Stepped to keep in sync with physics transforms
            setConnection("noclip", RunService.Stepped:Connect(function()
                local char = getChar(nil, false)
                if not char then return end
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                    end
                end
            end))
        end
    end
})

PlayerBox:AddToggle("DisableCollision", {
    Text = "Disable Player Collision",
    Default = false,
    Callback = function(v)
        flags.noCollision = v
        safeDisconnect(conns.noCollision)
        if v then
            setConnection("noCollision", RunService.Heartbeat:Connect(function()
                for _, plr in ipairs(Players:GetPlayers()) do
                    if plr ~= LocalPlayer then
                        local char = plr.Character
                        if char then
                            for _, part in ipairs(char:GetDescendants()) do
                                if part:IsA("BasePart") then
                                    part.CanCollide = false
                                end
                            end
                        end
                    end
                end
            end))
        else
            -- restore collisions once
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer then
                    local char = plr.Character
                    if char then
                        for _, part in ipairs(char:GetDescendants()) do
                            if part:IsA("BasePart") then
                                part.CanCollide = true
                            end
                        end
                    end
                end
            end
        end
    end
})

PlayerBox:AddToggle("InfiniteJump", {
    Text = "Infinite Jump",
    Default = false,
    Callback = function(v)
        flags.infiniteJump = v
        safeDisconnect(conns.infiniteJump)
        if v then
            setConnection("infiniteJump", UIS.JumpRequest:Connect(function()
                local hum = getHum(nil, false)
                if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
            end))
        end
    end
})

-- Main -> Visual groupbox
local VisualBox = Tabs.Main:AddRightGroupbox("Visual", "eye")

VisualBox:AddToggle("Fullbright", {
    Text = "Fullbright",
    Default = false,
    Callback = function(v)
        safeDisconnect(conns.fullbright)
        if v then
            saveLighting()
            setConnection("fullbright", RunService.RenderStepped:Connect(function()
                Lighting.Brightness = 2
                Lighting.ClockTime = 14
                Lighting.FogEnd = 1e9
                Lighting.GlobalShadows = false
                Lighting.Ambient = Color3.new(1, 1, 1)
            end))
        else
            restoreLighting()
        end
    end
})

-- Main -> Utility groupbox
local UtilityBox = Tabs.Main:AddRightGroupbox("Utility", "zap")

UtilityBox:AddToggle("ClickTeleport", {
    Text = "Click Teleport",
    Default = false,
    Callback = function(v)
        flags.clickTp = v
        safeDisconnect(conns.clickTp)
        if v and LocalPlayer then
            local mouse = LocalPlayer:GetMouse()
            setConnection("clickTp", mouse.Button1Down:Connect(function()
                if mouse.Hit then teleportTo(CFrame.new(mouse.Hit.Position + Vector3.new(0, 5, 0))) end
            end))
        end
    end
})

-- Combat -> Aimbot groupbox
local AimBox = Tabs.Combat:AddLeftGroupbox("Aimbot", "crosshair")

AimBox:AddToggle("Aimbot", {
    Text = "Aimbot",
    Default = false,
    Callback = function(v)
        flags.aimbot = v
        safeDisconnect(conns.aimbot)
        if v then
            setConnection("aimbot", RunService.RenderStepped:Connect(function()
                local target = getClosestTarget()
                if target and Camera then
                    local camPos = Camera.CFrame.Position
                    local targetPos = target.Position
                    local newCF = CFrame.new(camPos, targetPos)
                    Camera.CFrame = Camera.CFrame:Lerp(newCF, flags.aimbotSmoothness or 0.15)
                end
            end))
        end
    end
})

AimBox:AddSlider("AimbotFOV", {
    Text = "FOV",
    Default = flags.aimbotFOV,
    Min = 40,
    Max = 300,
    Rounding = 0,
    Compact = false,
    Callback = function(val)
        flags.aimbotFOV = val
    end,
})

AimBox:AddSlider("AimbotSmoothness", {
    Text = "Smoothness",
    Default = flags.aimbotSmoothness,
    Min = 0.01,
    Max = 0.5,
    Rounding = 2,
    Callback = function(val)
        flags.aimbotSmoothness = val
    end,
})

AimBox:AddDropdown("AimbotLockPart", {
    Values = { "Head", "Torso", "HumanoidRootPart" },
    Default = 1,
    Text = "Lock Part",
    Callback = function(val)
        flags.aimbotLockPart = val
    end,
})

AimBox:AddToggle("AimbotTeamCheck", {
    Text = "Team Check",
    Default = false,
    Callback = function(v) flags.aimbotTeamCheck = v end
})

AimBox:AddToggle("AimbotAliveCheck", {
    Text = "Alive Check",
    Default = true,
    Callback = function(v) flags.aimbotAliveCheck = v end
})

-- Teleport Tab -> Player Teleport
local TeleBox = Tabs.Teleport:AddLeftGroupbox("Player Teleport", "map")

TeleBox:AddDropdown("TeleportPlayer", {
    SpecialType = "Player",
    ExcludeLocalPlayer = true,
    Text = "Pilih Pemain",
    Callback = function(val) end
})

TeleBox:AddButton({
    Text = "Teleport ke Pemain",
    Func = function()
        local playerName = Library.Options and Library.Options.TeleportPlayer and Library.Options.TeleportPlayer.Value
        local target = playerName and Players:FindFirstChild(playerName)
        local hrp = target and getHRP(target, false)
        if hrp then teleportTo(hrp.CFrame + Vector3.new(0, 3, 0)) end
    end
})

TeleBox:AddButton({
    Text = "Refresh List",
    Func = function()
        local list = sortedPlayers()
        if Library.Options and Library.Options.TeleportPlayer and Library.Options.TeleportPlayer.SetValues then
            safeCall(function() Library.Options.TeleportPlayer:SetValues(list) end)
        end
    end
})

-- Misc -> Spectate
local SpectBox = Tabs.Misc:AddLeftGroupbox("Spectate", "eye")

SpectBox:AddDropdown("SpectatePlayer", {
    SpecialType = "Player",
    ExcludeLocalPlayer = true,
    Text = "Spectate Player",
    Callback = function(val) end
})

SpectBox:AddButton({
    Text = "Mulai Spectate",
    Func = function()
        local playerName = Library.Options and Library.Options.SpectatePlayer and Library.Options.SpectatePlayer.Value
        local target = playerName and Players:FindFirstChild(playerName)
        if target and target.Character then
            Camera.CameraSubject = target.Character
        end
    end
})

SpectBox:AddButton({
    Text = "Berhenti Spectate",
    Func = function()
        Camera.CameraSubject = getHum(nil, false) or getChar(nil, false)
    end
})

SpectBox:AddButton({
    Text = "Refresh List",
    Func = function()
        local list = sortedPlayers()
        if Library.Options and Library.Options.SpectatePlayer and Library.Options.SpectatePlayer.SetValues then
            safeCall(function() Library.Options.SpectatePlayer:SetValues(list) end)
        end
    end
})

-- Misc -> Position
local PosBox = Tabs.Misc:AddRightGroupbox("Position", "map-pin")

PosBox:AddDropdown("PositionSlot", {
    Values = { "1","2","3","4","5" },
    Default = 1,
    Text = "Pilih Slot",
    Callback = function(val) flags.positionSlot = tonumber(val) or 1 end
})

PosBox:AddButton({
    Text = "Save Pos",
    Func = function()
        local hrp = getHRP(nil, false)
        local slot = flags.positionSlot or 1
        if hrp then savedSlots[slot] = hrp.Position end
    end
})

PosBox:AddButton({
    Text = "Teleport Pos",
    Func = function()
        local slot = flags.positionSlot or 1
        local pos = savedSlots[slot]
        if pos then teleportTo(CFrame.new(pos + Vector3.new(0, 5, 0))) end
    end
})

PosBox:AddButton({
    Text = "Clear Slot",
    Func = function()
        local slot = flags.positionSlot or 1
        savedSlots[slot] = nil
    end
})

PosBox:AddButton({
    Text = "Clear All Slots",
    Func = function()
        table.clear(savedSlots)
    end
})

-- Misc -> Camera
local CamBox = Tabs.Misc:AddRightGroupbox("Camera", "camera")

local FreeCam = nil
safeCall(function()
    FreeCam = loadstring(game:HttpGet("https://raw.githubusercontent.com/Verdial/Verdict/refs/heads/main/fc_core.lua"))()
end)

CamBox:AddToggle("FreeCam", {
    Text = "Free Cam",
    Default = false,
    Callback = function(v)
        if FreeCam then
            if v then FreeCam:Enable() else FreeCam:Disable() end
        end
    end
})

CamBox:AddToggle("SmoothCamera", {
    Text = "Smooth Camera",
    Default = false,
    Callback = function(v)
        flags.smoothCam = v
        safeDisconnect(conns.smoothCam)
        safeDisconnect(conns.inputHandler)
        if not v then return end

        local lastCF = Camera and Camera.CFrame or CFrame.new()
        setConnection("smoothCam", RunService.RenderStepped:Connect(function()
            if not Camera then return end
            local goal = Camera.CFrame
            lastCF = lastCF:Lerp(goal, 0.25)
            Camera.CFrame = lastCF
        end))

        if UIS.MouseEnabled then
            setConnection("inputHandler", UIS.InputChanged:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseMovement then
                    local d = input.Delta
                    local x = -d.X * 0.002 * flags.sensitivity
                    local y = -d.Y * 0.002 * flags.sensitivity
                    Camera.CFrame = Camera.CFrame * CFrame.Angles(0, x, 0) * CFrame.Angles(y, 0, 0)
                end
            end))
        elseif UIS.TouchEnabled then
            setConnection("inputHandler", UIS.TouchMoved:Connect(function(touch)
                local pos = touch.Position
                if pos.X < Camera.ViewportSize.X * 0.5 then return end
                local d = touch.Delta
                local x = -d.X * 0.002 * flags.sensitivity
                local y = -d.Y * 0.002 * flags.sensitivity
                Camera.CFrame = Camera.CFrame * CFrame.Angles(0, x, 0) * CFrame.Angles(y, 0, 0)
            end))
        end
    end
})

CamBox:AddSlider("Sensitivity", {
    Text = "Sensitivity",
    Default = flags.sensitivity,
    Min = 0.1,
    Max = 10.0,
    Rounding = 1,
    Callback = function(val)
        flags.sensitivity = val
    end
})

-- Misc -> Utility / Performance
local PerfBox = Tabs.Misc:AddRightGroupbox("Utility", "cpu")

PerfBox:AddToggle("PowerSaving", {
    Text = "Power Saving Mode",
    Default = false,
    Callback = function(v)
        if not capSupported() then
            warn("⚠️ Exploit tidak support FPS cap API.")
            return
        end
        if v then doSetCap(24) else doSetCap(originalCap) end
    end
})

PerfBox:AddDropdown("BoostMode", {
    Values = { "Lite", "Balanced", "Ultra" },
    Default = 1,
    Text = "BoostFPS Mode",
    Callback = function(val)
        flags.boostMode = val
    end
})

PerfBox:AddButton({
    Text = "Apply Boost",
    Func = function()
        restoreBoost()
        applyBoost(flags.boostMode or "Lite")
    end
})

PerfBox:AddButton({
    Text = "Restore Boost",
    Func = function() restoreBoost() end
})

-- UI Settings (Theme/Save)
if ThemeManager and SaveManager then
    ThemeManager:SetLibrary(Library)
    SaveManager:SetLibrary(Library)
    ThemeManager:ApplyToTab(Tabs.UISettings)
    SaveManager:BuildConfigSection(Tabs.UISettings)
    SaveManager:LoadAutoloadConfig()
end

-- Unload handler
Library:OnUnload(function()
    clearAll()
    Camera.CameraSubject = getHum(nil, false) or getChar(nil, false)
    if capSupported() then
        doSetCap(originalCap)
    end
    restoreBoost()
    _G.VerdictObsidianUI = nil
end)

_G.VerdictObsidianUI = Library
