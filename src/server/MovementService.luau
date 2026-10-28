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
