--!strict
-- SpriteIds6: unified purple+gold UI kit. Every sprite is shown as ONE whole image at its native aspect
-- (never 9-sliced or stretched): lock the element with a UIAspectRatioConstraint of Size.X/Size.Y and place
-- content inside Inner (native px; convert to Scale = Inner/Size). Sources, prompts and upload manifests are in
-- Assets/UI/BaD/ui/NEW/v6 (STYLE.md, sprites/, icons/, manifest.ids.json, ids_group2.json, inner.json).
local function S(id: string, w: number, h: number, l: number?, t: number?, r: number?, b: number?)
	return table.freeze({ Id = id, Size = Vector2.new(w, h), Inner = if l then Rect.new(l, t :: number, r :: number, b :: number) else nil })
end

local M = {}
M.Arrow = table.freeze({
	Tutorial = S("rbxassetid://124795924181263", 322, 216),
})
M.Badge = table.freeze({
	Count = S("rbxassetid://81538679527299", 142, 78, 14, 20, 129, 63),
	Dot = S("rbxassetid://99042035077105", 76, 76),
	Round = S("rbxassetid://76232211434914", 114, 114, 17, 27, 98, 91),
})
M.Banner = table.freeze({
	LevelUp = S("rbxassetid://114614386004310", 680, 248),
})
M.Bar = table.freeze({
	FillBlue = S("rbxassetid://96260621229886", 324, 88, 17, 28, 309, 64),
	FillGreen = S("rbxassetid://106681049082709", 324, 88, 16, 28, 308, 61),
	FillPurple = S("rbxassetid://128831999169502", 324, 88, 16, 28, 308, 64),
	FillRed = S("rbxassetid://133916315607812", 324, 88, 16, 28, 308, 61),
	FillYellow = S("rbxassetid://113099339334300", 324, 88, 16, 28, 309, 64),
	Track = S("rbxassetid://100229637715870", 518, 98, 30, 28, 490, 72),
})
M.Bubble = table.freeze({
	Tutorial = S("rbxassetid://127131468595583", 264, 166, 28, 27, 239, 110),
	Wide = S("rbxassetid://95589735515724", 590, 214, 32, 32, 560, 154),
})
M.Button = table.freeze({
	CloseSmall = S("rbxassetid://135208426245124", 144, 144),
	Green = S("rbxassetid://115984806014458", 330, 160, 16, 34, 314, 124),
	GreenPressed = S("rbxassetid://85203525287544", 330, 136, 16, 31, 314, 106),
	Grey = S("rbxassetid://85548380246315", 336, 160, 16, 33, 321, 124),
	GreyPressed = S("rbxassetid://106920705960854", 336, 136, 16, 30, 319, 107),
	Purple = S("rbxassetid://124537729370508", 332, 160, 16, 34, 316, 124),
	PurplePressed = S("rbxassetid://100105881253318", 332, 136, 15, 31, 314, 107),
	Red = S("rbxassetid://128605537186698", 332, 160, 17, 33, 317, 124),
	RedPressed = S("rbxassetid://94943029927312", 332, 136, 17, 31, 316, 107),
	Yellow = S("rbxassetid://75033877096569", 340, 160, 16, 31, 324, 144),
	YellowPressed = S("rbxassetid://119306897580867", 340, 136, 16, 30, 324, 107),
})
M.ButtonPrice = table.freeze({
	Grey = S("rbxassetid://139993279818569", 352, 120, 15, 27, 336, 89),
	Yellow = S("rbxassetid://76124777878932", 352, 120, 16, 27, 338, 92),
})
M.ButtonWide = table.freeze({
	Green = S("rbxassetid://118573572900189", 520, 128, 15, 31, 505, 95),
	Grey = S("rbxassetid://138434578042252", 518, 128, 16, 28, 503, 96),
	Purple = S("rbxassetid://88308984456383", 518, 128, 16, 28, 503, 96),
	Yellow = S("rbxassetid://133273317915237", 518, 126, 15, 27, 504, 96),
})
M.Card = table.freeze({
	Glow = S("rbxassetid://103623161889511", 270, 262, 23, 23, 247, 239),
	Info = S("rbxassetid://78598262719823", 312, 330, 38, 93, 273, 286),
	Normal = S("rbxassetid://74659432699853", 278, 276, 14, 31, 264, 238),
	Selected = S("rbxassetid://105389777823262", 280, 282, 25, 25, 255, 257),
	Shop = S("rbxassetid://97449478276007", 294, 272, 24, 24, 270, 248),
})
M.Chip = table.freeze({
	Dark = S("rbxassetid://100788202644316", 224, 102, 19, 24, 208, 77),
	Gold = S("rbxassetid://131774326421137", 228, 102, 17, 23, 213, 77),
	Green = S("rbxassetid://133634480107790", 214, 102, 16, 25, 199, 73),
	Grey = S("rbxassetid://100008049520932", 214, 102, 16, 24, 198, 74),
	Purple = S("rbxassetid://125654248434360", 214, 102, 15, 24, 199, 73),
	Red = S("rbxassetid://74340675587525", 214, 102, 16, 24, 199, 75),
})
M.Frame = table.freeze({
	Highlight = S("rbxassetid://121087377443842", 606, 306),
})
M.Fx = table.freeze({
	Burst = S("rbxassetid://106680690478238", 274, 270),
	Ring = S("rbxassetid://91306276151867", 254, 258),
	Sparkle = S("rbxassetid://108999236644444", 206, 216),
})
M.Hud = table.freeze({
	BarWide = S("rbxassetid://108651950021322", 534, 128, 39, 41, 496, 93),
	BarWideGold = S("rbxassetid://70689938493214", 534, 128, 38, 41, 495, 93),
	Pill = S("rbxassetid://125053297286440", 538, 152, 38, 35, 501, 117),
	PillGold = S("rbxassetid://120669653874146", 540, 150, 38, 46, 503, 110),
})
M.Icons = table.freeze({
	Bag = S("rbxassetid://93621813755645", 123, 121),
	Blueprint = S("rbxassetid://140454558960019", 283, 239),
	BlueprintCard = S("rbxassetid://129435978967145", 269, 245),
	Box = S("rbxassetid://125716095823635", 317, 259),
	Build = S("rbxassetid://127636461323852", 116, 118),
	Clock = S("rbxassetid://80542761631904", 262, 264),
	Coin = S("rbxassetid://71867935707681", 106, 104),
	CoinRange = S("rbxassetid://109595343485924", 289, 246),
	CoinStack = S("rbxassetid://96636844346820", 258, 243),
	Collection = S("rbxassetid://71207711257435", 127, 128),
	CrystalBox = S("rbxassetid://129178468420107", 320, 300),
	Defender = S("rbxassetid://134376062080032", 274, 246),
	DropChance = S("rbxassetid://79324385284685", 282, 248),
	Entrance = S("rbxassetid://113663360977489", 346, 311),
	Exchange = S("rbxassetid://94994771291159", 233, 258),
	Flag = S("rbxassetid://95275952454989", 297, 251),
	Heal = S("rbxassetid://96332579734253", 257, 226),
	Keeper = S("rbxassetid://117477323450955", 256, 284),
	Level = S("rbxassetid://126414971415140", 285, 273),
	Lock = S("rbxassetid://129175703058388", 222, 262),
	RareBox = S("rbxassetid://111106900070361", 334, 301),
	Rooms = S("rbxassetid://121544574734556", 97, 106),
	Settings = S("rbxassetid://117515051869127", 140, 141),
	Shield = S("rbxassetid://95125767830719", 236, 274),
	Shop = S("rbxassetid://104320249933398", 119, 119),
	Speed = S("rbxassetid://116884760847901", 288, 256),
	SpikeHall = S("rbxassetid://113044244907479", 351, 317),
	Support = S("rbxassetid://136576982179017", 300, 202),
	Sword = S("rbxassetid://138291939536664", 245, 271),
	T1 = S("rbxassetid://82009474856627", 234, 234),
	T2 = S("rbxassetid://83067097245001", 232, 233),
	T3 = S("rbxassetid://126535989558108", 232, 234),
	T4 = S("rbxassetid://77220108200765", 232, 233),
	T5 = S("rbxassetid://112879503374171", 231, 233),
	T6 = S("rbxassetid://75690411037522", 237, 234),
	Thief = S("rbxassetid://111893680039742", 247, 271),
	ThreatCheck = S("rbxassetid://99303788507646", 104, 104),
	ThreatLock = S("rbxassetid://95147177866296", 109, 127),
	Trap = S("rbxassetid://94172491515713", 295, 262),
	TreasureRoom = S("rbxassetid://113044683007599", 342, 318),
	Trophy = S("rbxassetid://102350501878611", 279, 272),
	Upgrade = S("rbxassetid://107788005721706", 137, 121),
	Vault = S("rbxassetid://95927741585331", 118, 107),
	Xp = S("rbxassetid://140142301804523", 266, 245),
})
M.Misc = table.freeze({
	Divider = S("rbxassetid://112896307197551", 1546, 142),
	Spinner = S("rbxassetid://125706538765226", 284, 294),
})
M.Nav = table.freeze({
	Off = S("rbxassetid://118487532372483", 194, 192, 16, 29, 179, 159),
	On = S("rbxassetid://138023557784323", 192, 192, 14, 27, 168, 177),
})
M.Panel = table.freeze({
	Modal = S("rbxassetid://79959803435761", 890, 494, 46, 121, 846, 461),
	ModalCompact = S("rbxassetid://70388395507504", 394, 270, 42, 77, 353, 225),
	ModalPlain = S("rbxassetid://111642189767710", 1000, 531, 63, 91, 937, 464),
	ModalPlainCompact = S("rbxassetid://111715745452358", 738, 534, 63, 91, 677, 467),
	ModalPlainSquare = S("rbxassetid://118059995141226", 570, 537, 62, 92, 509, 469),
	Section = S("rbxassetid://106520131567491", 706, 248, 29, 36, 678, 215),
	SectionPlate = S("rbxassetid://77436846540511", 712, 210),
	TitlePlate = S("rbxassetid://115722331101487", 654, 218),
	Tooltip = S("rbxassetid://78138698643770", 418, 264, 32, 41, 388, 224),
	TooltipLeft = S("rbxassetid://130025648538129", 532, 196, 46, 40, 502, 161),
	Tray = S("rbxassetid://80934188132067", 1142, 204, 49, 52, 1093, 148),
})
M.Pointer = table.freeze({
	Down = S("rbxassetid://137648672216026", 252, 198),
	Up = S("rbxassetid://123089572415464", 250, 200),
})
M.Rarity = table.freeze({
	Common = S("rbxassetid://134247835801814", 236, 314, 31, 47, 206, 268),
	Epic = S("rbxassetid://140201879227538", 226, 314, 31, 49, 197, 268),
	Legendary = S("rbxassetid://123369198330352", 226, 314, 29, 45, 198, 269),
	Mythic = S("rbxassetid://116424299797876", 226, 312, 31, 47, 197, 266),
	Rare = S("rbxassetid://90969023428867", 226, 314, 30, 47, 197, 268),
	Secret = S("rbxassetid://131457014751316", 222, 312, 29, 45, 197, 268),
	Uncommon = S("rbxassetid://73134528092380", 230, 312, 26, 43, 204, 268),
})
M.RarityBadge = table.freeze({
	Common = S("rbxassetid://90989478529959", 216, 82, 17, 24, 199, 62),
	Epic = S("rbxassetid://138964924862481", 212, 82, 15, 24, 195, 61),
	Legendary = S("rbxassetid://120551649796189", 210, 82, 14, 23, 194, 61),
	Mythic = S("rbxassetid://93580130668712", 210, 82, 15, 24, 195, 61),
	Rare = S("rbxassetid://128676260246092", 212, 82, 15, 24, 198, 61),
	Secret = S("rbxassetid://94264757346165", 206, 82, 7, 7, 199, 75),
	Uncommon = S("rbxassetid://121161348229039", 212, 82, 15, 24, 196, 61),
})
M.Round = table.freeze({
	Back = S("rbxassetid://91280811190052", 212, 216),
	Close = S("rbxassetid://84773403257971", 212, 216),
	Confirm = S("rbxassetid://124396077262537", 210, 214),
	Lock = S("rbxassetid://99822092993015", 258, 264),
	Purple = S("rbxassetid://126279824844928", 192, 198),
	Yellow = S("rbxassetid://86268474372911", 196, 200),
})
M.Row = table.freeze({
	Well = S("rbxassetid://130433812286813", 514, 126, 23, 25, 493, 100),
})
M.Scroll = table.freeze({
	Thumb = S("rbxassetid://136138542386618", 78, 270, 16, 27, 63, 246),
	Track = S("rbxassetid://95127597448995", 88, 270, 27, 27, 65, 246),
})
M.Slider = table.freeze({
	Sample = S("rbxassetid://135360647425987", 574, 134),
})
M.Slot = table.freeze({
	Empty = S("rbxassetid://113562524320110", 272, 272, 24, 28, 249, 241),
})
M.Tab = table.freeze({
	Off = S("rbxassetid://90311517034326", 400, 158, 16, 33, 385, 123),
	On = S("rbxassetid://139303945146725", 412, 160, 16, 33, 396, 128),
	WideOff = S("rbxassetid://137826858927308", 516, 126, 15, 27, 500, 94),
	WideOn = S("rbxassetid://109530714902679", 522, 124, 16, 27, 507, 94),
})
M.Tag = table.freeze({
	Label = S("rbxassetid://128913380041878", 254, 94, 15, 21, 241, 79),
	New = S("rbxassetid://103700995474863", 198, 102),
})
M.Toast = table.freeze({
	Bad = S("rbxassetid://103930598932468", 366, 146, 28, 32, 341, 114),
	Good = S("rbxassetid://80775578606537", 366, 146, 26, 29, 340, 116),
	Info = S("rbxassetid://94813116822186", 370, 146, 31, 34, 340, 112),
})
M.ToastWide = table.freeze({
	Bad = S("rbxassetid://120752902744333", 540, 120, 34, 37, 510, 89),
	Good = S("rbxassetid://115208398753830", 538, 120, 31, 37, 508, 88),
	Info = S("rbxassetid://103875395624247", 538, 120, 31, 37, 508, 89),
})
M.Toggle = table.freeze({
	Off = S("rbxassetid://89952357635516", 278, 148),
	On = S("rbxassetid://73052069610157", 278, 148),
})
-- Room art for inventory/shop/index tiles (whole 512x512 images). Every room has its own art.
M.RoomIcons = table.freeze({
	ArcaneBarricade = S("rbxassetid://115288978373278", 512, 512),
	ArrowGallery = S("rbxassetid://79639818475694", 512, 512),
	BatRoost = S("rbxassetid://125472932287116", 512, 512),
	CelestialCoffer = S("rbxassetid://136535079073870", 512, 512),
	CrystalBarricade = S("rbxassetid://127455416938669", 512, 512),
	CrystalGuard = S("rbxassetid://123445622737032", 512, 512),
	CrystalSentinel = S("rbxassetid://127466329241734", 512, 512),
	CrystalSentry = S("rbxassetid://95002116829939", 512, 512),
	DragonHoard = S("rbxassetid://130966553174051", 512, 512),
	DragonLair = S("rbxassetid://117277836838985", 512, 512),
	EclipseBastion = S("rbxassetid://97098760329380", 512, 512),
	EmeraldGuardroom = S("rbxassetid://92046899946076", 512, 512),
	Entrance = S("rbxassetid://126432328134696", 512, 512),
	FlameVent = S("rbxassetid://103225137868499", 512, 512),
	FrostChamber = S("rbxassetid://93828168581956", 512, 512),
	GoblinBarracks = S("rbxassetid://118995575984909", 512, 512),
	GolemForge = S("rbxassetid://79947337788576", 512, 512),
	GuardRoom = S("rbxassetid://111091204437374", 512, 512),
	LichSanctum = S("rbxassetid://108902747863435", 512, 512),
	MimicRoom = S("rbxassetid://129167098886165", 512, 512),
	MonsterDen = S("rbxassetid://129723880342230", 512, 512),
	MushroomCavern = S("rbxassetid://110011981383990", 512, 512),
	PhoenixNest = S("rbxassetid://128877038598021", 512, 512),
	PrismBastion = S("rbxassetid://108366341215640", 512, 512),
	PrismGallery = S("rbxassetid://102638076067878", 512, 512),
	PrismSanctum = S("rbxassetid://111579678264244", 512, 512),
	PrismSentinel = S("rbxassetid://75406784596511", 512, 512),
	RestlessCrypt = S("rbxassetid://123496586750657", 512, 512),
	RoyalGuard = S("rbxassetid://100425833982826", 512, 512),
	RoyalVault = S("rbxassetid://107628426462591", 512, 512),
	SlimeNest = S("rbxassetid://70861828103018", 512, 512),
	SpikeHall = S("rbxassetid://132751948679953", 512, 512),
	StormGallery = S("rbxassetid://121415823132049", 512, 512),
	Strongbox = S("rbxassetid://125265431928084", 512, 512),
	SunfireSanctum = S("rbxassetid://73804914953856", 512, 512),
	TreasureRoom = S("rbxassetid://118222936707339", 512, 512),
	Treasury = S("rbxassetid://138297619522795", 512, 512),
	VoidGate = S("rbxassetid://99256546060944", 512, 512),
	VoidVault = S("rbxassetid://104724027242505", 512, 512),
})
return table.freeze(M)
