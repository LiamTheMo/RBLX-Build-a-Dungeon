-- Profile mutations for loot and progression (GDD "Loot, rarity and
-- progression"). Pure and non-yielding: callers pass the live profile and an
-- RNG (Random.new() on the server, seeded in specs), then call
-- ProfileService.Changed. Each returns (ok, dataOrReason) like a remote handler.
-- Context()/Table() give the reward math that Defeat() applies, so the drop
-- tables the player sees are the ones that are rolled.

local Balance = require(script.Parent.Parent.Definitions.Balance)
local Rooms = require(script.Parent.Parent.Definitions.Rooms)
local Economy = require(script.Parent.Economy)
local Events = require(script.Parent.Events)
local Loot = require(script.Parent.Loot)
local Progression = require(script.Parent.Progression)
local RoomInventory = require(script.Parent.RoomInventory)
local Threat = require(script.Parent.Threat)

local Rewards = {}

local function isDefender(roomId: string): boolean
	local def = Rooms.Get(roomId)
	return def ~= nil and def.Kind == "Defender"
end

-- Adds one box. At the stack cap the box converts to banked coins instead of
-- being lost; returns true when it was converted (callers send "Box storage full").
local function addBox(profile, boxType: string): boolean
	local held = profile.Boxes[boxType] or 0
	if held >= Balance.Loot.MaxStack then
		profile.Coins += Balance.Loot.BoxOverflowCoins[boxType] or 0
		return true
	end
	profile.Boxes[boxType] = held + 1
	return false
end

local function addBlueprints(profile, roomId: string, n: number)
	profile.Blueprints[roomId] = math.min(Balance.Loot.MaxStack, (profile.Blueprints[roomId] or 0) + n)
end

-- Adds XP and grants one box per level gained. Returns (newLevel?, levelDrops).
function Rewards.GrantXp(profile, amount: number)
	local level, xp, gained = Progression.AddXp(profile.Level, profile.Xp, amount)
	profile.Level, profile.Xp = level, xp
	local drops = {}
	for _, reached in gained do
		local boxType = Progression.LevelReward(reached)
		local overflow = addBox(profile, boxType)
		table.insert(drops, { Kind = "Box", Type = boxType, Source = "LevelUp", Overflow = overflow or nil })
	end
	return if #gained > 0 then level else nil, drops
end

-- Everything a visitor's rewards depend on right now: {Threat, Scale (threat
-- multipliers), Bonuses (capped), Effects (event), EventId, VariantMult}.
-- `eventId` is the active event (or nil); `unlockAll` the admin threat override.
function Rewards.Context(profile, eventId: string?, unlockAll: boolean?)
	local tier = Progression.ActiveThreat(profile, unlockAll)
	local effects = Events.Effects(eventId)
	return {
		Threat = tier,
		Scale = Threat.Scale(tier),
		Bonuses = Progression.Bonuses(profile),
		Effects = effects,
		EventId = if Events.Get(eventId) then eventId else nil,
		VariantMult = Threat.VariantMultiplier(Progression.VaultBonus(profile), effects.Variants, Progression.VariantBonus(profile)),
	}
end

function Rewards.CoinMultiplier(ctx, variantId: string?): number
	local v = Threat.Variant(variantId)
	return Economy.CoinMultiplier({
		ThreatCoins = ctx.Scale.Coins,
		VariantCoins = v and v.Coins,
		CoinBonus = ctx.Bonuses.Coins,
		EventCoins = ctx.Effects.Coins,
	})
end

-- Drop-chance multiplier besides the loot bonus: threat * variant * event.
function Rewards.DropScale(ctx, variantId: string?): number
	local v = Threat.Variant(variantId)
	return ctx.Scale.Drops * (v and v.Drops or 1) * ctx.Effects.Drops
end

-- Effective coin range {Min, Max} for a visitor (nil if unknown).
function Rewards.CoinRange(visitorId: string, ctx, variantId: string?)
	local min, max = Economy.RewardRange(visitorId)
	if min == nil or max == nil then
		return nil
	end
	local m = Rewards.CoinMultiplier(ctx, variantId)
	return { Min = Economy.WinPayout(min, m), Max = Economy.WinPayout(max, m) }
end

-- The player's drop table for a normal (non-variant) visitor: {Coins = {Min, Max},
-- Xp, Drops = Loot.DropTable(...), Variants = {{Id, Chance, Coins = {Min, Max},
-- Drops = multiplier, GuaranteedBox?}}}.
function Rewards.Table(profile, visitorId: string, ctx)
	local variants = {}
	for _, v in Threat.VariantChances(visitorId, ctx.VariantMult) do
		local def = Threat.Variant(v.Id)
		table.insert(variants, {
			Id = v.Id,
			Chance = v.Chance,
			Coins = Rewards.CoinRange(visitorId, ctx, v.Id),
			Drops = def.Drops,
			GuaranteedBox = def.GuaranteedBox,
		})
	end
	return {
		Coins = Rewards.CoinRange(visitorId, ctx),
		Xp = Progression.XpFor(visitorId, ctx.Bonuses.Xp, ctx.Scale.Xp),
		Drops = Loot.DropTable(visitorId, ctx.Bonuses.Loot, Rewards.DropScale(ctx), profile.Level),
		Variants = variants,
	}
end

