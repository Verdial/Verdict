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
local originalLighting = {}

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

-- Load WindUI
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

-- Section Player
MainTab:Section({Title = "Player"})

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

-- Section Visual
MainTab:Section({Title = "Visual"})

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

-- Section Utility
MainTab:Section({Title = "Utility"})

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
TeleportTab:Section({Title = "Player Teleport"})

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

-- Section Spectate
MiscTab:Section({Title = "Spectate"})
local spectateTargetName

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

-- Section Position
MiscTab:Section({Title = "Position"})
local slotSelected = 1

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

-- Section Free Cam (pakai freecam kamu sendiri)
MiscTab:Section({Title = "Free Cam"})

local FreeCam = loadstring(game:HttpGet("RAW_LINK_FREECAM_KAMU"))()

MiscTab:Toggle({
    Title = "Free Cam",
    Default = false,
    Callback = function(v)
        if v then
            FreeCam:Enable()
            game.StarterGui:SetCore("SendNotification",{
                Title = "Free Cam",
                Text = "Aktif ✅",
                Duration = 1
            })
        else
            FreeCam:Disable()
            game.StarterGui:SetCore("SendNotification",{
                Title = "Free Cam",
                Text = "Nonaktif ❌",
                Duration = 1
            })
        end
    end
})

-- Unload Logic
function Window:Unload()
    clearAll()
    Workspace.CurrentCamera.CameraSubject = getHum() or getChar()
    _G.VerdictWindUI = nil
end

_G.VerdictWindUI = Window
