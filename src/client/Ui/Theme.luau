-- Design tokens from docs/UI_SPEC.md. Sizes are reference px (before UIScale).
local function hex(s: string): Color3
	return Color3.fromHex(s)
end

local RarityColors = require(script.Parent.RarityColors)

local Theme = {
	BgDeep = hex("#2E1A5C"), -- deep well
	BgPanel = hex("#2E1A5C"),
	BgRaised = hex("#7B3FD0"), -- kit purple
	Stroke = hex("#1A0F2E"), -- outline
	TextPrimary = hex("#FFF6E0"),
	TextMuted = hex("#BDB0D6"),
	Gold = hex("#FFC21A"),
	GoldDark = hex("#E59400"),
	TextOnGold = hex("#2A1A00"),
	Accent = hex("#7B3FD0"),
	Success = hex("#4ADE80"),
	Danger = hex("#FF5C5C"),
	Warning = hex("#FFA94D"),
	Disabled = hex("#5A4F73"),
	DisabledText = hex("#A99EC2"),
	DangerText = hex("#1E0A0A"),

	-- Rarity accents (always paired with the rarity name, never colour alone).
	Rarity = RarityColors.Accent,

	TextSize = { Title = 36, Heading = 28, Button = 26, Number = 30, Body = 23, Caption = 18, Label = 18, Tiny = 16 },
	CornerPanel = UDim.new(0, 16),
	CornerButton = UDim.new(0, 12),
	CornerPill = UDim.new(1, 0),
}

Theme.HeadingFont = Font.fromEnum(Enum.Font.FredokaOne)
-- One family everywhere (owner request): hierarchy comes from size, not from a second font.
Theme.BodyFont = Theme.HeadingFont

return Theme