-- A defeated visitor: coins (base rolled at spawn, times the multipliers) go
-- straight to Coins; drop rolls (loot bonus, threat, variant, event) plus a
-- variant's guaranteed box; XP (threat, XP bonus). Call exactly once per
-- encounter, in the step that pays out. Returns {Amount, Drops = {{Kind, Type?,
-- RoomId?, Source, Overflow?, Guaranteed?}}, Xp, LevelUp = level?}.
-- Overflow = true: the box stack was full and it was converted to coins.
function Rewards.Defeat(profile, visitorId: string, rng, ctx, base: number, variantId: string?)
	local amount = Economy.WinPayout(base, Rewards.CoinMultiplier(ctx, variantId))
	profile.Coins += amount
	local drops = Loot.RollDrops(visitorId, ctx.Bonuses.Loot, rng, profile.Level, Rewards.DropScale(ctx, variantId))
	local v = Threat.Variant(variantId)
	if v and v.GuaranteedBox then
		table.insert(drops, { Kind = "Box", Type = v.GuaranteedBox, Guaranteed = true })
	end
	for _, drop in drops do
		drop.Source = "Visitor"
		if drop.Kind == "Box" then
			drop.Overflow = addBox(profile, drop.Type) or nil
		elseif drop.RoomId then
			addBlueprints(profile, drop.RoomId, 1)
		end
	end
	local xp = Progression.XpFor(visitorId, ctx.Bonuses.Xp, ctx.Scale.Xp)
	local levelUp, levelDrops = Rewards.GrantXp(profile, xp)
	table.move(levelDrops, 1, #levelDrops, #drops + 1, drops)
	return { Amount = amount, Drops = drops, Xp = xp, LevelUp = levelUp }
end

-- Admin grant: `n` boxes (each one past the stack cap converts to coins).
-- Returns how many were converted.
function Rewards.GiveBoxes(profile, boxType: string, n: number): number
	local converted = 0
	for _ = 1, n do
		if addBox(profile, boxType) then
			converted += 1
		end
	end
	return converted
end

-- Opens one box: a rolled tier (pity applies), then a room of that tier (gated
-- for Common/Uncommon). The room's rarity and perks are its definition's.
-- During an event the tier weights may be boosted (Events.BoxTiers) and the
-- room may get a modifier. A full inventory leaves the box unopened.
-- Returns {InstanceId, RoomId, Rarity, Perks (copy of the definition's), Modifier?}.
function Rewards.OpenBox(profile, boxType: string, rng, eventId: string?)
	if Loot.Odds(boxType, 0, profile.Level) == nil then
		return false, "BadArgs"
	end
	if (profile.Boxes[boxType] or 0) < 1 then
		return false, "NoBox"
	end
	if RoomInventory.Count(profile) >= RoomInventory.MAX_ROOMS then
		return false, "TooManyRooms"
	end
	-- Same pity-adjusted, gate-filtered (and event-boosted) lists the odds show.
	local rarity, roomId = Loot.RollBox(boxType, profile.BoxPity, rng, profile.Level, Events.BoxTiers(Events.Effects(eventId)))
	if rarity == nil or roomId == nil then
		return false, "BadArgs"
	end
	local modifier = Events.RollModifier(eventId, rng)
	profile.Boxes[boxType] -= 1
	profile.BoxPity = Loot.NextPity(profile.BoxPity, rarity)
	local instanceId = RoomInventory.Add(profile, roomId, modifier)
	local perks = {}
	for i, perk in (Rooms.Get(roomId) :: any).Perks do
		perks[i] = { Kind = perk.Kind, Amount = perk.Amount }
	end
	return true, { InstanceId = instanceId, RoomId = roomId, Rarity = rarity, Perks = perks, Modifier = modifier }
end

-- The tier's CraftCost blueprints of a type -> one room of that type.
function Rewards.Craft(profile, roomId: string)
	local cost = Loot.CraftCost(roomId)
	if cost == nil then
		return false, "NotCraftable"
	end
	if (profile.Blueprints[roomId] or 0) < cost then
		return false, "NotEnoughBlueprints"
	end
	if RoomInventory.Count(profile) >= RoomInventory.MAX_ROOMS then
		return false, "TooManyRooms"
	end
	local left = profile.Blueprints[roomId] - cost
	profile.Blueprints[roomId] = if left > 0 then left else nil
	return true, RoomInventory.Add(profile, roomId)
end

-- Scraps an unplaced room instance (any level; not the starter Coin Cache) for
-- its tier's ScrapReturn blueprints of its type. Returns the new blueprint count.
function Rewards.Scrap(profile, instanceId: string)
	local room = profile.Rooms[instanceId]
	if room == nil then
		return false, "NotOwned"
	end
	if not Loot.Craftable(room.Id) then
		return false, "NotScrappable"
	end
	if RoomInventory.IsPlaced(profile, instanceId) then
		return false, "RoomPlaced"
	end
	if (profile.Blueprints[room.Id] or 0) >= Balance.Loot.MaxStack then
		return false, "BlueprintsFull"
	end
	if isDefender(room.Id) then
		local others = 0
		for id, other in profile.Rooms do
			if id ~= instanceId and isDefender(other.Id) then
				others += 1
			end
		end
		if others == 0 then
			return false, "LastDefender"
		end
	end
	profile.Rooms[instanceId] = nil
	addBlueprints(profile, room.Id, Loot.ScrapReturn(room.Id) :: number)
	return true, profile.Blueprints[room.Id]
end

-- Buys the next level of a permanent upgrade with banked coins.
function Rewards.BuyPermanent(profile, upgradeId: string)
	local def = Balance.Permanent[upgradeId]
	if type(def) ~= "table" or def.Base == nil then
		return false, "UnknownUpgrade"
	end
	local level = profile.Permanent[upgradeId] or 0
	local cost = Progression.PermanentCost(upgradeId, level)
	if cost == nil then
		return false, "MaxLevel"
	end
	if profile.Coins < cost then
		return false, "NotEnoughCoins"
	end
	profile.Coins -= cost
	profile.Permanent[upgradeId] = level + 1
	return true, level + 1
end

return Rewards
