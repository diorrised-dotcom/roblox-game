-- Local audio: breathing when stamina is low, warning when your light flickers, sting when one dies.
-- Sound ids live in Config.Sounds; empty ids are skipped, so the game runs silently until filled in.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local function make(id, props)
	if id == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	for k, v in props do
		s[k] = v
	end
	s.Parent = SoundService
	return s
end

local breathing = make(Config.Sounds.Breathing, { Looped = true, Volume = 0 })
local offSting = make(Config.Sounds.LightOff, { Volume = 0.8 })
local warning = make(Config.Sounds.FlickerWarning, { Volume = 0.6 })

if breathing then
	breathing:Play()
	RunService.RenderStepped:Connect(function()
		local stamina = player:GetAttribute("Stamina") or 1
		local low = math.clamp((0.4 - stamina) / 0.4, 0, 1)
		breathing.Volume = low * low * 0.9
		breathing.PlaybackSpeed = 1 + low * 0.25
	end)
end

local function watch(model)
	local boundary = model:WaitForChild("Boundary")
	boundary:GetAttributeChangedSignal("State"):Connect(function()
		local state = boundary:GetAttribute("State")
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if state == "Off" and offSting and root and (boundary.Position - root.Position).Magnitude < 120 then
			offSting:Play()
		elseif state == "Flickering" and warning and player:GetAttribute("ZoneLabel") == boundary:GetAttribute("Label") then
			warning:Play()
		end
	end)
end

local folder = workspace:WaitForChild("LightZones")
for _, model in folder:GetChildren() do
	task.spawn(watch, model)
end
folder.ChildAdded:Connect(watch)
