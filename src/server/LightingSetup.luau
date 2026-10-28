local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local LightingSetup = {}

function LightingSetup.Apply()
	Lighting.ClockTime = 0
	Lighting.Brightness = 0
	Lighting.Ambient = Color3.fromRGB(6, 6, 9)
	Lighting.OutdoorAmbient = Color3.fromRGB(6, 6, 9)
	Lighting.EnvironmentDiffuseScale = 0
	Lighting.EnvironmentSpecularScale = 0
	Lighting.GlobalShadows = false -- performance: bulbs do not cast shadows either
	Lighting.FogColor = Color3.new(0, 0, 0)
	Lighting.FogStart = 20
	Lighting.FogEnd = 260

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.35
	atmosphere.Offset = 0
	atmosphere.Color = Color3.fromRGB(10, 12, 16)
	atmosphere.Decay = Color3.fromRGB(0, 0, 0)
	atmosphere.Glare = 0
	atmosphere.Haze = 2
	atmosphere.Parent = Lighting

	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.5
	bloom.Size = 24
	bloom.Threshold = 1.2
	bloom.Parent = Lighting

	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
	cc.Contrast = 0.1
	cc.Saturation = -0.25
	cc.TintColor = Color3.new(1, 1, 1):Lerp(Config.UI.Theme.Accent, 0.12) -- cold cast to match the UI
	cc.Parent = Lighting
end

return LightingSetup
