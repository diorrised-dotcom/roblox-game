-- LIGHTS OUT installer. Paste into View > Command Bar and press Enter (run once in an empty place).
local SSS = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")
local SP = game:GetService("StarterPlayer")
local roots = { ReplicatedStorage = RS, ServerScriptService = SSS, StarterPlayerScripts = SP:WaitForChild("StarterPlayerScripts") }
local function folder(root, name)
	local old = roots[root]:FindFirstChild(name)
	if old then old:Destroy() end
	local f = Instance.new("Folder"); f.Name = name; f.Parent = roots[root]; return f
end
local function add(parent, class, name, source)
	local s = Instance.new(class); s.Name = name; s.Source = source; s.Parent = parent
end

do local f = folder("ReplicatedStorage", "Shared")
add(f, "ModuleScript", "Config", [=====[
-- Central tuning table. Every value here is a starting target to be playtested in Studio.
return {
	Movement = {
		WalkSpeed = 14,
		SprintSpeed = 22,
		StaminaSeconds = 5, -- continuous sprint time
		RecoverSeconds = 4, -- empty -> full
		ExhaustRecoverSeconds = 1, -- stamina needed again after hitting empty
		JumpHeight = 7.5,
		Gravity = 230, -- default is 196.2; higher = snappier, less floaty
		FallKillY = -60, -- pits are at y = -6, so this only catches true falls
	},

	Light = {
		Stable = 20,
		Flicker = 7,
		Critical = 3,
		RelightDelay = 12, -- seconds a failed light stays dark before it resets (unarmed)
		BlackoutScale = 0.5, -- multiplies Stable + Flicker once the generator is on
	},

	GraceSeconds = 1.5, -- time exposed before a monster is allowed to kill

	Stalker = {
		PatrolSpeed = 8,
		ChaseSpeedMin = 12,
		ChaseSpeedMax = 21,
		AccelSeconds = 2.5,
		DetectRange = 70,
		LoseRange = 110,
		KillRange = 4.5,
		BlackoutSpeedScale = 1.15,
	},

	Round = {
		MaxPlayers = 6,
		MinPlayers = 2,
		IntermissionSeconds = 10,
		CountdownSeconds = 5,
		SwitchesRequired = 3,
		SwitchHoldSeconds = 2,
		ExitGraceSeconds = 10, -- after the first escape, time left for teammates
		RoundTimeLimit = 15 * 60,
		EndScreenSeconds = 8,
	},

	Rewards = {
		Escaped = { XP = 100, Coins = 50 },
		SurvivedNotEscaped = { XP = 40, Coins = 15 },
		Participated = { XP = 20, Coins = 5 },
		TeamVictoryBonus = { XP = 25, Coins = 10 },
	},

	-- Paste Roblox asset ids ("rbxassetid://123") here. Empty = that sound is skipped.
	Sounds = {
		LightHum = "",
		LightOff = "",
		FlickerWarning = "",
		Breathing = "",
		StalkerSteps = "",
		Glitch = "", -- short static burst used by the UI
		MenuAmbience = "",
	},

	UI = {
		ShowNextLightDistance = true, -- turn off for harder modes
		ReducedEffects = false, -- players can also toggle this in SETTINGS (less flashing/static)

		-- One accent colour drives every glow, line and CRT band.
		-- Try Color3.fromRGB(140, 90, 255) for purple, (255, 60, 60) for red, (255, 180, 80) for amber.
		Theme = {
			Accent = Color3.fromRGB(110, 160, 255),
			Text = Color3.fromRGB(226, 230, 240),
			Dim = Color3.fromRGB(105, 110, 128),
			Warning = Color3.fromRGB(255, 190, 80),
			Danger = Color3.fromRGB(255, 64, 64),
			GhostA = Color3.fromRGB(255, 40, 90), -- chromatic split colours on glitching text
			GhostB = Color3.fromRGB(40, 220, 255),
			Panel = Color3.fromRGB(5, 6, 10),
		},
	},
}
]=====])
end
do local f = folder("ServerScriptService", "Server")
add(f, "ModuleScript", "Collision", [=====[
-- Players fall through the invisible "bridges" laid over pits, while the Stalker (Default group)
-- walks across them. That keeps pits deadly to players but lets Stalker pathfinding cross them.
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local Collision = {}

local function setGroup(model, group)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
end

function Collision.Init()
	for _, name in { "Players", "Bridges" } do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end
	PhysicsService:CollisionGroupSetCollidable("Players", "Bridges", false)

	local function hook(player)
		player.CharacterAdded:Connect(function(char)
			setGroup(char, "Players")
			char.DescendantAdded:Connect(function(d)
				if d:IsA("BasePart") then
					d.CollisionGroup = "Players"
				end
			end)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
end

return Collision
]=====])
add(f, "ModuleScript", "LightService", [=====[
-- Server-authoritative light zones. A player is "safe" only while inside the boundary of a zone
-- whose state is not "Off"; clients only render this state, they never decide it.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local LightService = {}

local zones = {}
local exposure = {} -- [Player] = seconds spent outside any lit zone (0 while safe)
local active = false
local blackout = false

local function duration(state)
	local base = Config.Light[state]
	if blackout and (state == "Stable" or state == "Flicker") then
		return base * Config.Light.BlackoutScale
	end
	return base
end

local function setState(zone, state, seconds)
	zone.State = state
	zone.EndsAt = os.clock() + seconds
	zone.Boundary:SetAttribute("State", state)
	zone.Boundary:SetAttribute("StateEnd", workspace:GetServerTimeNow() + seconds)

	local lit = state ~= "Off"
	zone.Light.Enabled = lit
	zone.Bulb.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
	if zone.Hum then
		zone.Hum.Playing = lit
	end
end

local function resetZone(zone)
	zone.Armed = false
	setState(zone, "Stable", 1e9)
end

local function arm(zone)
	if zone.Armed or zone.Permanent then
		return
	end
	zone.Armed = true
	setState(zone, "Stable", duration("Stable"))
end

local function advance(zone)
	if zone.State == "Stable" then
		setState(zone, "Flickering", duration("Flicker"))
	elseif zone.State == "Flickering" then
		setState(zone, "Critical", duration("Critical"))
	elseif zone.State == "Critical" then
		setState(zone, "Off", Config.Light.RelightDelay)
	else
		resetZone(zone) -- relit, but stays steady until someone enters it again
	end
end

local function zoneAt(position)
	for _, zone in zones do
		if zone.State ~= "Off" then
			local rel = zone.Boundary.CFrame:PointToObjectSpace(position)
			local half = zone.Boundary.Size / 2
			if math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z then
				return zone
			end
		end
	end
	return nil
end

function LightService.Init(folder)
	for _, model in folder:GetChildren() do
		local boundary = model:FindFirstChild("Boundary")
		local bulb = model:FindFirstChild("Bulb")
		if boundary and bulb then
			local zone = {
				Model = model,
				Boundary = boundary,
				Bulb = bulb,
				Light = bulb:FindFirstChildOfClass("PointLight"),
				Hum = bulb:FindFirstChild("Hum"),
				Label = model:GetAttribute("Label") or model.Name,
				Order = model:GetAttribute("Order") or 0,
				Permanent = model:GetAttribute("Permanent") == true,
				State = "Stable",
				EndsAt = 1e9,
				Armed = false,
			}
			boundary:SetAttribute("Order", zone.Order)
			boundary:SetAttribute("Label", zone.Label)
			table.insert(zones, zone)
			resetZone(zone)
		end
	end
	table.sort(zones, function(a, b)
		return a.Order < b.Order
	end)

	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		if active then
			for _, zone in zones do
				if (zone.Armed or zone.State == "Off") and now >= zone.EndsAt then
					advance(zone)
				end
			end
		end

		for _, player in Players:GetPlayers() do
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if hum and root and hum.Health > 0 then
				local zone = zoneAt(root.Position)
				if zone then
					exposure[player] = 0
					if active then
						arm(zone)
					end
					player:SetAttribute("LightState", string.upper(zone.State))
					player:SetAttribute("ZoneLabel", zone.Label)
					player:SetAttribute("ZoneOrder", zone.Order)
				else
					exposure[player] = (exposure[player] or 0) + dt
					player:SetAttribute("LightState", "EXPOSED")
				end
			else
				exposure[player] = nil
			end
		end
	end)
end

function LightService.SetActive(value)
	active = value
end

function LightService.SetBlackout(value)
	blackout = value
end

function LightService.Reset()
	active = false
	blackout = false
	for _, zone in zones do
		resetZone(zone)
	end
	for _, player in Players:GetPlayers() do
		player:SetAttribute("ZoneOrder", 0)
	end
end

function LightService.IsExposed(player)
	local e = exposure[player]
	return e ~= nil and e > 0
end

-- The monster-side check: a newly exposed player gets Config.GraceSeconds before they can be killed.
function LightService.CanKill(player)
	local e = exposure[player]
	return e ~= nil and e >= Config.GraceSeconds
end

function LightService.IsSafe(position)
	return zoneAt(position) ~= nil
end

Players.PlayerRemoving:Connect(function(player)
	exposure[player] = nil
end)

return LightService
]=====])
add(f, "ModuleScript", "LightingSetup", [=====[
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local LightingSetup = {}

function LightingSetup.Apply()
	Lighting.ClockTime = 0
	Lighting.Brightness = 0
	Lighting.Ambient = Color3.fromRGB(6, 6, 9)
	Lighting.OutdoorAmbient = Color3.fromRGB(6, 6, 9)
	Lighting.EnvironmentDiffuseScale = 0
	Lighting.EnvironmentSpecularScale = 0
	Lighting.GlobalShadows = false -- performance: bulbs do not cast shadows either
	Lighting.FogColor = Color3.new(0, 0, 0)
	Lighting.FogStart = 20
	Lighting.FogEnd = 260

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.35
	atmosphere.Offset = 0
	atmosphere.Color = Color3.fromRGB(10, 12, 16)
	atmosphere.Decay = Color3.fromRGB(0, 0, 0)
	atmosphere.Glare = 0
	atmosphere.Haze = 2
	atmosphere.Parent = Lighting

	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.5
	bloom.Size = 24
	bloom.Threshold = 1.2
	bloom.Parent = Lighting

	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
	cc.Contrast = 0.1
	cc.Saturation = -0.25
	cc.TintColor = Color3.new(1, 1, 1):Lerp(Config.UI.Theme.Accent, 0.12) -- cold cast to match the UI
	cc.Parent = Lighting
end

return LightingSetup
]=====])
add(f, "Script", "Main", [=====[
local Collision = require(script.Parent.Collision)
local LightingSetup = require(script.Parent.LightingSetup)
local MapBuilder = require(script.Parent.MapBuilder)
local LightService = require(script.Parent.LightService)
local MovementService = require(script.Parent.MovementService)
local Progression = require(script.Parent.Progression)
local RoundService = require(script.Parent.RoundService)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

LightingSetup.Apply()
Collision.Init()
MapBuilder.Build(Config)
LightService.Init(workspace:WaitForChild("LightZones"))
MovementService.Init()
Progression.Init()
RoundService.Init()
]=====])
add(f, "ModuleScript", "MapBuilder", [=====[
-- Builds THE BLACKOUT FACILITY graybox if the place has no Workspace.LightZones folder.
-- Replace/extend it by hand in Studio later: LightService, Stalker and RoundService only rely on
-- the named objects listed in README.md ("Map contract").
local MapBuilder = {}

local CONCRETE = Color3.fromRGB(38, 39, 44)
local DARK = Color3.fromRGB(22, 22, 26)

local HALF_W = 16 -- floor is 32 wide (z)
local ZONE_LEN = 30

-- Zone centres along +X. Corridor i connects zone i to zone i+1; numbers are pit widths (studs).
-- A sprinting jump clears ~11 studs, a walking jump ~7, so wide pits demand a sprint.
local ZONES = {
	{ label = "ZONE 01", name = "Lobby", x = 0 },
	{ label = "ZONE 02", name = "Lobby Hall", x = 80 },
	{ label = "ZONE 03", name = "Maintenance A", x = 160 },
	{ label = "ZONE 04", name = "Maintenance B", x = 250 },
	{ label = "ZONE 05", name = "Tunnel A", x = 340 },
	{ label = "ZONE 06", name = "Tunnel B", x = 440 },
	{ label = "ZONE 07", name = "Main Generator", x = 540, generator = true },
	{ label = "EXIT", name = "Emergency Exit", x = 620, permanent = true },
}
local CORRIDOR_PITS = { {}, { 6 }, { 7 }, { 7, 8 }, { 8, 8 }, { 8 }, { 8, 9, 8 } }

local function block(parent, name, size, cf, color, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.Color = color or CONCRETE
	p.Material = Enum.Material.Concrete
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function invisibleMarker(parent, name, position)
	return block(parent, name, Vector3.new(2, 2, 2), CFrame.new(position), nil, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
end

local function buildZone(zonesFolder, facility, def, order, config)
	local model = Instance.new("Model")
	model.Name = string.format("Zone%02d", order)
	model:SetAttribute("Label", def.label)
	model:SetAttribute("Order", order)
	model:SetAttribute("Permanent", def.permanent == true)

	-- Trigger volume: this box IS the safe area (checked on the server, never on the client).
	block(model, "Boundary", Vector3.new(ZONE_LEN - 2, 14, 30), CFrame.new(def.x, 7, 0), nil, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})

	local bulb = block(model, "Bulb", Vector3.new(2, 0.6, 2), CFrame.new(def.x, 16, 0), Color3.fromRGB(255, 214, 150), {
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	local light = Instance.new("PointLight")
	light.Range = 45
	light.Brightness = 2.5
	light.Color = Color3.fromRGB(255, 214, 150)
	light.Shadows = false
	light.Parent = bulb

	local hum = Instance.new("Sound")
	hum.Name = "Hum"
	hum.SoundId = config.Sounds.LightHum
	hum.Looped = true
	hum.Volume = 0.4
	hum.RollOffMaxDistance = 60
	hum.Parent = bulb

	-- light fixture so the bulb is not floating
	block(model, "Fixture", Vector3.new(0.4, 2, 0.4), CFrame.new(def.x, 17.3, 0), DARK, { CanCollide = false })

	model.Parent = zonesFolder
end

local function buildCorridor(facility, patrol, xa, xb, pits, rng, index)
	local total = 0
	for _, w in pits do
		total += w
	end
	local seg = (xb - xa - total) / (#pits + 1)
	local cursor = xa

	for i = 0, #pits do
		block(facility, "Floor", Vector3.new(seg, 8, 32), CFrame.new(cursor + seg / 2, -4, 0))

		-- machinery: leave 8 studs of run-up on both ends of each segment
		if seg > 18 then
			for _ = 1, rng:NextInteger(1, 2) do
				local s = rng:NextNumber(3, 5)
				local cx = cursor + rng:NextNumber(8, seg - 8)
				local cz = rng:NextNumber(-12, 12)
				block(facility, "Machinery", Vector3.new(s, s, s), CFrame.new(cx, s / 2, cz), DARK)
			end
		end

		invisibleMarker(patrol, "Patrol", Vector3.new(cursor + seg / 2, 3, rng:NextNumber(-8, 8)))
		cursor += seg

		local w = pits[i + 1]
		if w then
			-- Shallow pit: a failed jump is dangerous (dark + exposed) but climbable (floor at y=-6).
			block(facility, "Pit", Vector3.new(w, 2, 32), CFrame.new(cursor + w / 2, -7, 0), DARK)
			-- Invisible bridge: players fall through (collision group), the Stalker can path over it.
			block(facility, "StalkerBridge", Vector3.new(w, 8, 32), CFrame.new(cursor + w / 2, -4, 0), nil, {
				Transparency = 1,
				CanQuery = false,
				CollisionGroup = "Bridges",
			})
			cursor += w
		end
	end
end

function MapBuilder.Build(config)
	if workspace:FindFirstChild("LightZones") then
		return
	end

	local facility = Instance.new("Folder")
	facility.Name = "Facility"
	local zonesFolder = Instance.new("Folder")
	zonesFolder.Name = "LightZones"
	local patrol = Instance.new("Folder")
	patrol.Name = "StalkerPatrol"
	local spawns = Instance.new("Folder")
	spawns.Name = "StalkerSpawns"
	local switches = Instance.new("Folder")
	switches.Name = "Switches"
	switches.Parent = facility

	local rng = Random.new(1337)
	local firstX = ZONES[1].x - ZONE_LEN / 2
	local lastX = ZONES[#ZONES].x + ZONE_LEN / 2

	-- zone floors
	for i, def in ZONES do
		block(facility, "ZoneFloor", Vector3.new(ZONE_LEN, 8, 32), CFrame.new(def.x, -4, 0))
		buildZone(zonesFolder, facility, def, i, config)
	end

	-- corridors
	for i = 1, #ZONES - 1 do
		local xa = ZONES[i].x + ZONE_LEN / 2
		local xb = ZONES[i + 1].x - ZONE_LEN / 2
		buildCorridor(facility, patrol, xa, xb, CORRIDOR_PITS[i], rng, i)
	end

	-- shell: walls, ceiling, end caps
	local length = lastX - firstX
	local midX = (firstX + lastX) / 2
	for _, z in { -HALF_W - 1, HALF_W + 1 } do
		block(facility, "Wall", Vector3.new(length, 20, 2), CFrame.new(midX, 9, z), DARK)
	end
	block(facility, "Ceiling", Vector3.new(length, 2, 36), CFrame.new(midX, 20, 0), DARK)
	block(facility, "EndWall", Vector3.new(2, 20, 36), CFrame.new(firstX - 1, 9, 0), DARK)
	block(facility, "EndWallExit", Vector3.new(2, 20, 36), CFrame.new(lastX + 1, 9, 0), DARK)

	-- spawn (lobby)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = CFrame.new(-4, 0.5, 0)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = facility

	-- generator switches (inside the Main Generator zone)
	local gen = ZONES[7]
	for i, z in { -10, 0, 10 } do
		local sw = block(switches, "Switch" .. i, Vector3.new(3, 5, 2), CFrame.new(gen.x + 8, 2.5, z), Color3.fromRGB(110, 30, 30))
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Activate"
		prompt.ObjectText = "Generator Switch"
		prompt.HoldDuration = config.Round.SwitchHoldSeconds
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false
		prompt.Parent = sw
	end

	-- gate that seals the final corridor until the generator is running
	block(facility, "ExitGate", Vector3.new(2, 20, 32), CFrame.new(gen.x + ZONE_LEN / 2 + 1, 9, 0), Color3.fromRGB(80, 20, 20))

	-- exit trigger at the far end of the exit zone
	block(facility, "ExitTrigger", Vector3.new(2, 12, 30), CFrame.new(lastX - 2, 6, 0), nil, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	})

	-- stalker spawns: first hunts the Tunnels, second arrives from behind when the blackout hits
	invisibleMarker(spawns, "Spawn1", Vector3.new((ZONES[5].x + ZONES[6].x) / 2, 5, 0))
	invisibleMarker(spawns, "Spawn2", Vector3.new((ZONES[4].x + ZONES[5].x) / 2, 5, 0))

	facility.Parent = workspace
	zonesFolder.Parent = workspace
	patrol.Parent = workspace
	spawns.Parent = workspace
end

return MapBuilder
]=====])
add(f, "ModuleScript", "MovementService", [=====[
-- Server-authoritative stamina and sprint speed. The client only reports whether Shift is held.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)

local M = Config.Movement
local MovementService = {}

local states = {} -- [Player] = { Want, Stamina, Exhausted, Sent }

local function setupCharacter(player, char)
	local hum = char:WaitForChild("Humanoid")
	hum.UseJumpPower = false
	hum.JumpHeight = M.JumpHeight
	hum.WalkSpeed = M.WalkSpeed
	local s = states[player]
	if s then
		s.Stamina = M.StaminaSeconds
		s.Exhausted = false
	end
end

local function addPlayer(player)
	states[player] = { Want = false, Stamina = M.StaminaSeconds, Exhausted = false, Sent = -1 }
	player.CharacterAdded:Connect(function(char)
		setupCharacter(player, char)
	end)
	if player.Character then
		task.spawn(setupCharacter, player, player.Character)
	end
end

function MovementService.Init()
	workspace.Gravity = M.Gravity

	Remotes.Sprint.OnServerEvent:Connect(function(player, held)
		local s = states[player]
		if s and typeof(held) == "boolean" then
			s.Want = held
		end
	end)

	Players.PlayerAdded:Connect(addPlayer)
	for _, p in Players:GetPlayers() do
		addPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		states[p] = nil
	end)

	RunService.Heartbeat:Connect(function(dt)
		for player, s in states do
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if hum and root and hum.Health > 0 then
				local moving = hum.MoveDirection.Magnitude > 0.1
				local sprinting = s.Want and moving and not s.Exhausted and s.Stamina > 0

				if sprinting then
					s.Stamina = math.max(0, s.Stamina - dt)
					if s.Stamina <= 0 then
						s.Exhausted = true
					end
				else
					s.Stamina = math.min(M.StaminaSeconds, s.Stamina + (M.StaminaSeconds / M.RecoverSeconds) * dt)
					if s.Exhausted and s.Stamina >= M.ExhaustRecoverSeconds then
						s.Exhausted = false
					end
				end

				local speed = if sprinting then M.SprintSpeed else M.WalkSpeed
				if hum.WalkSpeed ~= speed then
					hum.WalkSpeed = speed
				end

				-- throttle replication to ~10 Hz worth of change
				local pct = math.floor(s.Stamina / M.StaminaSeconds * 100) / 100
				if pct ~= s.Sent then
					s.Sent = pct
					player:SetAttribute("Stamina", pct)
				end
				player:SetAttribute("Exhausted", s.Exhausted)

				-- fall detection: pits are shallow, this only catches leaving the map
				if root.Position.Y < M.FallKillY then
					hum.Health = 0
				end
			end
		end
	end)
end

return MovementService
]=====])
add(f, "ModuleScript", "Progression", [=====[
-- Basic XP + coin progression. Cosmetics are the only thing coins should ever buy.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local Progression = {}

local store
pcall(function()
	store = DataStoreService:GetDataStore("LightsOutV1")
end)

local loaded = {} -- [Player] = true once data has loaded (never overwrite saves with defaults)

local function load(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local xp = Instance.new("IntValue")
	xp.Name = "XP"
	xp.Parent = stats
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = stats
	local escapes = Instance.new("IntValue")
	escapes.Name = "Escapes"
	escapes.Parent = stats
	stats.Parent = player

	if store then
		local ok, data = pcall(function()
			return store:GetAsync(tostring(player.UserId))
		end)
		if ok then
			if type(data) == "table" then
				xp.Value = data.XP or 0
				coins.Value = data.Coins or 0
				escapes.Value = data.Escapes or 0
			end
			loaded[player] = true
		end
	end
end

local function save(player)
	local stats = player:FindFirstChild("leaderstats")
	if not (store and stats and loaded[player]) then
		return
	end
	pcall(function()
		store:SetAsync(tostring(player.UserId), { XP = stats.XP.Value, Coins = stats.Coins.Value, Escapes = stats.Escapes.Value })
	end)
end

function Progression.Award(player, reward)
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		stats.XP.Value += reward.XP
		stats.Coins.Value += reward.Coins
	end
end

function Progression.AddEscape(player)
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		stats.Escapes.Value += 1
	end
end

function Progression.Init()
	Players.PlayerAdded:Connect(load)
	for _, p in Players:GetPlayers() do
		task.spawn(load, p)
	end
	Players.PlayerRemoving:Connect(function(p)
		save(p)
		loaded[p] = nil
	end)
	game:BindToClose(function()
		for _, p in Players:GetPlayers() do
			save(p)
		end
	end)
end

return Progression
]=====])
add(f, "ModuleScript", "Remotes", [=====[
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = Instance.new("Folder")
folder.Name = "Remotes"

local sprint = Instance.new("RemoteEvent")
sprint.Name = "Sprint"
sprint.Parent = folder

-- fired once when the player presses PLAY on the title screen
local ready = Instance.new("RemoteEvent")
ready.Name = "Ready"
ready.Parent = folder

folder.Parent = ReplicatedStorage

return {
	Sprint = sprint,
	Ready = ready,
}
]=====])
add(f, "ModuleScript", "RoundService", [=====[
-- Round flow: Intermission -> Countdown -> Playing -> End. Dead players spectate until the round ends.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local LightService = require(script.Parent.LightService)
local Stalker = require(script.Parent.Stalker)
local Progression = require(script.Parent.Progression)
local Remotes = require(script.Parent.Remotes)

local R = Config.Round
local RoundService = {}

local state = "Intermission" -- Intermission | Countdown | Playing | Ending
local participants = {} -- [Player] = true for everyone who started this round
local alive = {} -- [Player] = true while alive (escaped players stay alive)
local escaped = {} -- [Player] = true
local stalkers = {}
local switchesOn = 0
local firstEscapeAt = nil
local connections = {}

local minPlayers = if RunService:IsStudio() then 1 else R.MinPlayers

-- only players who pressed PLAY on the title screen take part in rounds
local function readyPlayers()
	local list = {}
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("Ready") == true then
			table.insert(list, p)
		end
	end
	return list
end

local function setStatus(text)
	ReplicatedStorage:SetAttribute("Status", text)
end

local function count(set)
	local n = 0
	for _ in set do
		n += 1
	end
	return n
end

local function publishCounts()
	local pending = 0
	for p in alive do
		if not escaped[p] then
			pending += 1
		end
	end
	ReplicatedStorage:SetAttribute("Alive", count(alive))
	ReplicatedStorage:SetAttribute("Total", count(participants))
	ReplicatedStorage:SetAttribute("Escaped", count(escaped))
	ReplicatedStorage:SetAttribute("Pending", pending)
end

local function setState(newState)
	state = newState
	ReplicatedStorage:SetAttribute("RoundState", newState)
end

local function loadInLobby(player)
	if player.Parent then
		player:SetAttribute("Spectating", false)
		player:LoadCharacter()
	end
end

local function onDied(player)
	if state == "Playing" and alive[player] and not escaped[player] then
		alive[player] = nil
		player:SetAttribute("Spectating", true)
		publishCounts()
	elseif state ~= "Playing" and state ~= "Ending" then
		task.delay(3, function()
			if state ~= "Playing" and state ~= "Ending" then
				loadInLobby(player)
			end
		end)
	end
end

local function hookPlayer(player)
	player:SetAttribute("Spectating", state == "Playing" or state == "Ending")
	player.CharacterAdded:Connect(function(char)
		local hum = char:WaitForChild("Humanoid")
		hum.Died:Connect(function()
			onDied(player)
		end)
	end)
	if state == "Intermission" or state == "Countdown" then
		task.spawn(loadInLobby, player)
	end
end

local function closeConnections()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
end

local function setGate(open)
	local gate = workspace.Facility:FindFirstChild("ExitGate")
	if gate then
		gate.CanCollide = not open
		gate.Transparency = if open then 0.85 else 0
	end
end

local function setSwitches(enabled)
	for _, sw in workspace.Facility.Switches:GetChildren() do
		local prompt = sw:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = enabled
		end
		sw.Color = Color3.fromRGB(110, 30, 30)
		sw:SetAttribute("On", false)
	end
	switchesOn = 0
end

local function spawnStalker(name)
	local marker = workspace.StalkerSpawns:FindFirstChild(name)
	if marker then
		table.insert(stalkers, Stalker.new(marker.Position))
	end
end

local function triggerBlackout()
	LightService.SetBlackout(true)
	Stalker.SpeedScale = Config.Stalker.BlackoutSpeedScale
	setGate(true)
	setStatus("BLACKOUT - RUN FOR THE EXIT")
	spawnStalker("Spawn2")
end

local function connectObjective()
	for _, sw in workspace.Facility.Switches:GetChildren() do
		local prompt = sw:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			table.insert(connections, prompt.Triggered:Connect(function(player)
				if state ~= "Playing" or not alive[player] or sw:GetAttribute("On") then
					return
				end
				sw:SetAttribute("On", true)
				sw.Color = Color3.fromRGB(60, 220, 90)
				prompt.Enabled = false
				switchesOn += 1
				ReplicatedStorage:SetAttribute("Switches", switchesOn)
				if switchesOn >= R.SwitchesRequired then
					triggerBlackout()
				else
					setStatus(string.format("GENERATOR: %d / %d SWITCHES", switchesOn, R.SwitchesRequired))
				end
			end))
		end
	end

	local exit = workspace.Facility:FindFirstChild("ExitTrigger")
	if exit then
		table.insert(connections, exit.Touched:Connect(function(hit)
			local player = Players:GetPlayerFromCharacter(hit.Parent)
			if player and state == "Playing" and alive[player] and not escaped[player] and switchesOn >= R.SwitchesRequired then
				escaped[player] = true
				Progression.AddEscape(player)
				player:SetAttribute("Escaped", true)
				firstEscapeAt = firstEscapeAt or os.clock()
				publishCounts()
			end
		end))
	end
end

local function cleanup()
	closeConnections()
	for _, s in stalkers do
		s:Destroy()
	end
	table.clear(stalkers)
	Stalker.SpeedScale = 1
	LightService.Reset()
	setSwitches(false)
	setGate(false)
	ReplicatedStorage:SetAttribute("Switches", 0)
end

local function playRound()
	-- gather
	table.clear(participants)
	table.clear(alive)
	table.clear(escaped)
	firstEscapeAt = nil
	for _, p in readyPlayers() do
		if count(participants) < R.MaxPlayers then
			participants[p] = true
		end
	end
	for _, p in Players:GetPlayers() do
		p:SetAttribute("Escaped", false)
	end

	cleanup()
	setState("Countdown")
	for p in participants do
		alive[p] = true
		p:SetAttribute("Spectating", false)
		task.spawn(function()
			p:LoadCharacter()
		end)
	end
	for _, p in Players:GetPlayers() do
		if not participants[p] then
			p:SetAttribute("Spectating", true)
			-- remove lobby bodies so non-players cannot arm lights or draw the Stalker
			if p.Character then
				p.Character:Destroy()
			end
		end
	end
	publishCounts()

	for i = R.CountdownSeconds, 1, -1 do
		setStatus("GET READY... " .. i)
		task.wait(1)
	end

	-- go
	setState("Playing")
	setStatus("FIND THE NEXT LIGHT")
	LightService.SetActive(true)
	setSwitches(true)
	connectObjective()
	spawnStalker("Spawn1")

	local startedAt = os.clock()
	local victory = false
	while true do
		task.wait(0.5)
		publishCounts()

		local pending = ReplicatedStorage:GetAttribute("Pending")
		local escapedCount = count(escaped)

		if escapedCount > 0 and (pending == 0 or os.clock() - firstEscapeAt >= R.ExitGraceSeconds) then
			victory = true
			break
		end
		if count(alive) == 0 then
			break
		end
		if os.clock() - startedAt > R.RoundTimeLimit then
			break
		end
		if count(participants) == 0 then
			break
		end
		if escapedCount > 0 and pending > 0 then
			setStatus(string.format("ESCAPED - %ds FOR THE OTHERS", math.max(0, math.ceil(R.ExitGraceSeconds - (os.clock() - firstEscapeAt)))))
		end
	end

	-- end
	setState("Ending")
	setStatus(if victory then "YOU ESCAPED THE FACILITY" else "THE LIGHTS WENT OUT FOR GOOD")
	for p in participants do
		if p.Parent then
			if escaped[p] then
				Progression.Award(p, Config.Rewards.Escaped)
			elseif alive[p] then
				Progression.Award(p, Config.Rewards.SurvivedNotEscaped)
			else
				Progression.Award(p, Config.Rewards.Participated)
			end
			if victory then
				Progression.Award(p, Config.Rewards.TeamVictoryBonus)
			end
		end
	end
	task.wait(R.EndScreenSeconds)
	cleanup()
end

function RoundService.Init()
	Players.CharacterAutoLoads = false

	Remotes.Ready.OnServerEvent:Connect(function(player)
		player:SetAttribute("Ready", true)
	end)

	Players.PlayerAdded:Connect(hookPlayer)
	for _, p in Players:GetPlayers() do
		hookPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		participants[p] = nil
		alive[p] = nil
		escaped[p] = nil
		if state == "Playing" then
			publishCounts()
		end
	end)

	task.spawn(function()
		while true do
			setState("Intermission")
			ReplicatedStorage:SetAttribute("Alive", 0)
			ReplicatedStorage:SetAttribute("Total", 0)
			for _, p in Players:GetPlayers() do
				p:SetAttribute("Spectating", false)
				p:SetAttribute("Escaped", false)
				task.spawn(loadInLobby, p)
			end

			while #readyPlayers() < minPlayers do
				setStatus(string.format("WAITING FOR PLAYERS (%d/%d)", #readyPlayers(), minPlayers))
				task.wait(1)
			end
			for i = R.IntermissionSeconds, 1, -1 do
				setStatus("ROUND STARTS IN " .. i)
				task.wait(1)
				if #readyPlayers() < minPlayers then
					break
				end
			end
			if #readyPlayers() >= minPlayers then
				playRound()
			end
		end
	end)
end

return RoundService
]=====])
add(f, "ModuleScript", "Stalker", [=====[
-- THE STALKER: tall thin hunter. Patrols the dark, chases exposed players, ignores the safe.
-- All targeting and kill validation is server-side.
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local LightService = require(script.Parent.LightService)

local S = Config.Stalker

local Stalker = {}
Stalker.__index = Stalker
Stalker.SpeedScale = 1

local function part(model, root, name, size, offset, color, neon)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.Massless = true
	p.CFrame = root.CFrame * CFrame.new(offset)
	p.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = p
	weld.Parent = p
	return p
end

local function build(position)
	local model = Instance.new("Model")
	model.Name = "Stalker"

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.CFrame = CFrame.new(position)
	root.Parent = model
	model.PrimaryPart = root

	local black = Color3.fromRGB(8, 8, 10)
	part(model, root, "Torso", Vector3.new(1.4, 4, 0.9), Vector3.new(0, 3, 0), black)
	part(model, root, "Head", Vector3.new(1.1, 1.5, 1.1), Vector3.new(0, 5.8, 0), black)
	part(model, root, "LegL", Vector3.new(0.6, 4, 0.6), Vector3.new(-0.4, -3, 0), black)
	part(model, root, "LegR", Vector3.new(0.6, 4, 0.6), Vector3.new(0.4, -3, 0), black)
	part(model, root, "ArmL", Vector3.new(0.45, 5.5, 0.45), Vector3.new(-1.1, 2.6, 0), black)
	part(model, root, "ArmR", Vector3.new(0.45, 5.5, 0.45), Vector3.new(1.1, 2.6, 0), black)

	-- faint blue eyes: the only thing that shows its position at range
	local blue = Color3.fromRGB(70, 150, 255)
	for _, x in { -0.28, 0.28 } do
		local eye = part(model, root, "Eye", Vector3.new(0.22, 0.12, 0.1), Vector3.new(x, 5.9, -0.58), blue, true)
		local glow = Instance.new("PointLight")
		glow.Color = blue
		glow.Range = 6
		glow.Brightness = 0.6
		glow.Shadows = false
		glow.Parent = eye
	end

	if Config.Sounds.StalkerSteps ~= "" then
		local steps = Instance.new("Sound")
		steps.Name = "Steps"
		steps.SoundId = Config.Sounds.StalkerSteps
		steps.Looped = true
		steps.Volume = 0.9
		steps.RollOffMode = Enum.RollOffMode.InverseTapered
		steps.RollOffMaxDistance = 90
		steps.Parent = root
	end

	local hum = Instance.new("Humanoid")
	hum.HipHeight = 4 -- root centre ends up 5 studs above the floor
	hum.RequiresNeck = false
	hum.BreakJointsOnDeath = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.WalkSpeed = S.PatrolSpeed
	hum.Parent = model

	CollectionService:AddTag(model, "Stalker")
	model.Parent = workspace
	root:SetNetworkOwner(nil) -- server simulates the monster
	return model, root, hum
end

local function alive(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and char:FindFirstChild("HumanoidRootPart") ~= nil
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

function Stalker.new(position)
	local self = setmetatable({}, Stalker)
	self.model, self.root, self.humanoid = build(position)
	self.running = true
	self.target = nil
	self.chaseStart = 0
	self.waypoints = nil
	self.index = 2
	self.lastPath = 0
	self.patrolPoint = nil
	self.idleUntil = 0
	self.home = position
	task.spawn(function()
		self:Run()
	end)
	return self
end

function Stalker:PickTarget()
	local rootPos = self.root.Position

	local current = self.target
	if current and current.Parent and alive(current) and LightService.IsExposed(current) then
		if (current.Character.HumanoidRootPart.Position - rootPos).Magnitude < S.LoseRange then
			return current
		end
	end

	-- choose among exposed players, weighted toward closer ones, not strictly the nearest
	local candidates, total = {}, 0
	for _, player in Players:GetPlayers() do
		if alive(player) and LightService.IsExposed(player) then
			local d = (player.Character.HumanoidRootPart.Position - rootPos).Magnitude
			if d < S.DetectRange then
				local w = 1 / math.max(d, 5)
				table.insert(candidates, { player = player, weight = w })
				total += w
			end
		end
	end
	if total == 0 then
		return nil
	end
	local roll = math.random() * total
	for _, c in candidates do
		roll -= c.weight
		if roll <= 0 then
			return c.player
		end
	end
	return candidates[#candidates].player
end

function Stalker:MoveToward(position)
	local now = os.clock()
	if not self.waypoints or now - self.lastPath > 0.5 then
		self.lastPath = now
		local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 8, AgentCanJump = true })
		local ok = pcall(function()
			path:ComputeAsync(self.root.Position, position)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			self.waypoints = path:GetWaypoints()
			self.index = 2
		else
			self.waypoints = nil
		end
	end

	local wps = self.waypoints
	if wps then
		local wp = wps[self.index]
		if wp and flat(wp.Position - self.root.Position).Magnitude < 3 then
			self.index += 1
			wp = wps[self.index]
		end
		if wp then
			self.humanoid:MoveTo(wp.Position)
			if wp.Action == Enum.PathWaypointAction.Jump then
				self.humanoid.Jump = true
			end
			return
		end
	end
	self.humanoid:MoveTo(position)
end

function Stalker:Run()
	local patrolPoints = {}
	local folder = workspace:FindFirstChild("StalkerPatrol")
	if folder then
		patrolPoints = folder:GetChildren()
	end

	while self.running and self.model.Parent do
		local root = self.root
		local steps = root:FindFirstChild("Steps")

		if root.Position.Y < -30 then
			self.model:PivotTo(CFrame.new(self.home))
			self.waypoints = nil
		end

		local target = self:PickTarget()
		if target then
			if target ~= self.target then
				self.target = target
				self.chaseStart = os.clock()
				self.waypoints = nil
			end
			local t = math.clamp((os.clock() - self.chaseStart) / S.AccelSeconds, 0, 1)
			self.humanoid.WalkSpeed = (S.ChaseSpeedMin + (S.ChaseSpeedMax - S.ChaseSpeedMin) * t) * Stalker.SpeedScale

			local targetRoot = target.Character.HumanoidRootPart
			self:MoveToward(targetRoot.Position)

			local delta = targetRoot.Position - root.Position
			if LightService.CanKill(target) and flat(delta).Magnitude < S.KillRange and math.abs(delta.Y) < 7 then
				target.Character.Humanoid.Health = 0
				self.target = nil
			end
		else
			if self.target then
				self.target = nil
				self.waypoints = nil
			end
			self.humanoid.WalkSpeed = S.PatrolSpeed * Stalker.SpeedScale

			if os.clock() >= self.idleUntil then
				if not self.patrolPoint and #patrolPoints > 0 then
					self.patrolPoint = patrolPoints[math.random(#patrolPoints)]
					self.waypoints = nil
				end
				if self.patrolPoint then
					local dest = self.patrolPoint.Position
					if flat(dest - root.Position).Magnitude < 4 then
						self.patrolPoint = nil
						self.idleUntil = os.clock() + math.random(1, 3)
						self.humanoid:MoveTo(root.Position)
					else
						self:MoveToward(dest)
					end
				end
			end
		end

		if steps then
			steps.Playing = self.humanoid.MoveDirection.Magnitude > 0.1
			steps.PlaybackSpeed = 0.8 + self.humanoid.WalkSpeed / 40
		end

		task.wait(0.1)
	end
end

function Stalker:Destroy()
	self.running = false
	self.model:Destroy()
end

return Stalker
]=====])
end
do local f = folder("StarterPlayerScripts", "Client")
add(f, "LocalScript", "Audio", [=====[
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
]=====])
add(f, "LocalScript", "Hud", [=====[
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
]=====])
add(f, "LocalScript", "Lights", [=====[
-- Renders light-zone state set by the server: steady, flickering (faster over time), critical.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local folder = workspace:WaitForChild("LightZones")
local zones = {}

local function register(model)
	local boundary = model:WaitForChild("Boundary")
	local bulb = model:WaitForChild("Bulb")
	local light = bulb:WaitForChild("PointLight")
	table.insert(zones, {
		boundary = boundary,
		light = light,
		hum = bulb:FindFirstChild("Hum"),
		base = light.Brightness,
		seed = math.random() * 100,
	})
end

for _, model in folder:GetChildren() do
	task.spawn(register, model)
end
folder.ChildAdded:Connect(register)

RunService.RenderStepped:Connect(function()
	local now = workspace:GetServerTimeNow()
	local clock = os.clock()
	for _, z in zones do
		local state = z.boundary:GetAttribute("State")
		local brightness = z.base
		local pitch = 1

		if state == "Flickering" then
			local remaining = (z.boundary:GetAttribute("StateEnd") or now) - now
			local progress = 1 - math.clamp(remaining / Config.Light.Flicker, 0, 1) -- 0 -> 1
			local rate = 2 + progress * 12
			local on = math.noise(clock * rate, z.seed) > (-0.35 + progress * 0.45)
			brightness = if on then z.base else z.base * 0.1
			pitch = if on then 1 else 0.7
		elseif state == "Critical" then
			local on = math.noise(clock * 28, z.seed) > 0.2
			brightness = if on then z.base * 0.8 else 0
			pitch = if on then 0.9 else 0.5
		end

		z.light.Brightness = brightness
		if z.hum then
			z.hum.PlaybackSpeed = pitch
		end
	end
end)
]=====])
add(f, "LocalScript", "Menu", [=====[
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
]=====])
add(f, "LocalScript", "Movement", [=====[
-- Sprint input (Shift / gamepad L3 / mobile buttons), head-bob, and a proximity shake near the Stalker.
-- Mobile gets two styled buttons: SPRINT (hold) and JUMP SPRINT (press = sprint + jump, hold = keep
-- sprinting and jump again every time you land).
-- The camera mode is set by the menu (LockFirstPerson once the player presses PLAY).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local UIStyle = require(script.Parent:WaitForChild("UIStyle"))
local T = UIStyle.Theme

-- Several inputs can hold sprint at once; the server only hears when the combined state changes.
local sources = {}
local sentSprint = false
local function setSprint(source, held)
	sources[source] = if held then true else nil
	local want = next(sources) ~= nil
	if want ~= sentSprint then
		sentSprint = want
		Remotes.Sprint:FireServer(want)
	end
end

ContextActionService:BindAction("Sprint", function(_, inputState)
	setSprint("key", inputState == Enum.UserInputState.Begin)
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)

local function humanoid()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

---------------------------------------------------------------------------------------------------
-- Mobile buttons
---------------------------------------------------------------------------------------------------
local mobileGui
if UserInputService.TouchEnabled then
	mobileGui = Instance.new("ScreenGui")
	mobileGui.Name = "MobileControls"
	mobileGui.ResetOnSpawn = false
	mobileGui.DisplayOrder = 6
	mobileGui.Parent = player:WaitForChild("PlayerGui")

	-- sits to the left of Roblox's own jump button so thumbs don't collide
	local jumpSprint = UIStyle.Button(mobileGui, UIStyle.Spaced("JUMP") .. "\n" .. UIStyle.Spaced("SPRINT"), {
		Name = "JumpSprint",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -190, 1, -132),
		Size = UDim2.fromOffset(132, 74),
		TextSize = 15,
	})
	local sprint = UIStyle.Button(mobileGui, UIStyle.Spaced("SPRINT"), {
		Name = "Sprint",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -190, 1, -48),
		Size = UDim2.fromOffset(132, 54),
		TextSize = 13,
	})

	local function pressedLook(button, down)
		button.Border.Thickness = if down then 3 else 1.5
		button.BackgroundColor3 = if down then T.Accent else T.Panel
		button.BackgroundTransparency = if down then 0.65 else 0.35
	end

	local function holdButton(button, source, onPress)
		button.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end
			setSprint(source, true)
			pressedLook(button, true)
			if onPress then
				onPress()
			end
			local conn
			conn = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
					setSprint(source, false)
					pressedLook(button, false)
					conn:Disconnect()
				end
			end)
		end)
	end

	holdButton(sprint, "sprintButton")
	holdButton(jumpSprint, "jumpSprint", function()
		local hum = humanoid()
		if hum then
			hum.Jump = true
		end
		UIStyle.Burst(0.08, 0.3)
	end)
end

---------------------------------------------------------------------------------------------------
-- Camera feel
---------------------------------------------------------------------------------------------------
local SHAKE_RANGE = 55
local bobTime = 0

RunService.RenderStepped:Connect(function(dt)
	local hum = humanoid()
	local root = hum and hum.Parent:FindFirstChild("HumanoidRootPart")
	local alive = hum ~= nil and root ~= nil and hum.Health > 0

	if mobileGui then
		mobileGui.Enabled = alive and player:GetAttribute("InMenu") ~= true and player:GetAttribute("Spectating") ~= true
	end
	if not alive then
		return
	end

	-- holding JUMP SPRINT keeps jumping on every landing
	if sources.jumpSprint then
		hum.Jump = true
	end

	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local grounded = hum.FloorMaterial ~= Enum.Material.Air

	bobTime += dt * speed * 0.55
	local amp = if grounded then math.clamp(speed / Config.Movement.SprintSpeed, 0, 1) else 0
	local bob = Vector3.new(math.sin(bobTime) * 0.06 * amp, math.abs(math.sin(bobTime)) * 0.12 * amp, 0)

	-- subtle shake that ramps up as a Stalker closes in
	local nearest = math.huge
	for _, stalker in CollectionService:GetTagged("Stalker") do
		if stalker:IsA("Model") then
			nearest = math.min(nearest, (stalker:GetPivot().Position - root.Position).Magnitude)
		end
	end
	local shake = math.clamp(1 - (nearest - 10) / (SHAKE_RANGE - 10), 0, 1) * 0.07
	if UIStyle.Reduced then
		shake *= 0.3
	end
	local t = os.clock() * 17
	local jitter = Vector3.new(math.noise(t, 0.3) * shake, math.noise(0.7, t) * shake, 0)

	hum.CameraOffset = hum.CameraOffset:Lerp(bob + jitter, math.min(1, dt * 12))
end)
]=====])
add(f, "LocalScript", "Spectate", [=====[
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
]=====])
add(f, "ModuleScript", "UIStyle", [=====[
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
]=====])
end
print("LIGHTS OUT installed. Press Play.")
