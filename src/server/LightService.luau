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
