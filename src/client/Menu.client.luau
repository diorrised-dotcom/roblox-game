-- Title screen. A dark close-up of the Stalker's face behind scanlines, letter-spaced menu items,
-- glowing selection lines and one star per escape milestone. PLAY drops you into the lobby.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local UIStyle = require(script.Parent:WaitForChild("UIStyle"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local T = UIStyle.Theme
local Spaced = UIStyle.Spaced
local camera = workspace.CurrentCamera

player:SetAttribute("InMenu", true)
player.CameraMode = Enum.CameraMode.Classic
UIStyle.Overlay()

local controls
pcall(function()
	controls = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()
	controls:Disable()
end)

local ambience
if Config.Sounds.MenuAmbience ~= "" then
	ambience = Instance.new("Sound")
	ambience.SoundId = Config.Sounds.MenuAmbience
	ambience.Looped = true
	ambience.Volume = 0.5
	ambience.Parent = SoundService
	ambience:Play()
end

---------------------------------------------------------------------------------------------------
-- 3D backdrop: built locally, far from the facility, lit only by an accent rim light
---------------------------------------------------------------------------------------------------
local SCENE = Vector3.new(0, 420, -600)
local scene = Instance.new("Model")
scene.Name = "MenuScene"

local function piece(size, offset, color, material)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = CFrame.new(SCENE + offset)
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = scene
	return p
end

local black = Color3.fromRGB(8, 8, 10)
piece(Vector3.new(90, 90, 1), Vector3.new(0, 0, -14), Color3.new(0, 0, 0))
local head = piece(Vector3.new(2.2, 3, 2.2), Vector3.zero, Color3.fromRGB(16, 16, 20), Enum.Material.Metal)
piece(Vector3.new(0.6, 1.4, 0.6), Vector3.new(0, -2.1, 0), black)
piece(Vector3.new(2.8, 7, 1.6), Vector3.new(0, -6.3, 0), black, Enum.Material.Metal)
piece(Vector3.new(0.8, 10, 0.8), Vector3.new(-2.1, -6.5, 0.3), black)
piece(Vector3.new(0.8, 10, 0.8), Vector3.new(2.1, -6.5, 0.3), black)

local EYE_OFFSETS = { Vector3.new(-0.5, 0.3, 1.12), Vector3.new(0.5, 0.3, 1.12) }
local eyes = {}
for _, offset in EYE_OFFSETS do
	local eye = piece(Vector3.new(0.42, 0.2, 0.08), offset, T.Accent, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = T.Accent
	light.Range = 5
	light.Brightness = 1.5
	light.Parent = eye
	table.insert(eyes, eye)
end

local rim = piece(Vector3.new(0.2, 0.2, 0.2), Vector3.new(-3.5, 2.5, 2), black)
rim.Transparency = 1
local rimLight = Instance.new("PointLight")
rimLight.Color = T.Accent
rimLight.Range = 10
rimLight.Brightness = 4
rimLight.Parent = rim

scene.Parent = workspace

local baseCam = CFrame.lookAt(SCENE + Vector3.new(2.6, 0.4, 6.4), SCENE + Vector3.new(2.6, 0.1, 0))
local startedAt = os.clock()
local twitchUntil, nextTwitch = 0, os.clock() + 2.5

RunService:BindToRenderStep("MenuCamera", Enum.RenderPriority.Camera.Value + 1, function()
	local now = os.clock()
	local t = now - startedAt
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 50
	camera.CFrame = baseCam
		* CFrame.new(math.sin(t * 0.4) * 0.15, math.sin(t * 0.27) * 0.1, 0)
		* CFrame.Angles(0, math.sin(t * 0.3) * 0.02, 0)

	if now > nextTwitch then
		twitchUntil = now + 0.12 + math.random() * 0.12
		nextTwitch = now + 2 + math.random() * 5
		UIStyle.Burst(0.15, 0.5)
	end
	local twitching = now < twitchUntil
	local pose = if twitching
		then CFrame.Angles(0, math.rad(math.random(-8, 8)), math.rad(math.random(-14, 14)))
		else CFrame.Angles(0, math.sin(t * 0.5) * 0.08, math.rad(6))
	head.CFrame = CFrame.new(SCENE) * pose
	for i, eye in eyes do
		eye.CFrame = head.CFrame * CFrame.new(EYE_OFFSETS[i])
		eye.Transparency = if twitching and math.random() < 0.5 then 1 else 0
	end
	rimLight.Brightness = if twitching then math.random() * 4 else 4
end)

---------------------------------------------------------------------------------------------------
-- 2D menu
---------------------------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "LightsOutMenu"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 10
gui.Parent = player:WaitForChild("PlayerGui")

-- darken the right side so the text reads over the scene
local shade = UIStyle.Frame(gui, { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0 })
local shadeGradient = Instance.new("UIGradient")
shadeGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.45, 0.95),
	NumberSequenceKeypoint.new(1, 0.3),
})
shadeGradient.Parent = shade

