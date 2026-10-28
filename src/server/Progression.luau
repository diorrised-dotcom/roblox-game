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
