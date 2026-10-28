-- Minimal HUD: light status, stamina, next light distance, survivors, zone, centre status line.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local gui = Instance.new("ScreenGui")
gui.Name = "LightsOutHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function label(parent, text, size, position, anchor, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Code
	l.Text = text
	l.TextSize = size
	l.TextColor3 = Color3.fromRGB(215, 215, 215)
	l.TextStrokeTransparency = 0.6
	l.Size = UDim2.fromOffset(300, size + 6)
	l.Position = position
	l.AnchorPoint = anchor or Vector2.zero
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

-- bottom-left panel
local panel = Instance.new("Frame")
panel.BackgroundTransparency = 1
panel.Size = UDim2.fromOffset(320, 130)
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 24, 1, -24)
panel.Parent = gui

label(panel, "LIGHT STATUS", 12, UDim2.fromOffset(0, 0)).TextColor3 = Color3.fromRGB(140, 140, 140)
local lightStatus = label(panel, "--", 24, UDim2.fromOffset(0, 14))
label(panel, "STAMINA", 12, UDim2.fromOffset(0, 54)).TextColor3 = Color3.fromRGB(140, 140, 140)

local barBack = Instance.new("Frame")
barBack.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
barBack.BorderSizePixel = 0
barBack.Size = UDim2.fromOffset(220, 8)
barBack.Position = UDim2.fromOffset(0, 72)
barBack.Parent = panel
local bar = Instance.new("Frame")
bar.BorderSizePixel = 0
bar.BackgroundColor3 = Color3.fromRGB(210, 210, 210)
bar.Size = UDim2.fromScale(1, 1)
bar.Parent = barBack

local nextLight = label(panel, "NEXT LIGHT: --", 16, UDim2.fromOffset(0, 92))

-- top-right
local survivors = label(gui, "SURVIVORS: -", 18, UDim2.new(1, -24, 0, 24), Vector2.new(1, 0), Enum.TextXAlignment.Right)
local zoneLabel = label(gui, "", 18, UDim2.new(1, -24, 0, 50), Vector2.new(1, 0), Enum.TextXAlignment.Right)

-- centre
local status = label(gui, "", 26, UDim2.new(0.5, 0, 0.12, 0), Vector2.new(0.5, 0), Enum.TextXAlignment.Center)
status.Size = UDim2.fromOffset(700, 34)
local hint = label(gui, "", 16, UDim2.new(0.5, 0, 0.12, 36), Vector2.new(0.5, 0), Enum.TextXAlignment.Center)
hint.Size = UDim2.fromOffset(700, 22)
hint.TextColor3 = Color3.fromRGB(150, 150, 150)

local STATE_COLORS = {
	STABLE = Color3.fromRGB(230, 230, 230),
	FLICKERING = Color3.fromRGB(255, 190, 70),
	CRITICAL = Color3.fromRGB(255, 70, 60),
	EXPOSED = Color3.fromRGB(255, 70, 60),
}

local zonesFolder = workspace:WaitForChild("LightZones")
local nextTimer = 0

RunService.RenderStepped:Connect(function(dt)
	local state = player:GetAttribute("LightState") or "--"
	local shown = if state == "EXPOSED" then "NO LIGHT" else state
	if state == "CRITICAL" or state == "EXPOSED" then
		shown ..= if math.floor(os.clock() * 4) % 2 == 0 then " !" else ""
	end
	lightStatus.Text = shown
	lightStatus.TextColor3 = STATE_COLORS[state] or Color3.fromRGB(150, 150, 150)

	local stamina = player:GetAttribute("Stamina") or 1
	bar.Size = UDim2.fromScale(stamina, 1)
	bar.BackgroundColor3 = if player:GetAttribute("Exhausted") then Color3.fromRGB(200, 60, 50) else Color3.fromRGB(210, 210, 210)

	survivors.Text = string.format("SURVIVORS: %d/%d", ReplicatedStorage:GetAttribute("Alive") or 0, ReplicatedStorage:GetAttribute("Total") or 0)
	zoneLabel.Text = player:GetAttribute("ZoneLabel") or ""

	local text = ReplicatedStorage:GetAttribute("Status") or ""
	status.Text = text
	if player:GetAttribute("Spectating") then
		hint.Text = "YOU WERE CAUGHT  -  CLICK TO CHANGE VIEW"
	else
		hint.Text = ""
	end

	nextTimer -= dt
	if nextTimer <= 0 then
		nextTimer = 0.2
		if not Config.UI.ShowNextLightDistance then
			nextLight.Text = ""
			return
		end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local order = (player:GetAttribute("ZoneOrder") or 0) + 1
		local target
		for _, model in zonesFolder:GetChildren() do
			local boundary = model:FindFirstChild("Boundary")
			if boundary and boundary:GetAttribute("Order") == order then
				target = boundary
			end
		end
		if root and target then
			local dist = math.max(0, math.floor((target.Position - root.Position).Magnitude - 15))
			local dark = if target:GetAttribute("State") == "Off" then " (DARK)" else ""
			nextLight.Text = string.format("NEXT LIGHT: %d STUDS%s", dist, dark)
		else
			nextLight.Text = "NEXT LIGHT: --"
		end
	end
end)
