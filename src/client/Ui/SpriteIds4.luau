-- SpriteIds4: AI design assistant-generated UI sprites (v4). Generated from Assets/BuildADungeon/ui/sprites/v4 (slices.json, manifest.ids.json).
-- Spec = { Id, SliceCenter (9-slice frames only), Size = native pixel size }. Every 9-slice border band is >= 24 px at native size.
-- Frames is an alias of the same spec objects (not copies). Notes: Feedback.Divider keeps its centre ornament (slice is a 2px centre column, so
-- it only grows horizontally past native width and stretches the diamond); Feedback.TutorialBubble's bottom slice includes its tail;
-- Reel.Burst / Feedback.GlowSoft are additive light on transparent, Feedback.Scrim is a black vignette (alpha), Reel.BurstMagenta is the raw magenta-keyed sheet cell.
-- Thin bars (Controls.SliderFill/DefenderHp*) carry transparent top/bottom padding so their 24 px bands fit.
local function S(id: string, w: number, h: number, l: number, t: number, r: number, b: number)
	return table.freeze({ Id = id, SliceCenter = Rect.new(l, t, r, b), Size = Vector2.new(w, h) })
end
local function N(id: string, w: number, h: number)
	return table.freeze({ Id = id, Size = Vector2.new(w, h) })
end

