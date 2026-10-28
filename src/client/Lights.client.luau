-- Renders light-zone state set by the server: steady, flickering (faster over time), critical.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local folder = workspace:WaitForChild("LightZones")
local zones = {}

local function register(model)
	local boundary = model:WaitForChild("Boundary")
	local bulb = model:WaitForChild("Bulb")
	local light = bulb:WaitForChild("PointLight")
	table.insert(zones, {
		boundary = boundary,
		light = light,
		hum = bulb:FindFirstChild("Hum"),
		base = light.Brightness,
		seed = math.random() * 100,
	})
end

for _, model in folder:GetChildren() do
	task.spawn(register, model)
end
folder.ChildAdded:Connect(register)

RunService.RenderStepped:Connect(function()
	local now = workspace:GetServerTimeNow()
	local clock = os.clock()
	for _, z in zones do
		local state = z.boundary:GetAttribute("State")
		local brightness = z.base
		local pitch = 1

		if state == "Flickering" then
			local remaining = (z.boundary:GetAttribute("StateEnd") or now) - now
			local progress = 1 - math.clamp(remaining / Config.Light.Flicker, 0, 1) -- 0 -> 1
			local rate = 2 + progress * 12
			local on = math.noise(clock * rate, z.seed) > (-0.35 + progress * 0.45)
			brightness = if on then z.base else z.base * 0.1
			pitch = if on then 1 else 0.7
		elseif state == "Critical" then
			local on = math.noise(clock * 28, z.seed) > 0.2
			brightness = if on then z.base * 0.8 else 0
			pitch = if on then 0.9 else 0.5
		end

		z.light.Brightness = brightness
		if z.hum then
			z.hum.PlaybackSpeed = pitch
		end
	end
end)
