-- Group-owned HUD sheet; Roblox stores the 1753 px source at 1024 px wide.
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
local bars, navigation, buttons, cards, panels = "rbxassetid://139331720265035", "rbxassetid://117617146296814", "rbxassetid://107056527648132", "rbxassetid://135428637152317", "rbxassetid://139268516777631"
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
atlas.Cross = rect(910, 51, 92, 94, cards, 1536)
atlas.Close = atlas.Cross
atlas.PanelLarge = rect(32, 35, 801, 535, panels, 1536)
atlas.PanelLarge.SliceCenter = Rect.new(55, 45, 479, 312)
atlas.TitleBar = rect(663, 655, 448, 111, navigation, 1774)
atlas.TitleBar.Stretch = true

atlas.ButtonSecondary = rect(38, 49, 372, 139, buttons, 1536)
atlas.ButtonSecondaryPressed = rect(785, 49, 352, 139, buttons, 1536)
atlas.ButtonPrimary = rect(36, 223, 374, 143, buttons, 1536)
atlas.ButtonPrimaryPressed = rect(784, 223, 353, 143, buttons, 1536)
atlas.ButtonDisabled = rect(1150, 48, 349, 139, buttons, 1536)
for _, button in { atlas.ButtonSecondary, atlas.ButtonSecondaryPressed, atlas.ButtonPrimary, atlas.ButtonPrimaryPressed, atlas.ButtonDisabled } do
	button.SliceCenter = Rect.new(42, 30, button.Size.X - 42, button.Size.Y - 30)
end
atlas.BarTrack = rect(878, 67, 424, 81, bars, 1774)
atlas.BarTrack.SliceCenter = Rect.new(20, 20, atlas.BarTrack.Size.X - 20, atlas.BarTrack.Size.Y - 20)
atlas.BarFill = rect(1318, 72, 431, 71, bars, 1774)
atlas.BarFill.SliceCenter = Rect.new(18, 18, atlas.BarFill.Size.X - 18, atlas.BarFill.Size.Y - 18)

return atlas