local panels_Large = S("rbxassetid://83520285511315", 1024, 759, 98, 98, 926, 661)
local panels_Small = S("rbxassetid://110501062923196", 338, 334, 59, 59, 279, 275)
local panels_Card = S("rbxassetid://125305570602753", 358, 426, 55, 55, 303, 371)
local panels_Row = S("rbxassetid://87192296313060", 754, 116, 41, 41, 713, 75)
local panels_HudPill = S("rbxassetid://74464604719723", 520, 152, 66, 66, 454, 86)
local panels_Chip = S("rbxassetid://105965096211761", 252, 120, 49, 49, 203, 71)
local panels_Tooltip = S("rbxassetid://132748851817457", 372, 184, 42, 42, 330, 142)
local panels_TabOn = S("rbxassetid://125853962737382", 328, 168, 43, 43, 285, 125)
local panels_TabOff = S("rbxassetid://125168716957975", 328, 168, 42, 42, 286, 126)
local panels_TitleBar = S("rbxassetid://106376964190842", 526, 146, 43, 43, 483, 103)
local buttons_PrimaryNormal = table.freeze({ Id = "rbxassetid://115081075639992", Size = Vector2.new(1024, 512), Stretch = true })
local buttons_PrimaryPressed = buttons_PrimaryNormal
local buttons_SuccessNormal = S("rbxassetid://108729837400547", 386, 214, 60, 60, 326, 154)
local buttons_SuccessPressed = S("rbxassetid://98275259356764", 386, 216, 52, 52, 334, 164)
local buttons_DangerNormal = S("rbxassetid://76630001681991", 388, 214, 60, 60, 328, 154)
local buttons_DangerPressed = S("rbxassetid://117619699963794", 388, 216, 52, 52, 336, 164)
local buttons_SecondaryNormal = S("rbxassetid://79207725840005", 388, 214, 60, 60, 328, 154)
local buttons_SecondaryPressed = S("rbxassetid://84419118676363", 388, 216, 52, 52, 336, 164)
local buttons_Round = N("rbxassetid://117210825314339", 268, 270)
local bars_Track = S("rbxassetid://110624136948297", 764, 178, 74, 74, 690, 104)
local bars_Fill = S("rbxassetid://71455913612341", 762, 174, 68, 68, 694, 106)
local bars_SliderTrack = S("rbxassetid://109939877549256", 936, 100, 39, 39, 897, 61)
local bars_Knob = N("rbxassetid://75142309922339", 174, 176)
local bars_ToggleOn = N("rbxassetid://79934247291312", 450, 226)
local bars_ToggleOff = N("rbxassetid://88533011819497", 452, 226)
local rarity_Common = S("rbxassetid://95787833331781", 402, 520, 64, 64, 338, 456)
local rarity_Uncommon = S("rbxassetid://81747056655712", 400, 520, 65, 65, 335, 455)
local rarity_Rare = S("rbxassetid://123329972403250", 400, 520, 63, 63, 337, 457)
local rarity_Epic = S("rbxassetid://75907774251512", 402, 520, 64, 64, 338, 456)
local rarity_Legendary = S("rbxassetid://93820021342303", 402, 520, 65, 65, 337, 455)
local rarity_Mythic = S("rbxassetid://105762393156631", 656, 818, 103, 103, 553, 715)
local rarity_Secret = S("rbxassetid://98400684178595", 656, 818, 102, 102, 554, 716)
local reel_Window = S("rbxassetid://79114447409728", 1024, 254, 69, 69, 955, 185)
local reel_PointerTop = N("rbxassetid://75613940711173", 218, 150)
local reel_PointerBottom = N("rbxassetid://81146658031410", 216, 150)
local reel_Slot = S("rbxassetid://73882514869308", 422, 404, 80, 80, 342, 324)
local reel_Burst = N("rbxassetid://100058378678372", 512, 512)
local reel_BurstMagenta = N("rbxassetid://131387027427398", 512, 512)
local reel_SpinButton = S("rbxassetid://133002031004627", 708, 284, 85, 85, 623, 199)
local feedback_ToastInfo = S("rbxassetid://108534141182869", 562, 166, 67, 67, 495, 99)
local feedback_ToastGood = S("rbxassetid://100176252349726", 554, 166, 67, 67, 487, 99)
local feedback_ToastBad = S("rbxassetid://135206857911362", 560, 166, 66, 66, 494, 100)
local feedback_IconInfo = N("rbxassetid://89688564912456", 354, 356)
local feedback_IconGood = N("rbxassetid://85787218264621", 354, 356)
local feedback_IconWarn = N("rbxassetid://105341163081113", 382, 342)
local feedback_TutorialBubble = S("rbxassetid://101207243362861", 540, 336, 69, 69, 471, 204)
local feedback_TutorialArrow = N("rbxassetid://75336640368125", 318, 352)
local feedback_HighlightRing = S("rbxassetid://121533632122592", 538, 306, 69, 69, 469, 237)
local feedback_LevelUpBanner = N("rbxassetid://123378544865395", 644, 210)
local feedback_GlowSoft = N("rbxassetid://90958109542525", 512, 512)
local feedback_LoadFailPanel = S("rbxassetid://93602991098482", 550, 304, 67, 67, 483, 237)
local feedback_Scrim = N("rbxassetid://86194880101333", 512, 512)
local feedback_EmptyBox = N("rbxassetid://104312913165291", 314, 336)
local feedback_LoadingSpinner = N("rbxassetid://101356699982664", 296, 296)
local feedback_Divider = S("rbxassetid://104978215706340", 1024, 66, 511, 0, 513, 66)
local controls_ButtonDisabled = table.freeze({ Id = "rbxassetid://132717535749322", Size = Vector2.new(1024, 512), Stretch = true })
local controls_ButtonShadow = S("rbxassetid://78837770792182", 620, 242, 59, 59, 561, 183)
local controls_SliderFill = S("rbxassetid://89153734866517", 1024, 58, 24, 24, 1000, 34)
local controls_ScrollBarThumb = S("rbxassetid://97994904710414", 86, 366, 34, 34, 52, 332)
local controls_ScrollBarTrack = S("rbxassetid://88067342178505", 86, 366, 33, 33, 53, 333)
local controls_DropPill = S("rbxassetid://119965393858656", 370, 120, 52, 52, 318, 68)
local controls_DefenderHpTrack = S("rbxassetid://118617366362360", 1024, 56, 24, 24, 1000, 32)
local controls_DefenderHpFill = S("rbxassetid://131357595038229", 1024, 56, 24, 24, 1000, 32)
local controls_ChipGold = S("rbxassetid://116010970718994", 388, 166, 70, 70, 318, 96)
local controls_ChipGreen = S("rbxassetid://83915234500467", 382, 164, 69, 69, 313, 95)
local controls_ChipRed = S("rbxassetid://114827007981038", 380, 164, 69, 69, 311, 95)
local controls_ChipGrey = S("rbxassetid://95858753489157", 384, 166, 71, 71, 313, 95)
local controls_ChipDark = S("rbxassetid://76497259939065", 386, 168, 72, 72, 314, 96)
local controls_RarityBadgeCommon = S("rbxassetid://129397971405926", 330, 144, 62, 62, 268, 82)
local controls_RarityBadgeUncommon = S("rbxassetid://138474878761246", 330, 144, 63, 63, 267, 81)
local controls_RarityBadgeRare = S("rbxassetid://89937567468381", 330, 144, 62, 62, 268, 82)
local controls_RarityBadgeEpic = S("rbxassetid://118871256373016", 328, 144, 62, 62, 266, 82)
local controls_RarityBadgeLegendary = S("rbxassetid://127730200807804", 330, 144, 63, 63, 267, 81)
local controls_RarityBadgeMythic = S("rbxassetid://125302753122060", 330, 144, 48, 48, 282, 96)
local controls_RarityBadgeSecret = S("rbxassetid://91674247417525", 330, 144, 62, 62, 268, 82)
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
local world_SignBoardOwned = S("rbxassetid://125171418630241", 406, 266, 55, 55, 351, 211)
local world_SignBoardFree = S("rbxassetid://105037912850813", 396, 266, 49, 49, 347, 217)
local world_HitBurst = N("rbxassetid://130323322701518", 322, 318)
local world_VfxSparkle = N("rbxassetid://112527185382960", 256, 270)
local world_VfxPuff = N("rbxassetid://90106257758601", 272, 282)
local world_VfxRing = N("rbxassetid://101837662890220", 284, 284)

