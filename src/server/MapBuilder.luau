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
