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
