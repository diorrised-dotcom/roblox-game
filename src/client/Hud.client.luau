-- In-game HUD in the title-screen style, plus the "fear" signal that drives every glitch effect:
-- flickering lights, darkness and a closing Stalker push UIStyle.Intensity up; dying tears the screen.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local UIStyle = require(script.Parent:WaitForChild("UIStyle"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local T = UIStyle.Theme
local Spaced = UIStyle.Spaced

UIStyle.Overlay()

local gui = Instance.new("ScreenGui")
gui.Name = "LightsOutHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")

local root = UIStyle.Frame(gui)
UIStyle.Responsive(root, 0.55, 1.2)

-- bottom-left: light + stamina + next light
local LEFT = 40
UIStyle.Label(root, { Text = Spaced("LIGHT STATUS"), TextSize = 12, TextColor3 = T.Dim, Position = UDim2.new(0, LEFT, 1, -168) })
local lightValue = UIStyle.Glitch(UIStyle.Label(root, {
	TextSize = 30,
	Size = UDim2.fromOffset(560, 40),
	Position = UDim2.new(0, LEFT, 1, -146),
}), 1)

UIStyle.Label(root, { Text = Spaced("STAMINA"), TextSize = 12, TextColor3 = T.Dim, Position = UDim2.new(0, LEFT, 1, -96) })
local barBack = UIStyle.Frame(root, {
	BackgroundColor3 = T.Dim,
	BackgroundTransparency = 0.75,
	Size = UDim2.fromOffset(280, 2),
	Position = UDim2.new(0, LEFT, 1, -66),
})
local bar = UIStyle.Rule(barBack, { Size = UDim2.fromScale(1, 1) })

local nextLight = UIStyle.Label(root, { TextSize = 14, Position = UDim2.new(0, LEFT, 1, -52) })

-- top-right: survivors + zone
local survivors = UIStyle.Label(root, {
	TextSize = 17,
	TextXAlignment = Enum.TextXAlignment.Right,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -40, 0, 34),
})
local zoneLabel = UIStyle.Glitch(UIStyle.Label(root, {
	TextSize = 14,
	TextColor3 = T.Dim,
	TextXAlignment = Enum.TextXAlignment.Right,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -40, 0, 62),
}), 0.5)

-- centre: status line flanked by glowing rules
local statusRow = UIStyle.Frame(root, { Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromScale(0, 0.13) })
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 22)
layout.Parent = statusRow
UIStyle.Rule(statusRow, { Size = UDim2.fromOffset(150, 2), LayoutOrder = 1 })
local status = UIStyle.Glitch(UIStyle.Label(statusRow, {
	TextSize = 22,
	AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.fromScale(0, 1),
	TextXAlignment = Enum.TextXAlignment.Center,
	LayoutOrder = 2,
}), 1)
UIStyle.Rule(statusRow, { Size = UDim2.fromOffset(150, 2), LayoutOrder = 3 })

local hint = UIStyle.Label(root, {
	TextSize = 13,
	TextColor3 = T.Dim,
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0),
	Size = UDim2.fromOffset(900, 22),
	Position = UDim2.new(0.5, 0, 0.13, 46),
})

-- big centre word for death / escape
local banner = UIStyle.Glitch(UIStyle.Label(root, {
	TextSize = 64,
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(1200, 80),
	Position = UDim2.fromScale(0.5, 0.45),
	Visible = false,
}), 2)

-- local colour grading that follows the fear level (client-only, does not replicate)
local grade = Instance.new("ColorCorrectionEffect")
grade.Name = "FearGrade"
grade.Parent = Lighting

local STATE_TEXT = {
	STABLE = { "STABLE", T.Text },
	FLICKERING = { "FLICKERING", T.Warning },
	CRITICAL = { "CRITICAL", T.Danger },
	EXPOSED = { "NO LIGHT", T.Danger },
}

local zonesFolder = workspace:WaitForChild("LightZones")
local lastState = nil
local wasSpectating = false
local wasEscaped = false
local lastAlive = 0
local bannerUntil = 0
local nextTimer = 0

local function showBanner(text, color, seconds)
	banner.Text = Spaced(text, 2)
	banner.TextColor3 = color
	bannerUntil = os.clock() + seconds
end

local function nearestStalker(position)
	local nearest = math.huge
	for _, stalker in CollectionService:GetTagged("Stalker") do
		if stalker:IsA("Model") then
			nearest = math.min(nearest, (stalker:GetPivot().Position - position).Magnitude)
		end
	end
	return nearest
end

