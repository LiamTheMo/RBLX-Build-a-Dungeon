--!strict
-- Look of each rarity tier (client presentation), keyed by the rarity Id the
-- server sends (Catalog.Rarities, from the server's Balance.Rarities). Adding a
-- tier needs one line here for its colour; an id missing here renders as
-- Common. Fill = badge/frame colour. Accent = colour for text, strokes and 3D
-- glows on dark backgrounds (defaults to Fill). Shimmer = animated prismatic
-- edge (static under reduced motion). Sparkle = particles on a placed room.
local TIERS: { [string]: { Fill: string, Accent: string?, Shimmer: boolean?, Sparkle: boolean? } } = {
	Common = { Fill = "#B0B7C3" },
	Uncommon = { Fill = "#4ADE80" },
	Rare = { Fill = "#4DA3FF" },
	Epic = { Fill = "#B36BFF" },
	Legendary = { Fill = "#FFB020" },
	Mythic = { Fill = "#FF4FD8", Sparkle = true },
	Secret = { Fill = "#1A1A1A", Accent = "#F4F0FF", Shimmer = true, Sparkle = true },
}

local fill: { [string]: Color3 } = {}
local accent: { [string]: Color3 } = {}
local shimmer: { [string]: boolean } = {}
local sparkle: { [string]: boolean } = {}
for id, t in TIERS do
	fill[id] = Color3.fromHex(t.Fill)
	accent[id] = Color3.fromHex(t.Accent or t.Fill)
	shimmer[id] = t.Shimmer == true
	sparkle[id] = t.Sparkle == true
end

return table.freeze({
	Fill = table.freeze(fill),
	Accent = table.freeze(accent),
	Shimmer = table.freeze(shimmer),
	Sparkle = table.freeze(sparkle),
})
