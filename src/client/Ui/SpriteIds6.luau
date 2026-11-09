--!strict
-- SpriteIds6: unified purple+gold UI kit v6 (generated sprites; sources, slices and upload ids in
-- Assets/UI/BaD/ui/NEW/v6: STYLE.md, sprites/, manifest.ids.json). Spec = { Id, Size = native px, SliceCenter? (9-slice) }.
local function S(id: string, w: number, h: number, l: number, t: number, r: number, b: number)
	return table.freeze({ Id = id, Size = Vector2.new(w, h), SliceCenter = Rect.new(l, t, r, b) })
end
local function N(id: string, w: number, h: number)
	return table.freeze({ Id = id, Size = Vector2.new(w, h) })
end

local M = {}
M.Arrow = table.freeze({
	Tutorial = N("rbxassetid://124795924181263", 322, 216),
})
M.Badge = table.freeze({
	Count = S("rbxassetid://81538679527299", 142, 78, 25, 24, 111, 52),
	Dot = N("rbxassetid://99042035077105", 76, 76),
	Round = N("rbxassetid://76232211434914", 114, 114),
})
M.Banner = table.freeze({
	LevelUp = N("rbxassetid://114614386004310", 680, 248),
})
M.Bar = table.freeze({
	FillBlue = S("rbxassetid://96260621229886", 324, 88, 44, 24, 280, 64),
	FillGreen = S("rbxassetid://106681049082709", 324, 88, 44, 24, 280, 64),
	FillPurple = S("rbxassetid://128831999169502", 324, 88, 44, 24, 280, 64),
	FillRed = S("rbxassetid://133916315607812", 324, 88, 44, 24, 280, 64),
	FillYellow = S("rbxassetid://113099339334300", 324, 88, 44, 24, 280, 64),
	Track = S("rbxassetid://100229637715870", 518, 98, 49, 24, 469, 74),
})
M.Bubble = table.freeze({
	Tutorial = S("rbxassetid://127131468595583", 264, 166, 61, 58, 204, 85),
})
M.Button = table.freeze({
	CloseSmall = N("rbxassetid://135208426245124", 144, 144),
	Green = S("rbxassetid://115984806014458", 330, 160, 80, 32, 250, 128),
	GreenPressed = S("rbxassetid://85203525287544", 330, 136, 68, 27, 262, 109),
	Grey = S("rbxassetid://85548380246315", 336, 160, 80, 32, 256, 128),
	GreyPressed = S("rbxassetid://106920705960854", 336, 136, 68, 26, 268, 110),
	Purple = S("rbxassetid://124537729370508", 332, 160, 80, 32, 252, 128),
	PurplePressed = S("rbxassetid://100105881253318", 332, 136, 68, 27, 264, 109),
	Red = S("rbxassetid://128605537186698", 332, 160, 80, 32, 252, 128),
	RedPressed = S("rbxassetid://94943029927312", 332, 136, 68, 27, 264, 109),
	Yellow = S("rbxassetid://75033877096569", 340, 160, 80, 27, 260, 133),
	YellowPressed = S("rbxassetid://119306897580867", 340, 136, 68, 26, 272, 110),
})
M.Card = table.freeze({
	Normal = S("rbxassetid://74659432699853", 278, 276, 36, 36, 225, 216),
	Selected = S("rbxassetid://105389777823262", 280, 282, 59, 56, 210, 212),
})
M.Chip = table.freeze({
	Dark = S("rbxassetid://100788202644316", 224, 102, 51, 21, 173, 81),
	Gold = S("rbxassetid://131774326421137", 228, 102, 51, 21, 177, 81),
	Green = S("rbxassetid://133634480107790", 214, 102, 51, 25, 163, 77),
	Grey = S("rbxassetid://100008049520932", 214, 102, 51, 24, 163, 78),
	Purple = S("rbxassetid://125654248434360", 214, 102, 51, 25, 163, 77),
	Red = S("rbxassetid://74340675587525", 214, 102, 51, 23, 163, 79),
})
M.Frame = table.freeze({
	Highlight = S("rbxassetid://121087377443842", 606, 306, 72, 72, 534, 234),
})
M.Fx = table.freeze({
	Burst = N("rbxassetid://106680690478238", 274, 270),
	Ring = N("rbxassetid://91306276151867", 254, 258),
	Sparkle = N("rbxassetid://108999236644444", 206, 216),
})
M.Hud = table.freeze({
	Pill = S("rbxassetid://125053297286440", 538, 152, 76, 31, 462, 121),
	PillGold = S("rbxassetid://120669653874146", 540, 150, 75, 42, 465, 108),
})
M.Misc = table.freeze({
	Divider = N("rbxassetid://112896307197551", 1546, 142),
	Spinner = N("rbxassetid://125706538765226", 284, 294),
})
M.Nav = table.freeze({
	Off = S("rbxassetid://118487532372483", 194, 192, 35, 34, 146, 140),
	On = S("rbxassetid://138023557784323", 192, 192, 29, 39, 150, 162),
})
M.Panel = table.freeze({
	Modal = S("rbxassetid://79959803435761", 890, 494, 118, 116, 697, 389),
	Section = S("rbxassetid://106520131567491", 706, 248, 50, 49, 649, 194),
	SectionPlate = S("rbxassetid://77436846540511", 712, 210, 178, 100, 534, 110),
	TitlePlate = N("rbxassetid://115722331101487", 654, 218),
	Tooltip = S("rbxassetid://78138698643770", 418, 264, 56, 54, 353, 200),
})
M.Pointer = table.freeze({
	Down = N("rbxassetid://137648672216026", 252, 198),
	Up = N("rbxassetid://123089572415464", 250, 200),
})
M.Rarity = table.freeze({
	Common = S("rbxassetid://134247835801814", 236, 314, 58, 57, 162, 241),
	Epic = S("rbxassetid://140201879227538", 226, 314, 60, 58, 148, 239),
	Legendary = S("rbxassetid://123369198330352", 226, 314, 55, 54, 155, 243),
	Mythic = S("rbxassetid://116424299797876", 226, 312, 58, 56, 152, 239),
	Rare = S("rbxassetid://90969023428867", 226, 314, 57, 56, 152, 241),
	Secret = S("rbxassetid://131457014751316", 222, 312, 55, 51, 151, 242),
	Uncommon = S("rbxassetid://73134528092380", 230, 312, 52, 52, 161, 242),
})
M.RarityBadge = table.freeze({
	Common = S("rbxassetid://90989478529959", 216, 82, 41, 20, 175, 62),
	Epic = S("rbxassetid://138964924862481", 212, 82, 41, 20, 171, 62),
	Legendary = S("rbxassetid://120551649796189", 210, 82, 41, 19, 169, 63),
	Mythic = S("rbxassetid://93580130668712", 210, 82, 41, 20, 169, 62),
	Rare = S("rbxassetid://128676260246092", 212, 82, 41, 20, 171, 62),
	Secret = S("rbxassetid://94264757346165", 206, 82, 41, 20, 165, 62),
	Uncommon = S("rbxassetid://121161348229039", 212, 82, 41, 20, 171, 62),
})
M.Round = table.freeze({
	Back = N("rbxassetid://91280811190052", 212, 216),
	Close = N("rbxassetid://84773403257971", 212, 216),
	Confirm = N("rbxassetid://124396077262537", 210, 214),
	Lock = N("rbxassetid://99822092993015", 258, 264),
	Purple = N("rbxassetid://126279824844928", 192, 198),
	Yellow = N("rbxassetid://86268474372911", 196, 200),
})
M.Scroll = table.freeze({
	Thumb = S("rbxassetid://136138542386618", 78, 270, 31, 30, 36, 231),
	Track = S("rbxassetid://95127597448995", 88, 270, 42, 38, 46, 231),
})
M.Slider = table.freeze({
	Sample = N("rbxassetid://135360647425987", 574, 134),
})
M.Slot = table.freeze({
	Empty = S("rbxassetid://113562524320110", 272, 272, 42, 41, 226, 223),
})
M.Tab = table.freeze({
	Off = S("rbxassetid://90311517034326", 400, 158, 79, 31, 321, 127),
	On = S("rbxassetid://139303945146725", 412, 160, 80, 29, 332, 131),
})
M.Tag = table.freeze({
	Label = S("rbxassetid://128913380041878", 254, 94, 47, 17, 207, 77),
	New = N("rbxassetid://103700995474863", 198, 102),
})
M.Toast = table.freeze({
	Bad = S("rbxassetid://103930598932468", 366, 146, 73, 28, 293, 118),
	Good = S("rbxassetid://80775578606537", 366, 146, 73, 26, 293, 120),
	Info = S("rbxassetid://94813116822186", 370, 146, 73, 30, 297, 116),
})
M.Toggle = table.freeze({
	Off = N("rbxassetid://89952357635516", 278, 148),
	On = N("rbxassetid://73052069610157", 278, 148),
})
return table.freeze(M)