local root = UIStyle.Frame(gui)
UIStyle.Responsive(root, 0.45, 1.3)

local COLUMN_X = 0.6
local TOP_Y = 0.4
local STEP = 70

-- title block, bottom right
UIStyle.Label(root, {
	Text = "THE BLACKOUT FACILITY",
	TextSize = 20,
	FontFace = Font.fromEnum(Enum.Font.GothamBold),
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0.5, 0, 1, -112),
})
UIStyle.Glitch(UIStyle.Label(root, {
	Text = Spaced("LIGHTS OUT", 2),
	TextSize = 60,
	TextXAlignment = Enum.TextXAlignment.Right,
	AnchorPoint = Vector2.new(1, 1),
	Size = UDim2.fromOffset(1000, 70),
	Position = UDim2.new(1, -48, 1, -36),
}), 1.2)

UIStyle.Label(root, {
	Text = "V0.1",
	TextSize = 13,
	TextColor3 = T.Dim,
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 14, 1, -10),
})

-- milestone stars (escapes), right edge
local MILESTONES = { 1, 5, 15, 30 }
local stars = {}
for i = 1, #MILESTONES do
	local star = UIStyle.Label(root, {
		Text = utf8.char(0x2605),
		TextSize = 58,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(80, 80),
		Position = UDim2.new(1, -95, 0.07 + (i - 1) * 0.095, 0),
	})
	table.insert(stars, star)
end

local function refreshStars()
	local stats = player:FindFirstChild("leaderstats")
	local escapes = stats and stats:FindFirstChild("Escapes")
	local count = if escapes then escapes.Value else 0
	for i, star in stars do
		local lit = count >= MILESTONES[i]
		star.TextColor3 = if lit then T.Text else T.Dim
		star.TextTransparency = if lit then 0 else 0.75
	end
end
refreshStars()
task.spawn(function()
	local stats = player:WaitForChild("leaderstats", 30)
	local escapes = stats and stats:WaitForChild("Escapes", 10)
	if escapes then
		escapes.Changed:Connect(refreshStars)
		refreshStars()
	end
end)

-- selection lines (left: screen edge -> item, right: short segment toward the stars)
local leftLine = UIStyle.Rule(root, {
	AnchorPoint = Vector2.new(0, 0.5),
	Size = UDim2.new(COLUMN_X, -28, 0, 2),
	Position = UDim2.new(0, 0, TOP_Y, 0),
})
local rightLine = UIStyle.Rule(root, {
	AnchorPoint = Vector2.new(0, 0.5),
	Size = UDim2.new(0.16, 0, 0, 2),
	Position = UDim2.new(0.86, 0, TOP_Y, 0),
})

local function moveLines(y)
	local info = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	TweenService:Create(leftLine, info, { Position = UDim2.new(0, 0, TOP_Y, y) }):Play()
	TweenService:Create(rightLine, info, { Position = UDim2.new(0.86, 0, TOP_Y, y) }):Play()
end

-- pages
local pages = {}
local function page(name)
	local f = UIStyle.Frame(root, { Name = name, Visible = false })
	pages[name] = f
	return f
end

local main = page("Main")
local items = {}
local selected = 1

local function selectItem(index)
	selected = index
	for i, item in items do
		item.TextTransparency = if i == index then 0 else 0.5
	end
	moveLines((index - 1) * STEP)
end

local function addItem(parent, index, text, onActivate)
	local b = Instance.new("TextButton")
	b.Name = text
	b.AutoButtonColor = false
	b.BackgroundTransparency = 1
	b.FontFace = UIStyle.Font
	b.Text = Spaced(text)
	b.TextSize = 28
	b.TextColor3 = T.Text
	b.TextXAlignment = Enum.TextXAlignment.Left
	b.AnchorPoint = Vector2.new(0, 0.5)
	b.Size = UDim2.fromOffset(420, 46)
	b.Position = UDim2.new(COLUMN_X, 0, TOP_Y, (index - 1) * STEP)
	local stroke = Instance.new("UIStroke")
	stroke.Color = T.Accent
	stroke.Transparency = 0.5
	stroke.Parent = b
	b.Parent = parent
	UIStyle.Glitch(b, 0.6)
	b.MouseEnter:Connect(function()
		if parent == main and selected ~= index then
			selectItem(index)
			UIStyle.Burst(0.06, 0.25)
		end
	end)
	b.SelectionGained:Connect(function()
		if parent == main then
			selectItem(index)
		end
	end)
	b.Activated:Connect(function()
		if parent == main then
			selectItem(index)
		end
		onActivate()
	end)
	return b
end

local function show(name)
	for n, f in pages do
		f.Visible = n == name
	end
	leftLine.Visible = name == "Main"
	rightLine.Visible = name == "Main"
	UIStyle.Burst(0.2, 0.6)
end

