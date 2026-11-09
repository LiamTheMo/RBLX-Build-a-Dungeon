-- Drop table of a visitor: coin range, XP, every possible drop (icon + %) and the rare-variant chances.
-- Numbers come from State.DropTables (the server's effective values: threat, loot bonus, event); the
-- Catalog only supplies names. Used by the Collection tab (compact chips) and the drop-card popup (bands).
local Badges = require(script.Parent.Badges)
local Catalog = require(script.Parent.Catalog)
local Kit = require(script.Parent.Kit)
local P = require(script.Parent.PanelsKit)
local Sprites = require(script.Parent.Sprites)
local SpriteIds = require(script.Parent.SpriteIds)
local Theme = require(script.Parent.Theme)

local make = Kit.Make
local X = Enum.AutomaticSize.X

local DropCard = {}

local BAND = {
	Dungeon = Color3.fromRGB(124, 88, 62),
	Rare = Color3.fromRGB(52, 96, 178),
	Blueprint = Color3.fromRGB(58, 74, 150),
}

local function roomName(id: string): string
	local def = Catalog.Room(id)
	return def and def.DisplayName or P.Spaced(id)
end

local function boxName(boxType: any): string
	return if boxType == "Crystal" then "Crystal Chest" elseif boxType == "Rare" then "Royal Chest" else "Dungeon Chest"
end

local function boxIcon(boxType: any): string
	return if boxType == "Crystal" then "CrystalBox" elseif boxType == "Rare" then "RareBox" else "Box"
end

local function hrow(parent: Instance, padding: number, props: { [string]: any }?): Frame
	local f = make("Frame", props or { BackgroundTransparency = 1 }, parent)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, padding), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	return f
end

-- A tinted band: leading art, chance icon and percent.
local function band(parent: Instance, order: number, color: Color3, art: (Instance) -> GuiObject, chance: number, tip: string)
	local f = make("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 48), LayoutOrder = order, Active = true, Image = "" }, parent)
	Kit.Skin(f, Kit.Spec("Chip.Dark"), "Uniform", nil, nil)
	local _ = color -- the tier colour shows in the chance text, the plate is the dark chip
	make("UIPadding", { PaddingLeft = UDim.new(0, 26), PaddingRight = UDim.new(0, 30) }, f)
	local left = hrow(f, 6, { BackgroundTransparency = 1, Size = UDim2.new(0.5, 0, 1, 0) })
	art(left).LayoutOrder = 1
	local right = hrow(f, 8, { BackgroundTransparency = 1, Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.5, 1) })
	Kit.Icon(right, "DropChance", UDim2.fromOffset(30, 30)).LayoutOrder = 1
	local l = Kit.Label(right, P.Pct(chance), Theme.TextSize.Number - 2, Theme.TextPrimary, true)
	l.AutomaticSize, l.Size, l.TextWrapped, l.LayoutOrder = X, UDim2.fromOffset(0, 40), false, 2
	Kit.Stroke(l, Theme.Stroke, 2)
	Kit.Tip(f, tip)
	return f
end

local function statChip(parent: Instance, order: number, icon: string, text: string, tip: string)
	local c = Kit.Panel(parent, { Sprite = "Pill", AutomaticSize = X, Size = UDim2.fromOffset(0, 36), LayoutOrder = order, Active = true })
	local row = hrow(c, 6, { BackgroundTransparency = 1, AutomaticSize = X, Size = UDim2.fromScale(0, 1) })
	make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, row)
	Kit.Icon(row, icon, UDim2.fromOffset(26, 26)).LayoutOrder = 1
	local l = Kit.Label(row, text, Theme.TextSize.Body, Theme.TextPrimary, true)
	l.AutomaticSize, l.Size, l.TextWrapped, l.LayoutOrder = X, UDim2.fromOffset(0, 30), false, 2
	Kit.Tip(c, tip)
	return c
end

