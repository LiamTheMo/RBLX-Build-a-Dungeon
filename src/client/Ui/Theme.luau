-- Design tokens from docs/UI_SPEC.md. Sizes are reference px (before UIScale).
local function hex(s: string): Color3
	return Color3.fromHex(s)
end

local RarityColors = require(script.Parent.RarityColors)

local Theme = {
	BgDeep = hex("#1E1630"),
	BgPanel = hex("#2E2347"),
	BgRaised = hex("#3F3162"),
	Stroke = hex("#120D1F"),
	TextPrimary = hex("#FFF6E0"),
	TextMuted = hex("#BDB0D6"),
	Gold = hex("#FFC83D"),
	GoldDark = hex("#B8860B"),
	TextOnGold = hex("#2A1A00"),
	Accent = hex("#6C5CE7"),
	Success = hex("#4ADE80"),
	Danger = hex("#FF5C5C"),
	Warning = hex("#FFA94D"),
	Disabled = hex("#5A4F73"),
	DisabledText = hex("#A99EC2"),
	DangerText = hex("#1E0A0A"),

	-- Rarity accents (always paired with the rarity name, never colour alone).
	Rarity = RarityColors.Accent,

	TextSize = { Title = 32, Heading = 24, Button = 22, Number = 26, Body = 18, Caption = 14 },
	CornerPanel = UDim.new(0, 16),
	CornerButton = UDim.new(0, 12),
	CornerPill = UDim.new(1, 0),
}

Theme.HeadingFont = Font.fromEnum(Enum.Font.FredokaOne)
-- One family everywhere (owner request): hierarchy comes from size, not from a second font.
Theme.BodyFont = Theme.HeadingFont

return Theme
