-- The look of every screen in LIGHTS OUT: wide letter-spaced type with a soft glow, chromatic
-- "ghost" text that tears apart in bursts, scanlines, rolling CRT bands, static and a vignette.
-- UIStyle.Intensity (0 calm .. 1 panic) is set by the HUD and drives how broken the screen looks.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Theme = Config.UI.Theme

local UIStyle = {}
UIStyle.Theme = Theme
UIStyle.Intensity = 0
UIStyle.Reduced = Config.UI.ReducedEffects

local ok, wideFont = pcall(function()
	return Font.fromEnum(Enum.Font.Michroma)
end)
UIStyle.Font = if ok then wideFont else Font.fromEnum(Enum.Font.Gotham)

local glitchers = {} -- [TextLabel|TextButton] = entry
local burstUntil, burstStrength = 0, 0
local overlay = nil

local glitchSound
if Config.Sounds.Glitch ~= "" then
	glitchSound = Instance.new("Sound")
	glitchSound.SoundId = Config.Sounds.Glitch
	glitchSound.Volume = 0.35
	glitchSound.Parent = SoundService
end

-- "NEW GAME" -> "N E W   G A M E" (Roblox text has no letter-spacing property)
function UIStyle.Spaced(text, gap)
	local pad = string.rep(" ", gap or 1)
	local words = string.split(text, " ")
	for i, word in words do
		words[i] = (word:gsub(".", "%0" .. pad)):sub(1, -(#pad + 1))
	end
	return table.concat(words, string.rep(pad, 3))
end

local function apply(object, props)
	if props then
		for k, v in props do
			object[k] = v
		end
	end
end

function UIStyle.Frame(parent, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, 1)
	apply(f, props)
	f.Parent = parent
	return f
end

local function glow(object, mode)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Accent
	stroke.Transparency = 0.55
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Contextual
	stroke.Parent = object
	return stroke
end

function UIStyle.Label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = UIStyle.Font
	l.TextColor3 = Theme.Text
	l.TextSize = 18
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Size = UDim2.fromOffset(500, 26)
	l.Text = ""
	apply(l, props)
	glow(l)
	l.Parent = parent
	return l
end

-- Glowing horizontal rule, like the selection line on the title screen.
function UIStyle.Rule(parent, props)
	local line = Instance.new("Frame")
	line.Name = "Rule"
	line.BorderSizePixel = 0
	line.BackgroundColor3 = Theme.Accent
	line.Size = UDim2.new(0, 100, 0, 2)
	apply(line, props)
	local halo = Instance.new("Frame")
	halo.Name = "Halo"
	halo.BorderSizePixel = 0
	halo.BackgroundColor3 = Theme.Accent
	halo.BackgroundTransparency = 0.82
	halo.AnchorPoint = Vector2.new(0, 0.5)
	halo.Position = UDim2.fromScale(0, 0.5)
	halo.Size = UDim2.new(1, 0, 0, 8)
	halo.Parent = line
	line.Parent = parent
	return line
end

-- Adds two coloured ghost copies of the text that split apart in random bursts.
function UIStyle.Glitch(label, strength)
	local entry = {
		label = label,
		strength = strength or 1,
		ghosts = {},
		nextBurst = os.clock() + math.random() * 2,
		burstUntil = 0,
	}
	for _, color in { Theme.GhostA, Theme.GhostB } do
		local g = Instance.new("TextLabel")
		g.Name = "Ghost"
		g.BackgroundTransparency = 1
		g.Size = UDim2.fromScale(1, 1)
		g.FontFace = label.FontFace
		g.TextSize = label.TextSize
		g.TextXAlignment = label.TextXAlignment
		g.TextYAlignment = label.TextYAlignment
		g.TextColor3 = color
		g.TextTransparency = 1
		g.Parent = label
		table.insert(entry.ghosts, g)
	end
	glitchers[label] = entry
	return label
end

-- Sharp panel button with a glowing border (used for the mobile JUMP SPRINT / SPRINT buttons).
function UIStyle.Button(parent, text, props)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundColor3 = Theme.Panel
	b.BackgroundTransparency = 0.35
	b.FontFace = UIStyle.Font
	b.TextColor3 = Theme.Text
	b.TextSize = 15
	b.Text = text
	apply(b, props)
	local border = glow(b, Enum.ApplyStrokeMode.Border)
	border.Name = "Border"
	border.Thickness = 1.5
	border.Transparency = 0.15
	-- a few scanlines inside the button
	for i = 1, 6 do
		UIStyle.Frame(b, {
			BackgroundTransparency = 0.85,
			BackgroundColor3 = Color3.new(0, 0, 0),
			Size = UDim2.new(1, 0, 0, 1),
			Position = UDim2.fromScale(0, i / 7),
		})
	end
	UIStyle.Glitch(b, 0.7)
	b.Parent = parent
	return b
end

-- Keeps offset-based layouts readable from phones to 4K: wraps a full-screen frame in a UIScale.
function UIStyle.Responsive(frame, minScale, maxScale)
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local camera = workspace.CurrentCamera
	local function update()
		local vp = camera.ViewportSize
		local s = math.clamp(math.min(vp.X / 1600, vp.Y / 900), minScale or 0.5, maxScale or 1.25)
		scale.Scale = s
		frame.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	update()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	return scale
end

-- A short burst of static, tearing and ghosting across the whole screen.
local lastSound = 0
function UIStyle.Burst(seconds, strength)
	local now = os.clock()
	if now < burstUntil then
		burstStrength = math.max(burstStrength, strength or 0.8)
	else
		burstStrength = strength or 0.8
	end
	burstUntil = math.max(burstUntil, now + seconds)
	if glitchSound and not UIStyle.Reduced and now - lastSound > 0.15 then
		lastSound = now
		glitchSound.PlaybackSpeed = 0.8 + math.random() * 0.5
		glitchSound:Play()
	end
end

-- Full-screen effects layer that sits above every other GUI (it never blocks input).
function UIStyle.Overlay()
	if overlay then
		return overlay
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "GlitchOverlay"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100

	local tint = UIStyle.Frame(gui, { BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.975, ZIndex = 1 })

	local bands = {}
	for _ = 1, 5 do
		local band = UIStyle.Frame(gui, {
			BackgroundColor3 = Theme.Accent,
			BackgroundTransparency = 0.93,
			Size = UDim2.new(1, 0, 0, math.random(2, 28)),
			ZIndex = 2,
		})
		local streak = Instance.new("UIGradient")
		streak.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.7),
			NumberSequenceKeypoint.new(0.35, 0),
			NumberSequenceKeypoint.new(0.7, 0.2),
			NumberSequenceKeypoint.new(1, 0.8),
		})
		streak.Parent = band
		table.insert(bands, { frame = band, y = math.random(), speed = 0.01 + math.random() * 0.035 })
	end

	local static = {}
	for _ = 1, 40 do
		table.insert(static, UIStyle.Frame(gui, { Visible = false, ZIndex = 3 }))
	end

	local scan = UIStyle.Frame(gui, { ZIndex = 4 })
	local LINES = 260
	for i = 0, LINES - 1 do
		UIStyle.Frame(scan, {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.78,
			Size = UDim2.new(1, 0, 0, 1),
			Position = UDim2.fromScale(0, i / LINES),
			ZIndex = 4,
		})
	end

	local vignette = {}
	for _, spec in {
		{ UDim2.fromScale(1, 0.28), UDim2.fromScale(0, 0), 90 },
		{ UDim2.fromScale(1, 0.28), UDim2.fromScale(0, 0.72), -90 },
		{ UDim2.fromScale(0.22, 1), UDim2.fromScale(0, 0), 0 },
		{ UDim2.fromScale(0.22, 1), UDim2.fromScale(0.78, 0), 180 },
	} do
		local edge = UIStyle.Frame(gui, {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.4,
			Size = spec[1],
			Position = spec[2],
			ZIndex = 5,
		})
		local fade = Instance.new("UIGradient")
		fade.Rotation = spec[3]
		fade.Transparency = NumberSequence.new(0, 1)
		fade.Parent = edge
		table.insert(vignette, edge)
	end

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	overlay = { gui = gui, tint = tint, bands = bands, static = static, scan = scan, vignette = vignette }
	return overlay