RunService.RenderStepped:Connect(function(dt)
	local inMenu = player:GetAttribute("InMenu") == true
	gui.Enabled = not inMenu
	if inMenu then
		return
	end

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local aliveNow = hum ~= nil and hum.Health > 0
	local spectating = player:GetAttribute("Spectating") == true
	local escaped = player:GetAttribute("Escaped") == true

	-- light status
	local state = player:GetAttribute("LightState")
	local entry = STATE_TEXT[state]
	if entry and aliveNow and not spectating then
		lightValue.Text = Spaced(entry[1])
		lightValue.TextColor3 = entry[2]
		if state == "CRITICAL" or state == "EXPOSED" then
			lightValue.TextTransparency = if math.floor(os.clock() * 4) % 2 == 0 then 0 else 0.35
		else
			lightValue.TextTransparency = 0
		end
	else
		lightValue.Text = Spaced("--")
		lightValue.TextColor3 = T.Dim
		lightValue.TextTransparency = 0
	end

	-- light died on you / started flickering
	if state ~= lastState then
		if state == "EXPOSED" and lastState == "CRITICAL" then
			UIStyle.Burst(0.5, 1)
		elseif state == "FLICKERING" then
			UIStyle.Burst(0.2, 0.4)
		end
		lastState = state
	end

	-- stamina
	local stamina = player:GetAttribute("Stamina") or 1
	bar.Size = UDim2.fromScale(stamina, 1)
	local exhausted = player:GetAttribute("Exhausted") == true
	bar.BackgroundColor3 = if exhausted then T.Danger else T.Accent
	bar.Halo.BackgroundColor3 = bar.BackgroundColor3

	-- counters
	survivors.Text = Spaced("SURVIVORS")
		.. "   "
		.. Spaced(string.format("%d/%d", ReplicatedStorage:GetAttribute("Alive") or 0, ReplicatedStorage:GetAttribute("Total") or 0))
	zoneLabel.Text = Spaced(player:GetAttribute("ZoneLabel") or "")

	-- status line
	local text = ReplicatedStorage:GetAttribute("Status") or ""
	status.Text = Spaced(text)
	statusRow.Visible = text ~= ""

	-- death / escape banners
	if aliveNow and not spectating then
		lastAlive = os.clock()
	end
	if spectating and not wasSpectating and os.clock() - lastAlive < 3 then
		showBanner("CAUGHT", T.Danger, 2.5)
		UIStyle.Burst(1.2, 1.3)
	end
	if escaped and not wasEscaped then
		showBanner("ESCAPED", T.Accent, 3)
		UIStyle.Burst(0.5, 0.8)
	end
	wasSpectating, wasEscaped = spectating, escaped
	banner.Visible = os.clock() < bannerUntil
	hint.Text = if spectating then Spaced("CLICK OR TAP TO CHANGE VIEW") else ""

	-- fear level -> UIStyle.Intensity + colour grade
	local fear = 0.08
	if aliveNow and not spectating then
		if state == "FLICKERING" then
			fear = 0.3
		elseif state == "CRITICAL" then
			fear = 0.55
		elseif state == "EXPOSED" then
			fear = 0.5
		end
		if hrp then
			local d = nearestStalker(hrp.Position)
			fear = math.max(fear, math.clamp(1 - (d - 8) / 45, 0, 1))
		end
	elseif spectating then
		fear = 0.25
	end
	UIStyle.Intensity += (fear - UIStyle.Intensity) * math.min(1, dt * 4)
	local k = if UIStyle.Reduced then UIStyle.Intensity * 0.3 else UIStyle.Intensity
	grade.TintColor = Color3.new(1, 1, 1):Lerp(T.Accent, 0.08 + 0.18 * k)
	grade.Contrast = 0.05 + 0.25 * k
	grade.Saturation = -0.2 - 0.4 * k
	grade.Brightness = if not UIStyle.Reduced and k > 0.6 and math.random() < 0.04 then -0.15 else 0

	-- next light distance (throttled)
	nextTimer -= dt
	if nextTimer <= 0 then
		nextTimer = 0.2
		local order = (player:GetAttribute("ZoneOrder") or 0) + 1
		local target
		for _, model in zonesFolder:GetChildren() do
			local boundary = model:FindFirstChild("Boundary")
			if boundary and boundary:GetAttribute("Order") == order then
				target = boundary
			end
		end
		if not Config.UI.ShowNextLightDistance or spectating then
			nextLight.Text = ""
		elseif hrp and target then
			local dist = math.max(0, math.floor((target.Position - hrp.Position).Magnitude - 15))
			local dark = if target:GetAttribute("State") == "Off" then "   " .. Spaced("(DARK)") else ""
			nextLight.Text = Spaced("NEXT LIGHT:") .. "   " .. Spaced(tostring(dist)) .. "   " .. Spaced("STUDS") .. dark
		else
			nextLight.Text = Spaced("NEXT LIGHT:") .. "   - -"
		end
	end
end)
