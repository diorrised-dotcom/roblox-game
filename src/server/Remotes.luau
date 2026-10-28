local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = Instance.new("Folder")
folder.Name = "Remotes"

local sprint = Instance.new("RemoteEvent")
sprint.Name = "Sprint"
sprint.Parent = folder

folder.Parent = ReplicatedStorage

return {
	Sprint = sprint,
}