-- RULES page
local rules = page("Rules")
local RULES = {
	{ "STAY IN THE LIGHT", "Light protects you only while it is on. The dark is where they hunt." },
	{ "WHEN IT FLICKERS, MOVE", "Every light fails. Find the next one before yours goes out." },
	{ "SPRINT AND JUMP", "Shift to sprint, Space to jump. On mobile, hold JUMP SPRINT." },
	{ "RESTORE POWER", "Turn on the 3 generator switches, then run for the exit. Together." },
}
for i, rule in RULES do
	local y = (i - 1) * 74 - 80
	UIStyle.Label(rules, {
		Text = Spaced(rule[1]),
		TextSize = 20,
		Position = UDim2.new(COLUMN_X - 0.12, 0, TOP_Y, y),
	})
	UIStyle.Label(rules, {
		Text = rule[2],
		TextSize = 14,
		TextColor3 = T.Dim,
		TextWrapped = true,
		Size = UDim2.fromOffset(620, 36),
		Position = UDim2.new(COLUMN_X - 0.12, 0, TOP_Y, y + 28),
	})
end

-- SETTINGS page
local settingsPage = page("Settings")
local function toggleText(label, on, onText, offText)
	return Spaced(label) .. "      " .. Spaced(if on then onText else offText)
end
local effectsButton
effectsButton = addItem(settingsPage, 0, "", function()
	UIStyle.Reduced = not UIStyle.Reduced
	effectsButton.Text = toggleText("SCREEN FX", not UIStyle.Reduced, "FULL", "REDUCED")
end)
effectsButton.Text = toggleText("SCREEN FX", not UIStyle.Reduced, "FULL", "REDUCED")
effectsButton.Size = UDim2.fromOffset(640, 46)
effectsButton.TextSize = 22
effectsButton.Position = UDim2.new(COLUMN_X - 0.12, 0, TOP_Y, -40)

local distanceButton
distanceButton = addItem(settingsPage, 0, "", function()
	Config.UI.ShowNextLightDistance = not Config.UI.ShowNextLightDistance
	distanceButton.Text = toggleText("LIGHT DISTANCE", Config.UI.ShowNextLightDistance, "ON", "OFF")
end)
distanceButton.Text = toggleText("LIGHT DISTANCE", Config.UI.ShowNextLightDistance, "ON", "OFF")
distanceButton.Size = UDim2.fromOffset(640, 46)
distanceButton.TextSize = 22
distanceButton.Position = UDim2.new(COLUMN_X - 0.12, 0, TOP_Y, 30)

-- STATS page
local statsPage = page("Stats")
local statLabels = {}
for i, name in { "XP", "COINS", "ESCAPES" } do
	statLabels[name] = UIStyle.Label(statsPage, {
		TextSize = 24,
		Size = UDim2.fromOffset(640, 34),
		Position = UDim2.new(COLUMN_X - 0.12, 0, TOP_Y, (i - 2) * 60),
	})
end
local function refreshStats()
	local stats = player:FindFirstChild("leaderstats")
	for name, label in statLabels do
		local value = stats and stats:FindFirstChild(name == "COINS" and "Coins" or name == "ESCAPES" and "Escapes" or "XP")
		label.Text = Spaced(name) .. "      " .. Spaced(tostring(if value then value.Value else 0))
	end
end

for _, p in { rules, settingsPage, statsPage } do
	local back = addItem(p, 0, "BACK", function()
		show("Main")
	end)
	back.TextSize = 20
	back.Position = UDim2.new(COLUMN_X - 0.12, 0, TOP_Y, 230)
end

-- PLAY
local fade = UIStyle.Frame(gui, { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, ZIndex = 50 })
local leaving = false

local function play()
	if leaving then
		return
	end
	leaving = true
	UIStyle.Burst(0.7, 1.2)
	Remotes.Ready:FireServer()

	local out = TweenService:Create(fade, TweenInfo.new(0.35), { BackgroundTransparency = 0 })
	out:Play()
	out.Completed:Wait()

	RunService:UnbindFromRenderStep("MenuCamera")
	scene:Destroy()
	if ambience then
		ambience:Stop()
	end
	root.Visible = false
	shade.Visible = false

	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		camera.CameraSubject = hum
	end
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	if controls then
		controls:Enable()
	end
	player:SetAttribute("InMenu", false)

	local back = TweenService:Create(fade, TweenInfo.new(0.6), { BackgroundTransparency = 1 })
	back:Play()
	back.Completed:Wait()
	gui:Destroy()
end

table.insert(items, addItem(main, 1, "PLAY", play))
table.insert(items, addItem(main, 2, "RULES", function()
	show("Rules")
end))
table.insert(items, addItem(main, 3, "SETTINGS", function()
	show("Settings")
end))
table.insert(items, addItem(main, 4, "STATS", function()
	refreshStats()
	show("Stats")
end))

show("Main")
selectItem(1)
UIStyle.Burst(0.5, 1)
