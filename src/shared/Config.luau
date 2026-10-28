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
	},

	UI = {
		ShowNextLightDistance = true, -- turn off for harder modes
	},
}
