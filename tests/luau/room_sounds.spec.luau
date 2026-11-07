local Ui = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Ui
local RoomSounds = require(Ui.RoomSounds)
local SoundIds = require(Ui.SoundIds)

test("room attacks use their own sound slots and unknown rooms fall back", function()
	for _, case in {
		{ "SlimeNest", "SlimeAttack" }, { "DragonLair", "DragonGrowl" },
		{ "EclipseBastion", "DragonGrowl" }, { "PhoenixNest", "PhoenixCall", "FireBurst" },
		{ "SunfireSanctum", "PhoenixCall", "FireBurst" }, { "Unknown", "Hit" },
	} do
		local slots = RoomSounds.Attack(case[1])
		for i = 2, #case do
			expectEq(slots[i - 1], case[i], case[1])
			expect(SoundIds[case[i]] ~= nil, "sound slot exists")
		end
	end
	expectEq(RoomSounds.Trap("FlameVent"), "FireBurst", "flame trap")
	expectEq(RoomSounds.Trap("SpikeHall"), "SpikeStrike", "other traps")
end)
