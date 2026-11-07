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
atlas.Upgrade = rect(40, 639, 250, 243, items, 1290)
atlas.Heal = rect(353, 658, 245, 214, items, 1290)
atlas.Flag = rect(970, 636, 285, 239, items, 1290)
atlas.Box = rect(47, 87, 305, 247, chests, 1448)
atlas.RareBox = rect(1091, 711, 322, 289, chests, 1448)
atlas.CrystalBox = rect(747, 46, 308, 288, chests, 1448)
atlas.PanelLarge = rect(640, 49, 556, 397, inventory, 1536)
atlas.PanelLarge.SliceCenter = Rect.new(35, 35, 335, 230)
atlas.TitleBar = rect(984, 758, 390, 92, inventory, 1536)
atlas.TitleBar.Stretch = true

atlas.ButtonSecondary = rect(25, 750, 405, 135)
atlas.ButtonPrimary = rect(450, 750, 405, 135)
for _, button in { atlas.ButtonSecondary, atlas.ButtonPrimary } do
	button.SliceCenter = Rect.new(35, 30, 200, 48)
end

return atlas