return table.freeze({
	Panels = table.freeze({
		Large = panels_Large,
		Small = panels_Small,
		Card = panels_Card,
		Row = panels_Row,
		HudPill = panels_HudPill,
		Chip = panels_Chip,
		Tooltip = panels_Tooltip,
		TabOn = panels_TabOn,
		TabOff = panels_TabOff,
		TitleBar = panels_TitleBar,
	}),
	Buttons = table.freeze({
		Primary = table.freeze({
			Normal = buttons_PrimaryNormal,
			Pressed = buttons_PrimaryPressed,
		}),
		Success = table.freeze({
			Normal = buttons_SuccessNormal,
			Pressed = buttons_SuccessPressed,
		}),
		Danger = table.freeze({
			Normal = buttons_DangerNormal,
			Pressed = buttons_DangerPressed,
		}),
		Secondary = table.freeze({
			Normal = buttons_SecondaryNormal,
			Pressed = buttons_SecondaryPressed,
		}),
		Round = buttons_Round,
	}),
	Bars = table.freeze({
		Track = bars_Track,
		Fill = bars_Fill,
		SliderTrack = bars_SliderTrack,
		Knob = bars_Knob,
		ToggleOn = bars_ToggleOn,
		ToggleOff = bars_ToggleOff,
	}),
	Rarity = table.freeze({
		Common = table.freeze({
			Frame = rarity_Common,
		}),
		Uncommon = table.freeze({
			Frame = rarity_Uncommon,
		}),
		Rare = table.freeze({
			Frame = rarity_Rare,
		}),
		Epic = table.freeze({
			Frame = rarity_Epic,
		}),
		Legendary = table.freeze({
			Frame = rarity_Legendary,
		}),
		Mythic = table.freeze({
			Frame = rarity_Mythic,
		}),
		Secret = table.freeze({
			Frame = rarity_Secret,
		}),
	}),
	Reel = table.freeze({
		Window = reel_Window,
		Pointer = reel_PointerTop,
		PointerTop = reel_PointerTop,
		PointerBottom = reel_PointerBottom,
		Slot = reel_Slot,
		Burst = reel_Burst,
		BurstMagenta = reel_BurstMagenta,
		SpinButton = reel_SpinButton,
	}),
	Feedback = table.freeze({
		ToastInfo = feedback_ToastInfo,
		ToastGood = feedback_ToastGood,
		ToastBad = feedback_ToastBad,
		IconInfo = feedback_IconInfo,
		IconGood = feedback_IconGood,
		IconWarn = feedback_IconWarn,
		TutorialBubble = feedback_TutorialBubble,
		TutorialArrow = feedback_TutorialArrow,
		HighlightRing = feedback_HighlightRing,
		LevelUpBanner = feedback_LevelUpBanner,
		GlowSoft = feedback_GlowSoft,
		LoadFailPanel = feedback_LoadFailPanel,
		Scrim = feedback_Scrim,
		EmptyBox = feedback_EmptyBox,
		LoadingSpinner = feedback_LoadingSpinner,
		Divider = feedback_Divider,
	}),
	Controls = table.freeze({
		ButtonDisabled = controls_ButtonDisabled,
		ButtonShadow = controls_ButtonShadow,
		SliderFill = controls_SliderFill,
		ScrollBarThumb = controls_ScrollBarThumb,
		ScrollBarTrack = controls_ScrollBarTrack,
		DropPill = controls_DropPill,
		DefenderHpTrack = controls_DefenderHpTrack,
		DefenderHpFill = controls_DefenderHpFill,
		Chip = table.freeze({
			Gold = controls_ChipGold,
			Green = controls_ChipGreen,
			Red = controls_ChipRed,
			Grey = controls_ChipGrey,
			Dark = controls_ChipDark,
		}),
		RarityBadge = table.freeze({
			Common = controls_RarityBadgeCommon,
			Uncommon = controls_RarityBadgeUncommon,
			Rare = controls_RarityBadgeRare,
			Epic = controls_RarityBadgeEpic,
			Legendary = controls_RarityBadgeLegendary,
			Mythic = controls_RarityBadgeMythic,
			Secret = controls_RarityBadgeSecret,
		}),
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
		SignBoardOwned = world_SignBoardOwned,
		SignBoardFree = world_SignBoardFree,
		HitBurst = world_HitBurst,
		VfxSparkle = world_VfxSparkle,
		VfxPuff = world_VfxPuff,
		VfxRing = world_VfxRing,
	}),
	Frames = table.freeze({
		PanelLarge = panels_Large,
		PanelSmall = panels_Small,
		Pill = panels_HudPill,
		Card = table.freeze({
			Common = rarity_Common,
			Uncommon = rarity_Uncommon,
			Rare = rarity_Rare,
			Epic = rarity_Epic,
			Legendary = rarity_Legendary,
			Mythic = rarity_Mythic,
			Secret = rarity_Secret,
		}),
	}),
})
