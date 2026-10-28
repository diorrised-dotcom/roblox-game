local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = Instance.new("Folder")
folder.Name = "Remotes"

local sprint = Instance.new("RemoteEvent")
sprint.Name = "Sprint"
sprint.Parent = folder

-- fired once when the player presses PLAY on the title screen
local ready = Instance.new("RemoteEvent")
ready.Name = "Ready"
ready.Parent = folder

folder.Parent = ReplicatedStorage

return {
	Sprint = sprint,
	Ready = ready,
}
