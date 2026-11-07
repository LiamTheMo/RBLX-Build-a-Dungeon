-- Presentation-only sound slots for room combat events.
local sounds = {
	SlimeNest = { "SlimeAttack" },
	GuardRoom = { "GuardAttack" },
	EmeraldGuardroom = { "GuardAttack" },
	DragonLair = { "DragonGrowl" },
	EclipseBastion = { "DragonGrowl" },
	PrismBastion = { "DragonGrowl" },
	PhoenixNest = { "PhoenixCall", "FireBurst" },
	SunfireSanctum = { "PhoenixCall", "FireBurst" },
	PrismSanctum = { "PhoenixCall", "FireBurst" },
}

local RoomSounds = {}

function RoomSounds.Attack(roomId: string?): { string }
	return sounds[roomId or ""] or { "Hit" }
end

function RoomSounds.Trap(roomId: string?): string
	return if roomId == "FlameVent" then "FireBurst" else "SpikeStrike"
end

return table.freeze(RoomSounds)
