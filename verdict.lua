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
local function safeDisconnect(conn)
    if conn then conn:Disconnect() end
end

local function clearAll()
    for k, v in pairs(conns) do
        safeDisconnect(v)
        conns[k] = nil
    end
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
    if hrp then
        hrp.CFrame = cf
    end
end

local function sortedPlayers()
    local list = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            table.insert(list, plr.Name)
        end
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
end

--// UI Init
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
WindUI:ToggleAcrylic(false)

local Window = WindUI:CreateWindow({
    Title = "Verdict",
    Author = "Just a simple script ♡",
    Icon = "smartphone",
    Size = UDim2.fromOffset(360, 400),
    Theme = "Dark",
    SideBarWidth = 120,
    Draggable = false
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
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                    end
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
                            if part:IsA("BasePart") then
                                part.CanCollide = false
                            end
                        end
                    end
                end
            end)
        else
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer and plr.Character then
                    for _, part in ipairs(plr.Character:GetDescendants()) do
                        if part:IsA("BasePart") then
                            part.CanCollide = true
                        end
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
                if hum then
                    hum:ChangeState(Enum.HumanoidStateType.Jumping)
                end
            end)
        end
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
                if mouse.Hit then
                    teleportTo(CFrame.new(mouse.Hit.Position + Vector3.new(0, 5, 0)))
                end
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
    Callback = function(opt)
        selectedPlayer = opt
    end
})

