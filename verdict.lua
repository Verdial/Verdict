-- Cleanup previous instance
if _G.VerdictObsidianUI then
    local prev = _G.VerdictObsidianUI
    if type(prev.Unload) == "function" then
        pcall(function() prev:Unload() end)
    end
    _G.VerdictObsidianUI = nil
end

-- Services (cached)
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local Lighting   = game:GetService("Lighting")
local Workspace  = game:GetService("Workspace")
local workspace  = Workspace -- consistent lowercase usage

-- Locals
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local conns = {}

-- Default flags
local flags = {
    aimbotFOV = 120,
    aimbotSmoothness = 0.15,
    aimbotLockPart = "Head",
    aimbotAliveCheck = true,
    aimbotTeamCheck = false,
    sensitivity = 1.0,
    positionSlot = 1,
    prediction = 0.12,
    showFOV = false,
    fovColor = Color3.fromRGB(255,255,255),
    fovThickness = 2,
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
        -- pcall to avoid errors if already disconnected or invalid
        pcall(function() conn:Disconnect() end)
    end
end

local function setConnection(key, conn)
    if not key then return end
    if conns[key] then safeDisconnect(conns[key]) end
    conns[key] = conn
end

local function disconnectKey(key)
    if conns[key] then
        safeDisconnect(conns[key])
        conns[key] = nil
    end
end

local function clearAllConnections()
    for k, v in pairs(conns) do
        safeDisconnect(v)
        conns[k] = nil
    end
end

local function safeSetTitle(elem, text)
    if elem and type(elem.SetTitle) == "function" then
        pcall(function() elem:SetTitle(text) end)
    end
end

-- Character utilities
local function getChar(plr, wait)
    plr = plr or LocalPlayer
    if not plr then return nil end
    if plr.Character then return plr.Character end
    if wait and plr.CharacterAdded then return plr.CharacterAdded:Wait() end
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
    local hrp = getHRP(nil, false)
    if hrp and cf then hrp.CFrame = cf end
end

local function sortedPlayers()
    local out = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            out[#out + 1] = p.Name
        end
    end
    table.sort(out)
    return out
end

-- Aimbot helpers
local function isAlive(char)
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health and hum.Health > 0
end

-- small clamp helper (Roblox/Luau has math.clamp but we keep safe)
local function clamp(x, a, b) return math.max(a, math.min(b, x)) end

-- get velocity with fallbacks (AssemblyLinearVelocity preferred on R15)
local function getPartVelocity(part)
    if not part then return Vector3.new(0,0,0) end
    local ok, vel = pcall(function()
        -- AssemblyLinearVelocity is more consistent on modern rigs
        if part.AssemblyLinearVelocity then
            return part.AssemblyLinearVelocity
        else
            return part.Velocity or Vector3.new(0,0,0)
        end
    end)
    return (ok and vel) and vel or Vector3.new(0,0,0)
end

-- Robust target resolution: try several common parts, primary part, bounding box center, or any BasePart fallback
local function resolveTargetPositionFromCharacter(char, preferredPart)
    if not char then return nil end
    -- if preferredPart provided and exists, try it first
    if preferredPart and type(preferredPart) == "string" then
        local p = char:FindFirstChild(preferredPart)
        if p and p:IsA("BasePart") then
            return p.Position, p
        end
    end
    -- prioritized names
    local priorities = { "Head", "UpperTorso", "Torso", "HumanoidRootPart", "LowerTorso" }
    for _, name in ipairs(priorities) do
        local p = char:FindFirstChild(name)
        if p and p:IsA("BasePart") then
            return p.Position, p
        end
    end
    -- PrimaryPart if set
    if char.PrimaryPart and char.PrimaryPart:IsA("BasePart") then
        return char.PrimaryPart.Position, char.PrimaryPart
    end
    -- try bounding box center
    local ok, cf = pcall(function() return char:GetBoundingBox() end)
    if ok and cf then
        return cf.Position, nil -- no actual part, but pos works
    end
    -- fallback: first BasePart found
    for _, v in ipairs(char:GetDescendants()) do
        if v:IsA("BasePart") then
            return v.Position, v
        end
    end
    return nil
end

-- Predict position using velocity if available (simple linear)
local function predictPositionFromPart(part)
    if not part then return nil end
    local pos = nil
    local ok, ppos = pcall(function() return part.Position end)
    if ok and ppos then pos = ppos end
    if not pos then return nil end
    local vel = getPartVelocity(part)
    local pred = (flags.prediction or 0) * 1.0
    return pos + vel * pred
end

local function predictPositionFromVector3(pos)
    if not pos then return nil end
    return pos
end

-- Drawing (FOV) support - use Drawing API if available
local DrawingLib = nil
pcall(function() DrawingLib = Drawing or drawing end) -- some exploits use lowercase 'drawing'

local fovCircle = nil

local function createFOVCircle()
    if not DrawingLib then return end
    if fovCircle then
        pcall(function() fovCircle:Remove() end)
        fovCircle = nil
    end
    pcall(function()
        fovCircle = DrawingLib.new("Circle")
        fovCircle.Visible = false
        fovCircle.Color = flags.fovColor or Color3.fromRGB(255,255,255)
        fovCircle.Thickness = flags.fovThickness or 2
        fovCircle.NumSides = 64
        fovCircle.Filled = false
        fovCircle.Radius = flags.aimbotFOV or 120
        fovCircle.Position = Vector2.new(0,0)
    end)
end

local function destroyFOVCircle()
    if not DrawingLib or not fovCircle then return end
    pcall(function() fovCircle:Remove() end)
    fovCircle = nil
end

-- getClosestTarget now returns table {player, position(Vector3), part(optional BasePart)}
local function getClosestTarget()
    local cam = workspace.CurrentCamera or Camera
    if not cam then return nil end

    local players = Players:GetPlayers()
    local vpSize = cam.ViewportSize
    local screenCenter = Vector2.new(vpSize.X * 0.5, vpSize.Y * 0.5)
    local shortest = flags.aimbotFOV or 120
    local best = nil -- {player=plr, position=Vector3, part=part}

    for i = 1, #players do
        local plr = players[i]
        if plr ~= LocalPlayer then
            if not (flags.aimbotTeamCheck and LocalPlayer and plr.Team == LocalPlayer.Team) then
                local char = plr.Character
                if char and (not flags.aimbotAliveCheck or isAlive(char)) then
                    local pos, part = resolveTargetPositionFromCharacter(char, flags.aimbotLockPart)
                    if pos then
                        local screenPos, onScreen = cam:WorldToViewportPoint(pos)
                        if onScreen then
                            local d = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                            if d < shortest then
                                shortest = d
                                best = {player = plr, position = pos, part = part}
                            end
                        end
                    end
                end
            end
        end
    end

    return best
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
        pcall(function() Lighting[k] = v end)
    end
    -- re-enable post effects
    for _, eff in ipairs(Lighting:GetChildren()) do
        if eff:IsA("PostEffect") then
            pcall(function() eff.Enabled = true end)
        end
    end
end

-- FPS cap utilities
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

-- Read original cap once
if capSupported() then
    originalCap = (typeof(getfpscap) == "function" and getfpscap())
        or (typeof(get_fps_cap) == "function" and get_fps_cap())
        or (syn and typeof(syn.get_fps_cap) == "function" and syn.get_fps_cap())
        or originalCap
end

-- BoostFPS helpers: use lookup tables for class checks (faster than repeated IsA chains)
local disableEnabledClasses = {
    ParticleEmitter = true,
    Trail = true,
    Smoke = true,
    Fire = true,
    Beam = true,
    Highlight = true,
}
local lightClasses = {
    PointLight = true,
    SpotLight = true,
    SurfaceLight = true,
}
local textureClasses = {
    Decal = true,
    Texture = true,
}
local partClasses = {
    BasePart = true,
    UnionOperation = true,
    MeshPart = true,
}

local function optimizeLite(obj)
    local class = obj.ClassName
    if disableEnabledClasses[class] or lightClasses[class] then
        pcall(function() obj.Enabled = false end)
    end
end

local function optimizeBalanced(obj)
    optimizeLite(obj)
    local class = obj.ClassName
    if textureClasses[class] then
        pcall(function() obj.Transparency = 1 end)
    elseif partClasses[class] then
        pcall(function()
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
            pcall(function() eff.Enabled = false end)
        end
    end

    -- initial traversal + watcher
    local walker = (mode == "Lite" and optimizeLite) or optimizeBalanced

    for _, o in ipairs(workspace:GetDescendants()) do
        pcall(function() walker(o) end)
    end

    setConnection("boostWatcher", workspace.DescendantAdded:Connect(function(o)
        pcall(function() walker(o) end)
    end))

    if mode == "Ultra" then
        pcall(function()
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
    disconnectKey("boostWatcher")
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
    pcall(function() ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))() end)
    pcall(function() SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))() end)
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
        disconnectKey("noclip")
        if v then
            -- Stepped keeps sync with physics transforms
            setConnection("noclip", RunService.Stepped:Connect(function()
                local char = getChar(nil, false)
                if not char then return end
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then
                        pcall(function() part.CanCollide = false end)
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
        disconnectKey("noCollision")
        if v then
            setConnection("noCollision", RunService.Heartbeat:Connect(function()
                for _, plr in ipairs(Players:GetPlayers()) do
                    if plr ~= LocalPlayer then
                        local char = plr.Character
                        if char then
                            for _, part in ipairs(char:GetDescendants()) do
                                if part:IsA("BasePart") then
                                    pcall(function() part.CanCollide = false end)
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
                                pcall(function() part.CanCollide = true end)
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
        disconnectKey("infiniteJump")
        if v then
            setConnection("infiniteJump", UIS.JumpRequest:Connect(function()
                local hum = getHum(nil, false)
                if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end) end
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
        disconnectKey("fullbright")
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
        disconnectKey("clickTp")
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
        disconnectKey("aimbot")
        if v then
            setConnection("aimbot", RunService.RenderStepped:Connect(function()
                local targetData = getClosestTarget()
                local cam = workspace.CurrentCamera or Camera
                if targetData and cam then
                    local camPos = cam.CFrame.Position
                    local rawPos = targetData.position
                    local predictedPos = nil

                    -- prefer predicting from a real part if available
                    if targetData.part and targetData.part:IsA("BasePart") then
                        predictedPos = predictPositionFromPart(targetData.part)
                    end

                    -- fallback: if predict not available, use vector pos
                    if not predictedPos and rawPos then
                        predictedPos = predictPositionFromVector3(rawPos)
                    end

                    if predictedPos then
                        -- create desired CFrame looking at predicted position
                        local desiredCF = CFrame.lookAt(camPos, predictedPos, Vector3.new(0,1,0))

                        -- FIXED: invert smoothness so higher smoothness => slower (more smooth).
                        -- mapping: smoothness slider [0..1], where 0 = instant snap, 1 = max smooth (slow).
                        local smooth = clamp(tonumber(flags.aimbotSmoothness) or 0, 0, 1)
                        -- alpha is lerp factor per-frame: larger alpha moves camera more towards target.
                        -- we invert: alpha = 1 - smooth. enforce a small minimum so it never stalls.
                        local alpha = clamp(1 - smooth, 0.01, 1)

                        pcall(function()
                            cam.CFrame = cam.CFrame:Lerp(desiredCF, alpha)
                        end)
                    end
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
        if fovCircle then
            pcall(function() fovCircle.Radius = val end)
        end
    end,
})

AimBox:AddSlider("AimbotSmoothness", {
    Text = "Smoothness",
    Default = flags.aimbotSmoothness,
    Min = 0.0,
    Max = 1.0,
    Rounding = 2,
    Callback = function(val) flags.aimbotSmoothness = val end,
})

AimBox:AddDropdown("AimbotLockPart", {
    Values = { "Head", "Torso", "HumanoidRootPart" },
    Default = 1,
    Text = "Lock Part",
    Callback = function(val) flags.aimbotLockPart = val end,
})

AimBox:AddToggle("AimbotTeamCheck", { Text = "Team Check", Default = false, Callback = function(v) flags.aimbotTeamCheck = v end })
AimBox:AddToggle("AimbotAliveCheck", { Text = "Alive Check", Default = true, Callback = function(v) flags.aimbotAliveCheck = v end })

-- New: Prediction slider for leading moving targets
AimBox:AddSlider("AimbotPrediction", {
    Text = "Prediction (s)",
    Default = flags.prediction,
    Min = 0,
    Max = 1.0,
    Rounding = 2,
    Callback = function(val) flags.prediction = val end,
})

-- New: FOV display toggle
AimBox:AddToggle("ShowFOV", {
    Text = "Show FOV",
    Default = flags.showFOV,
    Callback = function(v)
        flags.showFOV = v
        disconnectKey("fovRender")
        if v then
            createFOVCircle()
            -- update the circle every render
            setConnection("fovRender", RunService.RenderStepped:Connect(function()
                if not fovCircle then createFOVCircle() end
                local cam = workspace.CurrentCamera or Camera
                if not cam or not fovCircle then return end
                local vp = cam.ViewportSize
                local center = Vector2.new(vp.X * 0.5, vp.Y * 0.5)
                pcall(function()
                    fovCircle.Visible = true
                    fovCircle.Position = center
                    fovCircle.Radius = flags.aimbotFOV or fovCircle.Radius
                    fovCircle.Color = flags.fovColor or fovCircle.Color
                    fovCircle.Thickness = flags.fovThickness or fovCircle.Thickness
                end)
            end))
        else
            destroyFOVCircle()
        end
    end
})

-- Teleport Tab -> Player Teleport
local TeleBox = Tabs.Teleport:AddLeftGroupbox("Player Teleport", "map")

TeleBox:AddDropdown("TeleportPlayer", {
    SpecialType = "Player",
    ExcludeLocalPlayer = true,
    Text = "Pilih Pemain",
    Callback = function() end
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
            pcall(function() Library.Options.TeleportPlayer:SetValues(list) end)
        end
    end
})

-- Misc -> Spectate
local SpectBox = Tabs.Misc:AddLeftGroupbox("Spectate", "eye")

SpectBox:AddDropdown("SpectatePlayer", {
    SpecialType = "Player",
    ExcludeLocalPlayer = true,
    Text = "Spectate Player",
    Callback = function() end
})

SpectBox:AddButton({
    Text = "Mulai Spectate",
    Func = function()
        local playerName = Library.Options and Library.Options.SpectatePlayer and Library.Options.SpectatePlayer.Value
        local target = playerName and Players:FindFirstChild(playerName)
        if target and target.Character then
            workspace.CurrentCamera.CameraSubject = target.Character
        end
    end
})

SpectBox:AddButton({
    Text = "Berhenti Spectate",
    Func = function()
        workspace.CurrentCamera.CameraSubject = getHum(nil, false) or getChar(nil, false)
    end
})

SpectBox:AddButton({
    Text = "Refresh List",
    Func = function()
        local list = sortedPlayers()
        if Library.Options and Library.Options.SpectatePlayer and Library.Options.SpectatePlayer.SetValues then
            pcall(function() Library.Options.SpectatePlayer:SetValues(list) end)
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

PosBox:AddButton({ Text = "Save Pos", Func = function()
    local hrp = getHRP(nil, false)
    local slot = flags.positionSlot or 1
    if hrp then savedSlots[slot] = hrp.Position end
end })

PosBox:AddButton({ Text = "Teleport Pos", Func = function()
    local slot = flags.positionSlot or 1
    local pos = savedSlots[slot]
    if pos then teleportTo(CFrame.new(pos + Vector3.new(0, 5, 0))) end
end })

PosBox:AddButton({ Text = "Clear Slot", Func = function()
    savedSlots[flags.positionSlot or 1] = nil
end })

PosBox:AddButton({ Text = "Clear All Slots", Func = function() table.clear(savedSlots) end })

-- Misc -> Camera
local CamBox = Tabs.Misc:AddRightGroupbox("Camera", "camera")

local FreeCam = nil
pcall(function()
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
        disconnectKey("smoothCam")
        disconnectKey("inputHandler")
        if not v then return end

        local cam = workspace.CurrentCamera or Camera
        local lastCF = cam and cam.CFrame or CFrame.new()
        setConnection("smoothCam", RunService.RenderStepped:Connect(function()
            local cur = (workspace.CurrentCamera or cam)
            if not cur then return end
            lastCF = lastCF:Lerp(cur.CFrame, 0.25)
            cur.CFrame = lastCF
        end))

        -- Input handling (both mouse & touch)
        setConnection("inputHandler", UIS.InputChanged:Connect(function(input)
            local curCam = workspace.CurrentCamera or cam
            if not curCam then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement and UIS.MouseEnabled then
                local d = input.Delta
                local x = -d.X * 0.002 * flags.sensitivity
                local y = -d.Y * 0.002 * flags.sensitivity
                curCam.CFrame = curCam.CFrame * CFrame.Angles(0, x, 0) * CFrame.Angles(y, 0, 0)
            elseif input.UserInputType == Enum.UserInputType.Touch and UIS.TouchEnabled then
                local d = input.Delta
                local x = -d.X * 0.002 * flags.sensitivity
                local y = -d.Y * 0.002 * flags.sensitivity
                -- only update if touch is on right half (preserve UI / left controls)
                if input.Position and curCam and input.Position.X >= (curCam.ViewportSize.X * 0.5) then
                    curCam.CFrame = curCam.CFrame * CFrame.Angles(0, x, 0) * CFrame.Angles(y, 0, 0)
                end
            end
        end))
    end
})

CamBox:AddSlider("Sensitivity", {
    Text = "Sensitivity",
    Default = flags.sensitivity,
    Min = 0.1,
    Max = 10.0,
    Rounding = 1,
    Callback = function(val) flags.sensitivity = val end
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
    Callback = function(val) flags.boostMode = val end
})

PerfBox:AddButton({ Text = "Apply Boost", Func = function()
    restoreBoost()
    applyBoost(flags.boostMode or "Lite")
end })

PerfBox:AddButton({ Text = "Restore Boost", Func = function() restoreBoost() end })

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
    clearAllConnections()
    workspace.CurrentCamera.CameraSubject = getHum(nil, false) or getChar(nil, false)
    if capSupported() then
        doSetCap(originalCap)
    end
    restoreBoost()
    destroyFOVCircle()
    _G.VerdictObsidianUI = nil
end)

_G.VerdictObsidianUI = Library
