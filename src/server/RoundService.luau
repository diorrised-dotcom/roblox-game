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