TeleTab:Button({
    Title = "Teleport ke Pemain",
    Callback = function()
        if selectedPlayer then
            local target = Players:FindFirstChild(selectedPlayer)
            local targetHRP = target and getHRP(target)
            if targetHRP then
                teleportTo(targetHRP.CFrame + Vector3.new(0, 3, 0))
            end
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
MiscTab:Section({ Title = "Spectate" })

local spectTarget
local SpectDropdown = MiscTab:Dropdown({
    Title = "Spectate Player",
    Values = sortedPlayers(),
    Searchable = true,
    Callback = function(opt)
        spectTarget = opt
    end
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

MiscTab:Section({ Title = "Position" })

local slotSelected = 1
MiscTab:Dropdown({
    Title = "Pilih Slot",
    Values = { "1", "2", "3", "4", "5" },
    Value = "1",
    Callback = function(opt)
        slotSelected = tonumber(opt)
    end
})

MiscTab:Button({
    Title = "Save Pos",
    Callback = function()
        local hrp = getHRP()
        if hrp then
            savedSlots[slotSelected] = hrp.Position
        end
    end
})

MiscTab:Button({
    Title = "Teleport Pos",
    Callback = function()
        local pos = savedSlots[slotSelected]
        if pos then
            teleportTo(CFrame.new(pos + Vector3.new(0, 5, 0)))
        end
    end
})

MiscTab:Button({
    Title = "Clear Slot",
    Callback = function()
        savedSlots[slotSelected] = nil
    end
})

MiscTab:Button({
    Title = "Clear All Slots",
    Callback = function()
        table.clear(savedSlots)
    end
})

--// Camera Section
MiscTab:Section({ Title = "Camera" })

local FreeCam = loadstring(game:HttpGet("https://raw.githubusercontent.com/Verdial/Verdict/refs/heads/main/fc_core.lua"))()
MiscTab:Toggle({
    Title = "Free Cam",
    Default = false,
    Callback = function(v)
        if v then
            FreeCam:Enable()
        else
            FreeCam:Disable()
        end
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
                    local delta = input.Delta
                    local x = -delta.X * 0.002 * flags.sensitivity
                    local y = -delta.Y * 0.002 * flags.sensitivity
                    Camera.CFrame = Camera.CFrame * CFrame.Angles(0, x, 0) * CFrame.Angles(y, 0, 0)
                end
            end)
        elseif UIS.TouchEnabled then
            conns.inputHandler = UIS.TouchMoved:Connect(function(touch)
                local pos = touch.Position
                local viewport = Camera.ViewportSize
                if pos.X < viewport.X * 0.5 then return end
                local delta = touch.Delta
                local x = -delta.X * 0.002 * flags.sensitivity
                local y = -delta.Y * 0.002 * flags.sensitivity
                Camera.CFrame = Camera.CFrame * CFrame.Angles(0, x, 0) * CFrame.Angles(y, 0, 0)
            end)
        end
    end
})

sensitivitySlider = MiscTab:Slider({
    Title = "Sensitivity [ " .. tostring(flags.sensitivity) .. " ]",
    Desc = "Atur seberapa responsif kamera saat digeser",
    Value = { Min = 0.1, Max = 10.0, Default = flags.sensitivity, Step = 0.1 },
    Callback = function(val)
        flags.sensitivity = val
        sensitivitySlider:SetTitle("Sensitivity [ " .. string.format("%.1f", val) .. " ]")
    end
})

--// Utility Section
MiscTab:Section({ Title = "Utility" })

-- Enhanced Boost FPS+
MiscTab:Toggle({
    Title = "Boost FPS+",
    Default = false,
    Callback = function(v)
        flags.fpsBoost = v
        safeDisconnect(conns.fpsBoostSweep)
        safeDisconnect(conns.fpsBoostWatcher)
        safeDisconnect(conns.fpsBoostEffects)

        if v then
            saveLighting()
            pcall(function()
                Lighting.GlobalShadows = false
                Lighting.FogEnd = 1e9
                Lighting.Brightness = 2
            end)

            local effectClasses = {
                "Atmosphere","BloomEffect","BlurEffect","DepthOfFieldEffect",
                "SunRaysEffect","ColorCorrectionEffect"
            }
            local storedEffects = {}
            flags._storedEffects = storedEffects

            local function disableEffect(inst)
                for _, cls in ipairs(effectClasses) do
                    if inst:IsA(cls) then
                        pcall(function()
                            storedEffects[inst] = inst.Enabled
                            inst.Enabled = false
                        end)
                        break
                    end
                end
            end

            for _, cls in ipairs(effectClasses) do
                local eff = Lighting:FindFirstChildOfClass(cls)
                if eff then disableEffect(eff) end
            end
            conns.fpsBoostEffects = Lighting.ChildAdded:Connect(disableEffect)

            local function disableIfHeavy(obj)
                if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Smoke")
                or obj:IsA("Fire") or obj:IsA("Beam") or obj:IsA("Highlight") then
                    pcall(function() obj.Enabled = false end)
                elseif obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight") then
                    pcall(function() obj.Enabled = false end)
                elseif obj:IsA("Explosion") then
                    pcall(function() obj.Visible = false end)
                end
            end

            for _, obj in ipairs(workspace:GetDescendants()) do
                disableIfHeavy(obj)
            end
            conns.fpsBoostWatcher = workspace.DescendantAdded:Connect(disableIfHeavy)

            local acc = 0
            conns.fpsBoostSweep = RunService.Heartbeat:Connect(function(dt)
                acc += dt
                if acc >= 0.5 then
                    acc = 0
                    for _, obj in ipairs(workspace:GetDescendants()) do
                        if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Smoke")
                        or obj:IsA("Fire") or obj:IsA("Beam") or obj:IsA("Highlight") then
                            pcall(function() obj.Enabled = false end)
                        end
                    end
                end
            end)
        else
            restoreLighting()
            safeDisconnect(conns.fpsBoostWatcher)
            safeDisconnect(conns.fpsBoostSweep)
            safeDisconnect(conns.fpsBoostEffects)
            if flags._storedEffects then
                for inst, state in pairs(flags._storedEffects) do
                    if inst and inst.Parent then
                        pcall(function() inst.Enabled = state end)
                    end
                end
                table.clear(flags._storedEffects)
                flags._storedEffects = nil
            end
        end
    end
})

-- FPS Cap Slider
flags.fpsCap = 60
local fpsCapSlider = MiscTab:Slider({
    Title = "FPS Cap [ " .. tostring(flags.fpsCap) .. " ]",
    Desc = "Atur batas FPS (30 - 120)",
    Value = { Min = 30, Max = 120, Default = flags.fpsCap, Step = 5 },
    Callback = function(val)
        flags.fpsCap = val
        fpsCapSlider:SetTitle("FPS Cap [ " .. tostring(val) .. " ]")
        if typeof(setfpscap) == "function" then
            setfpscap(val)
        else
            warn("⚠️ Exploit tidak support setfpscap(), FPS Cap tidak aktif.")
        end
    end
})

--// Unload
Window:Unload(function()
    clearAll()
    Camera.CameraSubject = getHum() or getChar()
    _G.VerdictWindUI = nil
end)

_G.VerdictWindUI = Window