-- The table for a visitor (State first, else the catalog's base values).
local function tableFor(state: any, visitorId: string): any?
	local t = state and state.DropTables and state.DropTables[visitorId]
	if t then
		return t
	end
	local def = Catalog.Visitor(visitorId)
	if def and def.Reward then
		return { Coins = { Min = def.Reward.Min, Max = def.Reward.Max }, Xp = def.Xp or 0, Drops = def.Drops or {}, Variants = {} }
	end
	return nil
end

-- Fills `parent` (which must hold a vertical UIListLayout sorted by LayoutOrder) with the card.
-- full = bands (popup); otherwise compact chips (Collection entries).
function DropCard.Fill(parent: Instance, visitorId: string, state: any, full: boolean, order: number?)
	local t = tableFor(state, visitorId)
	if not t then
		return
	end
	local base = order or 0
	local boxes, blueprints = {}, {}
	for _, d in t.Drops or {} do
		table.insert(if d.Kind == "Blueprint" then blueprints else boxes, d)
	end
	local blueprintTotal = 0
	for _, d in blueprints do
		blueprintTotal += d.Chance or 0
	end

	if not full then
		local flow = P.ChipFlow(parent, base + 1)
		P.Chip(flow, 1, function(p)
			return Kit.Icon(p, "CoinRange", UDim2.fromOffset(24, 24))
		end, Badges.Range(t.Coins), Theme.Gold, "Coins")
		P.Chip(flow, 2, function(p)
			return Kit.Icon(p, "Xp", UDim2.fromOffset(24, 24))
		end, tostring(t.Xp or 0), Theme.TextPrimary, "XP")
		local n = 2
		for _, d in boxes do
			n += 1
			P.Chip(flow, n, function(p)
				return Kit.Icon(p, boxIcon(d.Type), UDim2.fromOffset(24, 24))
			end, P.Pct(d.Chance or 0), Theme.TextPrimary, boxName(d.Type))
		end
		if #blueprints > 0 then
			n += 1
			P.Chip(flow, n, function(p)
				return Kit.Icon(p, "Blueprint", UDim2.fromOffset(24, 24))
			end, P.Pct(blueprintTotal), Theme.TextPrimary, "Blueprint")
		end
		local variants = t.Variants or {}
		if #variants > 0 then
			local vf = P.ChipFlow(parent, base + 2)
			for i, v in variants do
				P.Chip(vf, i, function(p)
					return Badges.Variant(p, v.Id, 22) or Kit.Icon(p, "Check", UDim2.fromOffset(22, 22))
				end, P.Pct(v.Chance or 0), Badges.VariantTint[v.Id] or Theme.TextPrimary, tostring(v.Id))
			end
		end
		return
	end

	local head = hrow(parent, 10, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 56), LayoutOrder = base + 1 })
	local pid = SpriteIds.Portraits[visitorId]
	if Sprites.Ok(pid) then
		make("ImageLabel", { BackgroundTransparency = 1, Image = pid, Size = UDim2.fromOffset(52, 52), ScaleType = Enum.ScaleType.Fit, LayoutOrder = 1 }, head)
	else
		Kit.Icon(head, "Visitor", UDim2.fromOffset(46, 46)).LayoutOrder = 1
	end
	statChip(head, 2, "CoinRange", Badges.Range(t.Coins), "Coins")
	statChip(head, 3, "Xp", tostring(t.Xp or 0), "XP")
	local order2 = base + 1
	for _, d in boxes do
		order2 += 1
		band(parent, order2, BAND[d.Type] or BAND.Dungeon, function(p)
			return Kit.Icon(p, boxIcon(d.Type), UDim2.fromOffset(34, 34))
		end, d.Chance or 0, boxName(d.Type))
	end
	if #blueprints > 0 then
		order2 += 1
		band(parent, order2, BAND.Blueprint, function(p)
			return Kit.Icon(p, "Blueprint", UDim2.fromOffset(34, 34))
		end, blueprintTotal, "Blueprint")
		order2 += 1
		local rooms = P.ChipFlow(parent, order2)
		for i, d in blueprints do
			P.Chip(rooms, i, function(p)
				return P.RoomImage(p, d.RoomId, 26)
			end, P.Pct(d.Chance or 0), Theme.TextMuted, roomName(d.RoomId), Theme.Rarity[d.Rarity or Catalog.RoomRarity(d.RoomId)], d.Rarity or Catalog.RoomRarity(d.RoomId))
		end
	end
	for _, v in t.Variants or {} do
		order2 += 1
		local row = Kit.Panel(parent, { Sprite = "Row", Size = UDim2.new(1, 0, 0, 56), LayoutOrder = order2, Active = true })
		local cells = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, row)
		local function at(obj, x)
			obj.AnchorPoint, obj.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(x, 0.5)
		end
		local badge = Badges.Variant(cells, v.Id, 36)
		if badge then at(badge, 0.10) end
		at(Kit.Icon(cells, "DropChance", UDim2.fromOffset(26, 26)), 0.25)
		local chance = Kit.Label(cells, P.Pct(v.Chance or 0), Theme.TextSize.Body, Theme.TextPrimary, true)
		chance.Size, chance.TextWrapped = UDim2.new(0.15, 0, 0, 36), false
		at(chance, 0.35)
		at(Kit.Icon(cells, "CoinRange", UDim2.fromOffset(26, 26)), 0.48)
		local coins = Kit.Label(cells, Badges.Range(v.Coins), Theme.TextSize.Body, Theme.Gold, true)
		coins.Size, coins.TextWrapped = UDim2.new(0.22, 0, 0, 36), false
		coins.TextScaled = true
		make("UITextSizeConstraint", { MinTextSize = 11, MaxTextSize = Theme.TextSize.Body }, coins)
		at(coins, 0.64)
		if v.GuaranteedBox then
			at(Kit.Icon(cells, boxIcon(v.GuaranteedBox), UDim2.fromOffset(30, 30)), 0.82)
			at(Kit.Icon(cells, "Check", UDim2.fromOffset(16, 16), Theme.Success), 0.92)
		end
		Kit.Tip(row, tostring(v.Id) .. (if v.GuaranteedBox then " - guaranteed " .. boxName(v.GuaranteedBox) else ""))
	end
end

return DropCard
