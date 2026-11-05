-- Bank, Buy, Upgrade, BuyPermanent. Every mutation reads and writes the profile without
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

function EconomyService.Bank(player: Player)
	local profile = ProfileService.Get(player)
	if profile == nil then
		return false, "ProfileNotLoaded"
	end
	local plot = PlotService.GetPlot(player)
	if plot and plot:GetAttribute("State") == "Encounter" then
		return false, "EncounterActive" -- no dodging a theft by banking at the last second
	end
	local amount = profile.Vault
	if amount <= 0 then
		return false, "NothingToBank"
	end
	profile.Coins += amount
	profile.Vault = 0
	ProfileService.Changed(player)
	Net.Fire("Notice", player, { Text = `Banked {amount} coins.`, Kind = "Good" })
	TutorialService.Notify(player, "Banked")
	return true, amount
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
	if def.Source ~= "Shop" or stats == nil or type(stats.Cost) ~= "number" then
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
	local cost = if def and def.Upgradable then Economy.UpgradeCost(instance.Level, instance.Rarity) else nil
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
	Net.Handle("Bank", function(...)
		return select("#", ...) == 0
	end, EconomyService.Bank)
	Net.Handle("Buy", oneString, EconomyService.Buy)
	Net.Handle("Upgrade", oneString, EconomyService.Upgrade)
	Net.Handle("BuyPermanent", oneString, EconomyService.BuyPermanent)
end

return EconomyService
