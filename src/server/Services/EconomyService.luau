-- SetVaultPercent, Buy, Upgrade, BuyPermanent. Every mutation reads and writes the profile without
-- yielding, so each request is atomic; the client never supplies a price.

local Balance = require(script.Parent.Parent.Definitions.Balance)
local Rooms = require(script.Parent.Parent.Definitions.Rooms)
local Economy = require(script.Parent.Parent.Rules.Economy)
local Progression = require(script.Parent.Parent.Rules.Progression)
local Net = require(script.Parent.Parent.Infrastructure.Net)
local Rewards = require(script.Parent.Parent.Rules.Rewards)
local RoomInventory = require(script.Parent.Parent.Rules.RoomInventory)
local PlotService = require(script.Parent.PlotService)
local ProfileService = require(script.Parent.ProfileService)
local TutorialService = require(script.Parent.TutorialService)

local EconomyService = {}

local function oneString(...)
	local value = ...
	return select("#", ...) == 1 and type(value) == "string" and #value >= 1 and #value <= 32
end

-- SetVaultPercent: the share of Coins kept in the vault (at risk while a Treasure
-- Room is placed; raises the spawn-rate bonus). Whole number 0..100, any time
-- except during an encounter, so a theft cannot be dodged at the last second.
function EconomyService.SetVaultPercent(player: Player, percent: number)
	local profile = ProfileService.Get(player)
	if profile == nil then
		return false, "ProfileNotLoaded"
	end
	local plot = PlotService.GetPlot(player)
	if plot and plot:GetAttribute("State") == "Encounter" then
		return false, "EncounterActive"
	end
	if profile.VaultPercent ~= percent then
		profile.VaultPercent = percent
		ProfileService.Changed(player)
	end
	TutorialService.Notify(player, "VaultSet")
	return true, percent
end

function EconomyService.Buy(player: Player, roomId: string)
	local profile = ProfileService.Get(player)
	if profile == nil then
		return false, "ProfileNotLoaded"
	end
	local def = Rooms.Get(roomId)
	if def == nil then
		return false, "UnknownRoom"
	end
	local stats = Balance.Rooms[roomId]
	-- Only Common and Uncommon rooms are sold (rarer rooms are box/blueprint-only).
	local sellable = def.Rarity == "Common" or def.Rarity == "Uncommon"
	if def.Source ~= "Shop" or not sellable or stats == nil or type(stats.Cost) ~= "number" then
		return false, "NotForSale"
	end
	if profile.Level < Progression.ShopLevel(roomId) then
		return false, "LevelLocked"
	end
	if profile.Coins < stats.Cost then
		return false, "NotEnoughCoins"
	end
	if RoomInventory.Count(profile) >= RoomInventory.MAX_ROOMS then
		return false, "TooManyRooms"
	end
	if not RoomInventory.CanAdd(profile, 1) then return false, "RoomIdsExhausted" end
	profile.Coins -= stats.Cost
	local instanceId = RoomInventory.Add(profile, roomId)
	ProfileService.Changed(player)
	Net.Fire("Notice", player, { Text = `Bought a {def.DisplayName}.`, Kind = "Good" })
	TutorialService.Notify(player, "Bought")
	return true, instanceId
end

function EconomyService.Upgrade(player: Player, instanceId: string)
	local profile = ProfileService.Get(player)
	if profile == nil then
		return false, "ProfileNotLoaded"
	end
	local plot = PlotService.GetPlot(player)
	if plot and plot:GetAttribute("State") == "Encounter" then
		return false, "EncounterActive"
	end
	local instance = profile.Rooms[instanceId]
	if instance == nil then
		return false, "NotOwned"
	end
	local def = Rooms.Get(instance.Id)
	local cost = if def and def.Upgradable then Economy.UpgradeCost(instance.Level, def.Rarity) else nil
	if cost == nil then
		return false, "MaxLevel"
	end
	if profile.Coins < cost then
		return false, "NotEnoughCoins"
	end
	profile.Coins -= cost
	instance.Level += 1
	PlotService.RefreshRoomAttrs(player)
	ProfileService.Changed(player)
	return true, instance.Level
end

function EconomyService.BuyPermanent(player: Player, upgradeId: string)
	local profile = ProfileService.Get(player)
	if profile == nil then
		return false, "ProfileNotLoaded"
	end
	local ok, result = Rewards.BuyPermanent(profile, upgradeId)
	if not ok then
		return false, result
	end
	if upgradeId == "StoutDefenders" then
		PlotService.RefreshRoomAttrs(player)
	end
	ProfileService.Changed(player)
	return true, result
end

function EconomyService.Init()
	Net.Handle("SetVaultPercent", function(...)
		local percent = ...
		return select("#", ...) == 1 and type(percent) == "number" and percent % 1 == 0 and percent >= 0 and percent <= 100
	end, EconomyService.SetVaultPercent)
	Net.Handle("Buy", oneString, EconomyService.Buy)
	Net.Handle("Upgrade", oneString, EconomyService.Upgrade)
	Net.Handle("BuyPermanent", oneString, EconomyService.BuyPermanent)
end

return EconomyService
