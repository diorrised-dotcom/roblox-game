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
