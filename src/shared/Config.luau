-- Central tuning table. Every value here is a starting target to be playtested in Studio.
return {
	Movement = {
		WalkSpeed = 14,
		SprintSpeed = 22,
		StaminaSeconds = 5, -- continuous sprint time
		RecoverSeconds = 4, -- empty -> full
		ExhaustRecoverSeconds = 1, -- stamina needed again after hitting empty
		JumpHeight = 7.5,
		Gravity = 230, -- default is 196.2; higher = snappier, less floaty
		FallKillY = -60, -- pits are at y = -6, so this only catches true falls
	},

	Light = {
		Stable = 20,
		Flicker = 7,
		Critical = 3,
		RelightDelay = 12, -- seconds a failed light stays dark before it resets (unarmed)
		BlackoutScale = 0.5, -- multiplies Stable + Flicker once the generator is on
	},

	GraceSeconds = 1.5, -- time exposed before a monster is allowed to kill

	Stalker = {
		PatrolSpeed = 8,
		ChaseSpeedMin = 12,
		ChaseSpeedMax = 21,
		AccelSeconds = 2.5,
		DetectRange = 70,
		LoseRange = 110,
		KillRange = 4.5,
		BlackoutSpeedScale = 1.15,
	},

	Round = {
		MaxPlayers = 6,
		MinPlayers = 2,
		IntermissionSeconds = 10,
		CountdownSeconds = 5,
		SwitchesRequired = 3,
		SwitchHoldSeconds = 2,
		ExitGraceSeconds = 10, -- after the first escape, time left for teammates
		RoundTimeLimit = 15 * 60,
		EndScreenSeconds = 8,
	},

	Rewards = {
		Escaped = { XP = 100, Coins = 50 },
		SurvivedNotEscaped = { XP = 40, Coins = 15 },
		Participated = { XP = 20, Coins = 5 },
		TeamVictoryBonus = { XP = 25, Coins = 10 },
	},

	-- Paste Roblox asset ids ("rbxassetid://123") here. Empty = that sound is skipped.
	Sounds = {
		LightHum = "",
		LightOff = "",
		FlickerWarning = "",
		Breathing = "",
		StalkerSteps = "",
		Glitch = "", -- short static burst used by the UI
		MenuAmbience = "",
	},

	UI = {
		ShowNextLightDistance = true, -- turn off for harder modes
		ReducedEffects = false, -- players can also toggle this in SETTINGS (less flashing/static)

		-- One accent colour drives every glow, line and CRT band.
		-- Try Color3.fromRGB(140, 90, 255) for purple, (255, 60, 60) for red, (255, 180, 80) for amber.
		Theme = {
			Accent = Color3.fromRGB(110, 160, 255),
			Text = Color3.fromRGB(226, 230, 240),
			Dim = Color3.fromRGB(105, 110, 128),
			Warning = Color3.fromRGB(255, 190, 80),
			Danger = Color3.fromRGB(255, 64, 64),
			GhostA = Color3.fromRGB(255, 40, 90), -- chromatic split colours on glitching text
			GhostB = Color3.fromRGB(40, 220, 255),
			Panel = Color3.fromRGB(5, 6, 10),
		},
	},
}
