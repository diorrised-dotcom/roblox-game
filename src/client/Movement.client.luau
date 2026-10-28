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
