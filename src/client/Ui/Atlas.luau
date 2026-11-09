-- Icon sub-rects only (frames, buttons and bars are the SpriteIds6 kit). Group-owned HUD sheet; Roblox stores the 1753 px source at 1024 px wide.
local function rect(x: number, y: number, w: number, h: number, id: string?, sourceWidth: number?)
	local function pixel(n: number): number
		return math.floor(n * 1024 / (sourceWidth or 1753) + 0.5)
	end
	return { Id = id or "rbxassetid://112270935978547", Offset = Vector2.new(pixel(x), pixel(y)), Size = Vector2.new(pixel(w), pixel(h)) }
end

local atlas = {
	Build = rect(1202, 466, 126, 121),
	Shop = rect(1335, 466, 126, 121),
	Bag = rect(1467, 466, 126, 121),
	Collection = rect(1598, 466, 130, 121),
	Coin = rect(996, 324, 105, 103),
	Vault = rect(1112, 320, 120, 111),
	Settings = rect(1594, 307, 143, 143),
}

local threat, items, chests = "rbxassetid://97949765287019", "rbxassetid://98593157111323", "rbxassetid://72238203709732"
local inventory = "rbxassetid://109366640514096"
local materials, playerStats, roomStats, roomTypes, rooms = "rbxassetid://83405544394544", "rbxassetid://96510912195695", "rbxassetid://138241240576927", "rbxassetid://130107090233949", "rbxassetid://117553040809030"
local navigation = "rbxassetid://117617146296814"
for i, bounds in { {46,33,222,222}, {302,33,220,221}, {554,33,220,222}, {806,33,220,221}, {1056,33,219,221}, {1305,33,225,222} } do
	atlas["T" .. i] = rect(bounds[1], bounds[2], bounds[3], bounds[4], threat, 1774)
end
atlas.ThreatLock = rect(1546, 106, 97, 115, threat, 1774)
atlas.ThreatCheck = rect(1656, 116, 92, 92, threat, 1774)
atlas.CoinStack = rect(364, 59, 246, 231, items, 1290)
atlas.Exchange = rect(685, 49, 282, 246, items, 1290)
atlas.Clock = rect(674, 341, 251, 259, items, 1290)
atlas.Lock = rect(63, 341, 210, 250, items, 1290)
atlas.Thief = rect(366, 341, 235, 259, items, 1290)
atlas.Upgrade = rect(1220, 328, 124, 108, navigation, 1774)
atlas.Heal = rect(353, 658, 245, 214, items, 1290)
atlas.Flag = rect(970, 636, 285, 239, items, 1290)
atlas.DropChance = rect(967, 341, 288, 259, items, 1290)
atlas.Speed = rect(967, 51, 273, 244, items, 1290)
atlas.Sword = rect(32, 842, 233, 249, materials, 1402)
atlas.Shield = rect(308, 842, 224, 250, materials, 1402)
atlas.Blueprint = rect(567, 306, 271, 227, materials, 1402)
atlas.BlueprintCard = rect(846, 573, 257, 233, materials, 1402)
atlas.Keeper = rect(46, 32, 244, 272, playerStats, 1261)
atlas.Level = rect(337, 46, 273, 261, playerStats, 1261)
atlas.Xp = rect(651, 57, 254, 233, playerStats, 1261)
atlas.Trophy = rect(27, 953, 267, 260, playerStats, 1261)
atlas.CoinRange = rect(51, 574, 277, 268, roomStats, 1402)
atlas.Support = rect(718, 280, 288, 246, roomStats, 1402)
atlas.Trap = rect(55, 28, 283, 250, roomTypes, 1402)
atlas.Defender = rect(740, 310, 262, 234, roomTypes, 1402)
atlas.Entrance = rect(46, 31, 334, 299, rooms, 1536)
atlas.SpikeHall = rect(31, 354, 339, 329, rooms, 1536)
atlas.TreasureRoom = rect(409, 354, 330, 329, rooms, 1536)
atlas.Box = rect(47, 87, 305, 247, chests, 1448)
atlas.RareBox = rect(1091, 711, 322, 289, chests, 1448)
atlas.CrystalBox = rect(747, 46, 308, 288, chests, 1448)
atlas.Rooms = rect(40, 600, 85, 95, inventory, 1536)

return atlas
