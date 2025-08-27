local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local windows = {}
local conns = {}
local flags = {}
local customSpeed = 16
local originalLighting = {}

local function notify(msg)
    pcall(function()
        game.StarterGui:SetCore("SendNotification", {
            Title = "Verdict",
            Text = msg,
            Duration = 3
        })
    end)
end

local function getCharacter(player)
    player = player or LocalPlayer
    return player.Character or player.CharacterAdded:Wait()
end

local function getHumanoid(player)
    local char = getCharacter(player)
    return char:FindFirstChildOfClass("Humanoid")
end

local function sortedPlayerNames()
    local list = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        table.insert(list, plr.Name)
    end
    table.sort(list)
    return list
end

local function setConn(name, conn)
    if conns[name] then conns[name]:Disconnect() end
    conns[name] = conn
end

local function clearAllConns()
    for k, c in pairs(conns) do
        if c then c:Disconnect() end
        conns[k] = nil
    end
end

for k, v in pairs(Lighting:GetChildren()) do
    originalLighting[v.Name] = v
end

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
local Window = Rayfield:CreateWindow({
    Name = "Verdict",
    LoadingTitle = "Verdict",
    LoadingSubtitle = "by Verdict",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "Verdict",
        FileName = "Verdict_Config"
    },
    KeySystem = false,
})

local MainTab = Window:CreateTab("Main", 4483362458)
windows.Main = MainTab

MainTab:CreateSlider({
    Name = "WalkSpeed",
    Range = {16, 500},
    Increment = 1,
    CurrentValue = 16,
    Flag = "WalkSpeed",
    Callback = function(val)
        customSpeed = val
        local hum = getHumanoid()
        if hum then
            hum.WalkSpeed = val
        end
    end
})

MainTab:CreateSlider({
    Name = "JumpPower",
    Range = {50, 500},
    Increment = 1,
    CurrentValue = 50,
    Flag = "JumpPower",
    Callback = function(val)
        local hum = getHumanoid()
        if hum then
            hum.JumpPower = val
        end
    end
})

local MiscTab = Window:CreateTab("Misc", 4483362458)
windows.Misc = MiscTab

MiscTab:CreateSection("Spectate Player")
local spectateTargetName = nil
local viewDiedConn = nil
local viewChangedConn = nil

local SpectateDropdown = MiscTab:CreateDropdown({
    Name = "Pilih Pemain",
    Options = sortedPlayerNames(),
    CurrentOption = {},
    MultipleOptions = false,
    Flag = "SpectateDropdown",
    Callback = function(opt)
        spectateTargetName = (typeof(opt) == "table" and opt[1]) or opt
    end
})

setConn("specAdd", Players.PlayerAdded:Connect(function()
    pcall(function() SpectateDropdown:Refresh(sortedPlayerNames(), true) end)
end))
setConn("specRem", Players.PlayerRemoving:Connect(function()
    pcall(function() SpectateDropdown:Refresh(sortedPlayerNames(), true) end)
end))

MiscTab:CreateButton({
    Name = "Mulai Spectate",
    Callback = function()
        if not spectateTargetName or spectateTargetName == "" then
            notify("Pilih pemain terlebih dahulu.")
            return
        end
        local target = Players:FindFirstChild(spectateTargetName)
        if not target or not target.Character then
            notify("Pemain tidak valid atau belum spawn.")
            return
        end
        if viewDiedConn then viewDiedConn:Disconnect() viewDiedConn = nil end
        if viewChangedConn then viewChangedConn:Disconnect() viewChangedConn = nil end

        Workspace.CurrentCamera.CameraSubject = target.Character
        viewDiedConn = target.CharacterAdded:Connect(function()
            repeat task.wait() until target.Character and target.Character:FindFirstChild("HumanoidRootPart")
            Workspace.CurrentCamera.CameraSubject = target.Character
        end)
        viewChangedConn = Workspace.CurrentCamera:GetPropertyChangedSignal("CameraSubject"):Connect(function()
            if target and target.Character then
                Workspace.CurrentCamera.CameraSubject = target.Character
            end
        end)
        notify("Spectating: " .. spectateTargetName)
    end
})

MiscTab:CreateButton({
    Name = "Berhenti Spectate",
    Callback = function()
        if viewDiedConn then viewDiedConn:Disconnect() viewDiedConn = nil end
        if viewChangedConn then viewChangedConn:Disconnect() viewChangedConn = nil end
        local char = getCharacter()
        if char then
            local humanoid = getHumanoid()
            if humanoid then
                Workspace.CurrentCamera.CameraSubject = humanoid
            else
                Workspace.CurrentCamera.CameraSubject = char
            end
        end
        notify("Spectate dihentikan.")
    end
})

MiscTab:CreateSection("Teleport Player")
local teleportTarget = nil
local TeleportDropdown = MiscTab:CreateDropdown({
    Name = "Pilih Pemain",
    Options = sortedPlayerNames(),
    CurrentOption = {},
    MultipleOptions = false,
    Flag = "TeleportDropdown",
    Callback = function(opt)
        teleportTarget = (typeof(opt) == "table" and opt[1]) or opt
    end
})

setConn("teleAdd", Players.PlayerAdded:Connect(function()
    pcall(function() TeleportDropdown:Refresh(sortedPlayerNames(), true) end)
end))
setConn("teleRem", Players.PlayerRemoving:Connect(function()
    pcall(function() TeleportDropdown:Refresh(sortedPlayerNames(), true) end)
end))

MiscTab:CreateButton({
    Name = "Teleport",
    Callback = function()
        if not teleportTarget or teleportTarget == "" then
            notify("Pilih pemain dulu.")
            return
        end
        local target = Players:FindFirstChild(teleportTarget)
        if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
            local hrp = getCharacter().HumanoidRootPart
            hrp.CFrame = target.Character.HumanoidRootPart.CFrame + Vector3.new(0,2,0)
            notify("Teleport ke: " .. teleportTarget)
        else
            notify("Gagal teleport, pemain tidak valid.")
        end
    end
})

MiscTab:CreateSection("Unload Script")
MiscTab:CreateButton({
    Name = "Unload Verdict",
    Callback = function()
        clearAllConns()
        for _, win in pairs(windows) do
            pcall(function()
                if typeof(win) == "table" and win.Destroy then
                    win:Destroy()
                elseif typeof(win) == "Instance" then
                    win:Destroy()
                end
            end)
        end
        windows = {}
        flags = {}
        customSpeed = 16
        if originalLighting and next(originalLighting) then
            for k,v in pairs(originalLighting) do
                pcall(function() Lighting[k] = v end)
            end
        end
        notify("Verdict sudah di-unload.")
    end
})
