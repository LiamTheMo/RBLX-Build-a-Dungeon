-- SpriteIds4: generated sprites (v4), now only the icon glyphs (Icons, Feedback.Icon*) and the in-world art (World.*) that the
-- v6 kit does not replace. Every frame, button, bar, chip, badge, toast and feedback sprite lives in SpriteIds6.
-- Spec = { Id, Size = native pixel size }.
local function N(id: string, w: number, h: number)
	return table.freeze({ Id = id, Size = Vector2.new(w, h) })
end

local feedback_IconInfo = N("rbxassetid://89688564912456", 354, 356)
local feedback_IconGood = N("rbxassetid://85787218264621", 354, 356)
local feedback_IconWarn = N("rbxassetid://105341163081113", 382, 342)
local icons_Slow = N("rbxassetid://136048536847325", 350, 358)
local icons_SureFooted = N("rbxassetid://102595517326726", 396, 332)
local icons_ReducedMotion = N("rbxassetid://120706022584462", 342, 350)
local icons_ModifierRing = N("rbxassetid://98683850915344", 378, 384)
local icons_ModBlazing = N("rbxassetid://73007005714450", 326, 374)
local icons_ModLucky = N("rbxassetid://135350826303196", 342, 358)
local icons_ModGolden = N("rbxassetid://124173659403876", 364, 366)
local icons_CoinFloat = N("rbxassetid://108341842985476", 292, 294)
local icons_XpFloat = N("rbxassetid://94586674443086", 294, 282)
local icons_Back = N("rbxassetid://127289362002997", 290, 294)
local icons_Plus = N("rbxassetid://74930471103484", 290, 294)
local icons_Minus = N("rbxassetid://129205944294027", 292, 294)
local icons_Sort = N("rbxassetid://130858590151227", 290, 294)
local icons_Filter = N("rbxassetid://78213812111445", 290, 294)
local icons_Crown = N("rbxassetid://128453973115934", 334, 268)
local world_CellValid = N("rbxassetid://92259891986553", 298, 308)
local world_CellInvalid = N("rbxassetid://108329461130831", 298, 308)
local world_CellSelected = N("rbxassetid://85667983175143", 298, 308)
local world_RouteDot = N("rbxassetid://96600629257510", 158, 156)
local world_RouteArrow = N("rbxassetid://70803787260885", 240, 286)
local world_GhostOk = N("rbxassetid://140261644918209", 298, 300)
local world_GhostBad = N("rbxassetid://131074565202538", 300, 304)
local world_HitBurst = N("rbxassetid://130323322701518", 322, 318)
local world_VfxSparkle = N("rbxassetid://112527185382960", 256, 270)
local world_VfxPuff = N("rbxassetid://90106257758601", 272, 282)
local world_VfxRing = N("rbxassetid://101837662890220", 284, 284)

return table.freeze({
	Feedback = table.freeze({
		IconInfo = feedback_IconInfo,
		IconGood = feedback_IconGood,
		IconWarn = feedback_IconWarn,
	}),
	Icons = table.freeze({
		Slow = icons_Slow,
		SureFooted = icons_SureFooted,
		ReducedMotion = icons_ReducedMotion,
		ModifierRing = icons_ModifierRing,
		ModBlazing = icons_ModBlazing,
		ModLucky = icons_ModLucky,
		ModGolden = icons_ModGolden,
		CoinFloat = icons_CoinFloat,
		XpFloat = icons_XpFloat,
		Back = icons_Back,
		Plus = icons_Plus,
		Minus = icons_Minus,
		Sort = icons_Sort,
		Filter = icons_Filter,
		Crown = icons_Crown,
	}),
	World = table.freeze({
		CellValid = world_CellValid,
		CellInvalid = world_CellInvalid,
		CellSelected = world_CellSelected,
		RouteDot = world_RouteDot,
		RouteArrow = world_RouteArrow,
		GhostOk = world_GhostOk,
		GhostBad = world_GhostBad,
		HitBurst = world_HitBurst,
		VfxSparkle = world_VfxSparkle,
		VfxPuff = world_VfxPuff,
		VfxRing = world_VfxRing,
	}),
})
