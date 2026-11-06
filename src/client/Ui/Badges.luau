-- Small reusable badges: threat tier shields, rare-variant nameplates, room modifier chips and a few
-- number formatters. Sprites come from SpriteIds3 through Kit.Icon / Sprites (drawn fallbacks if a
-- sprite is missing or fails to load). Display only.
local Catalog = require(script.Parent.Catalog)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local make = Kit.Make

local Badges = {}

-- Sprite aspect ratios (width / height) of the variant nameplates.
local VARIANT_ASPECT = { Elite = 512 / 272, Shiny = 512 / 339, Gilded = 512 / 281 }
Badges.VariantTint = { Elite = Color3.fromRGB(255, 80, 80), Shiny = Color3.fromRGB(90, 210, 255), Gilded = Color3.fromRGB(255, 200, 61) }
Badges.ModifierColor = { Blazing = Theme.Warning, Lucky = Theme.Success, Golden = Theme.Gold }

-- 1,250 style number.
function Badges.Comma(n: number): string
	local s = tostring(math.floor(n + 0.5))
	local out = s
	repeat
		s = out
		out = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
	until out == s
	return out
end

-- Multiplier text: x1.5, x2, x1.25 (no trailing zeros).
function Badges.Mult(x: number): string
	local v = math.floor(x * 100 + 0.5) / 100
	return "x" .. (if v % 1 == 0 then tostring(math.floor(v)) else tostring(v))
end

-- Coin range text, "18-26" ("18" when equal).
function Badges.Range(r: any): string
	if type(r) ~= "table" then
		return "0"
	end
	if r.Min == r.Max then
		return Badges.Comma(r.Min or 0)
	end
	return Badges.Comma(r.Min or 0) .. "-" .. Badges.Comma(r.Max or 0)
end

-- Threat tier shield (T1..T6) at a square size.
function Badges.Tier(parent: Instance, tier: number, size: UDim2): any
	return Kit.Icon(parent, "T" .. tostring(math.clamp(math.floor(tier), 1, 6)), size)
end

-- Variant nameplate ("Elite" / "Shiny" / "Gilded"), `height` px tall, width from the sprite's aspect.
-- Returns nil for an unknown id.
function Badges.Variant(parent: Instance, id: any, height: number): any
	local aspect = VARIANT_ASPECT[id]
	if not aspect then
		return nil
	end
	local img = Kit.Icon(parent, id, UDim2.fromOffset(math.floor(height * aspect), height))
	if img:IsA("TextLabel") then -- drawn fallback: a tinted word
		img.TextColor3 = Badges.VariantTint[id]
	end
	return img
end

-- Room modifier chip: round, tinted by modifier, effect icon inside; name and text on hover.
function Badges.Modifier(parent: Instance, id: any, size: number): any
	local color = Badges.ModifierColor[id]
	if not color then
		return nil
	end
	local text = tostring(id)
	for _, m in if Catalog.Current then Catalog.Current.Modifiers or {} else {} do
		if m.Id == id then
			text = m.Name .. ": " .. m.Text
		end
	end
	-- ModifierRing sprite with the modifier's own icon (ModBlazing / ModLucky / ModGolden) inside.
	local chip = Kit.Icon(parent, "ModifierRing", UDim2.fromOffset(size, size))
	chip.Name, chip.Active = "Modifier", true
	local ic = Kit.Icon(chip, "Mod" .. tostring(id), UDim2.fromScale(0.62, 0.62))
	ic.AnchorPoint, ic.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
	Kit.Tip(chip, text)
	return chip
end

return Badges
