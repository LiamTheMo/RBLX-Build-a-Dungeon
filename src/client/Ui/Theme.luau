-- Design tokens from docs/UI_SPEC.md. Sizes are reference px (before UIScale).
local function hex(s: string): Color3
	return Color3.fromHex(s)
end

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
	Rarity = { Common = hex("#BDB0D6"), Uncommon = hex("#4ADE80"), Rare = hex("#4DA3FF"), Mythic = hex("#D58BFF") },

	TextSize = { Title = 32, Heading = 24, Button = 22, Number = 26, Body = 18, Caption = 14 },
	CornerPanel = UDim.new(0, 16),
	CornerButton = UDim.new(0, 12),
	CornerPill = UDim.new(1, 0),
}

local function font(family: string, weight: Enum.FontWeight?, fallback: Enum.Font): Font
	local ok, f = pcall(Font.fromName, family, weight or Enum.FontWeight.Regular)
	return if ok then f else Font.fromEnum(fallback)
end

Theme.HeadingFont = font("FredokaOne", Enum.FontWeight.Bold, Enum.Font.FredokaOne)
Theme.BodyFont = font("BuilderSans", Enum.FontWeight.Medium, Enum.Font.GothamMedium)

return Theme
