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
