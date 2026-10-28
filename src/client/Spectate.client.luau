-- Dead players watch surviving teammates in first person. Click / tap to cycle.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local index = 0
local current = nil

local function candidates()
	local list = {}
	for _, p in Players:GetPlayers() do
		local hum = p ~= player and p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and not p:GetAttribute("Spectating") then
			table.insert(list, hum)
		end
	end
	return list
end

local function cycle()
	local list = candidates()
	if #list == 0 then
		return
	end
	index = index % #list + 1
	current = list[index]
	camera.CameraSubject = current
end

local function restore()
	current = nil
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		camera.CameraSubject = hum
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not player:GetAttribute("Spectating") then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		cycle()
	end
end)

RunService.RenderStepped:Connect(function()
	if player:GetAttribute("Spectating") then
		if not current or current.Health <= 0 or not current.Parent then
			cycle()
		end
	elseif current then
		restore()
	end
end)
