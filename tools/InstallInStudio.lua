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
	},

	UI = {
		ShowNextLightDistance = true, -- turn off for harder modes
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
	stats.Parent = player

	if store then
		local ok, data = pcall(function()
			return store:GetAsync(tostring(player.UserId))
		end)
		if ok then
			if type(data) == "table" then
				xp.Value = data.XP or 0
				coins.Value = data.Coins or 0
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
		store:SetAsync(tostring(player.UserId), { XP = stats.XP.Value, Coins = stats.Coins.Value })
	end)
end

function Progression.Award(player, reward)
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		stats.XP.Value += reward.XP
		stats.Coins.Value += reward.Coins
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

folder.Parent = ReplicatedStorage

return {
	Sprint = sprint,
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
	for _, p in Players:GetPlayers() do
		if count(participants) < R.MaxPlayers then
			participants[p] = true
		end
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

			while #Players:GetPlayers() < minPlayers do
				setStatus(string.format("WAITING FOR PLAYERS (%d/%d)", #Players:GetPlayers(), minPlayers))
				task.wait(1)
			end
			for i = R.IntermissionSeconds, 1, -1 do
				setStatus("ROUND STARTS IN " .. i)
				task.wait(1)
				if #Players:GetPlayers() < minPlayers then
					break
				end
			end
			if #Players:GetPlayers() >= minPlayers then
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
add(f, "LocalScript", "Movement", [=====[
-- First-person camera, sprint input, head-bob, and a proximity shake near the Stalker.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

player.CameraMode = Enum.CameraMode.LockFirstPerson

local function onSprint(_, inputState)
	Remotes.Sprint:FireServer(inputState == Enum.UserInputState.Begin)
	return Enum.ContextActionResult.Pass
end
ContextActionService:BindAction("Sprint", onSprint, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
ContextActionService:SetTitle("Sprint", "RUN")

local SHAKE_RANGE = 55
local bobTime = 0

RunService.RenderStepped:Connect(function(dt)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (hum and root) or hum.Health <= 0 then
		return
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
end
print("LIGHTS OUT installed. Press Play.")