end

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	local reduced = UIStyle.Reduced
	local bursting = now < burstUntil
	local level = math.clamp(UIStyle.Intensity + (if bursting then burstStrength else 0), 0, 1.5)
	if reduced then
		level *= 0.3
		bursting = false
	end

	for label, e in glitchers do
		if not label.Parent then
			glitchers[label] = nil
			continue
		end
		local k = e.strength * (0.3 + level)
		if now >= e.nextBurst then
			e.burstUntil = now + 0.04 + math.random() * 0.14
			e.nextBurst = now + (0.6 + math.random() * 3.5) / (0.4 + k)
		end

		local a, b = e.ghosts[1], e.ghosts[2]
		a.Text, b.Text = label.Text, label.Text
		a.TextSize, b.TextSize = label.TextSize, label.TextSize

		local ghostT
		if (now < e.burstUntil or (bursting and math.random() < 0.5)) and not reduced then
			local spread = 2 + 8 * k
			a.Position = UDim2.fromOffset(-spread * math.random(), (math.random() - 0.5) * 3 * k)
			b.Position = UDim2.fromOffset(spread * math.random(), (math.random() - 0.5) * 3 * k)
			ghostT = 0.3
		else
			a.Position = UDim2.fromOffset(-1, 0)
			b.Position = UDim2.fromOffset(1, 0)
			ghostT = 0.82
		end
		-- ghosts fade with their label
		local t = 1 - (1 - ghostT) * (1 - label.TextTransparency)
		a.TextTransparency, b.TextTransparency = t, t
	end

	if not overlay then
		return
	end
	local calm = math.min(level, 1)
	overlay.tint.BackgroundTransparency = 0.975 - 0.05 * calm
	overlay.scan.Visible = true
	for _, edge in overlay.vignette do
		edge.BackgroundTransparency = 0.4 - 0.35 * calm
	end

	for _, band in overlay.bands do
		band.y = (band.y + band.speed * dt * (1 + level * 3)) % 1.15
		local y = band.y - 0.05
		local t = 0.94 - 0.07 * calm
		if bursting and math.random() < 0.25 then
			y = math.random()
			t = 0.72
		end
		band.frame.Position = UDim2.fromScale(0, y)
		band.frame.BackgroundTransparency = t
		band.frame.Visible = not reduced or band == overlay.bands[1]
	end

	for i, block in overlay.static do
		if bursting and i <= math.floor(10 + 30 * math.min(burstStrength, 1)) then
			block.Visible = true
			local wide = math.random() < 0.3
			block.Size = if wide
				then UDim2.new(1, 0, 0, math.random(1, 4))
				else UDim2.fromOffset(math.random(6, 160), math.random(2, 14))
			block.Position = UDim2.new(if wide then 0 else math.random(), 0, math.random(), 0)
			block.BackgroundColor3 = if math.random() < 0.6 then Theme.Accent else Color3.new(1, 1, 1)
			block.BackgroundTransparency = 0.35 + math.random() * 0.5
		else
			block.Visible = false
		end
	end
end)

return UIStyle
