-- Admin chat commands through TextChatService TextChatCommands created and handled
-- on the server (Triggered fires on the server for server-created commands). The
-- admin check (Config/Admins: listed UserId or group rank, cached per player) is
-- server-only; non-admins get no response. Every admin action is logged with the
-- admin's UserId. Syntax: Rules/Admin.Parse.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TextChatService = game:GetService("TextChatService")

local Admins = require(script.Parent.Parent.Config.Admins)
local Admin = require(script.Parent.Parent.Rules.Admin)
local Balance = require(script.Parent.Parent.Definitions.Balance)
local ProfileSchema = require(script.Parent.Parent.Rules.ProfileSchema)
local Rewards = require(script.Parent.Parent.Rules.Rewards)
local Net = require(script.Parent.Parent.Infrastructure.Net)
local EventService = require(script.Parent.EventService)
local PlotService = require(script.Parent.PlotService)
local ProfileService = require(script.Parent.ProfileService)
local BuildService = require(script.Parent.BuildService)
local EncounterService = require(script.Parent.EncounterService)

local AdminService = {}

local ALIASES = { "/event", "/give", "/threat" }
local resetTokens = {} -- admin -> {Token, UserId, Expires}

function AdminService.IsAdmin(player: Player): boolean
	if Admin.IsAdmin(player.UserId, Admins, nil) then return true end
	local ok, rank = pcall(player.GetRankInGroup, player, Admins.GroupId)
	return Admin.IsAdmin(player.UserId, Admins, if ok then rank else nil)
end

local function reply(player: Player, text: string, kind: string?)
	Net.Fire("Notice", player, { Text = text, Kind = kind or "Info" })
end

-- A player by exact name or display name, else a unique name prefix (case-insensitive).
local function findPlayer(name: string?, default: Player): Player?
	if name == nil then
		return default
	end
	local lower = string.lower(name)
	-- Usernames are unique. Display names and prefixes must identify exactly one player.
	for _, p in Players:GetPlayers() do
		if string.lower(p.Name) == lower then return p end
	end
	local exact, prefix = {}, {}
	for _, p in Players:GetPlayers() do
		if string.lower(p.DisplayName) == lower then table.insert(exact, p) end
		if string.sub(string.lower(p.Name), 1, #lower) == lower then table.insert(prefix, p) end
	end
	if #exact > 0 then return if #exact == 1 then exact[1] else nil end
	return if #prefix == 1 then prefix[1] else nil
end

local function run(admin: Player, cmd): (boolean, string)
	if (cmd.Action == "EventStart" or cmd.Action == "EventStop") and cmd.Scope == "Global" then
		return EventService.Global(cmd.Action == "EventStart" and cmd.Event or nil, cmd.Minutes and cmd.Minutes * 60)
	elseif cmd.Action == "EventStart" then
		local ok, result = EventService.Begin(cmd.Event, cmd.Minutes and cmd.Minutes * 60)
		return ok, if ok then `Started {cmd.Event}.` else tostring(result)
	elseif cmd.Action == "EventStop" then
		return true, if EventService.End() then "Event stopped." else "No event is running."
	elseif cmd.Action == "EventList" then
		local active = EventService.Active()
		local now = active and ` Active: {active.Id} ({math.ceil((active.EndsAt - workspace:GetServerTimeNow()) / 60)} min left).` or ""
		return true, "Events: " .. table.concat(Admin.EventIds(), ", ") .. "." .. now
	end
	local target = findPlayer(cmd.Target, admin)
	local profile = target and ProfileService.Get(target)
	if target == nil or profile == nil then
		return false, "Player not found or not loaded."
	end
	local what
	if cmd.Action == "GiveCoins" then
		profile.Coins = math.min(ProfileSchema.MAX_MONEY, profile.Coins + cmd.Amount)
		what = `{cmd.Amount} coins`
	elseif cmd.Action == "GiveBox" then
		local converted = Rewards.GiveBoxes(profile, cmd.Box, cmd.Amount)
		what = `{cmd.Amount} {cmd.Box} Box(es){if converted > 0 then ` ({converted} converted to coins)` else ""}`
	elseif cmd.Action == "GiveXp" then
		local level = Rewards.GrantXp(profile, cmd.Amount)
		what = `{cmd.Amount} XP{if level then ` (now level {level})` else ""}`
	elseif cmd.Action == "UnlockThreat" then
		ProfileService.SetTransient(target, "ThreatUnlockAll", true)
		what = "every threat level (this session)"
	else
		return false, "Unknown command."
	end
	ProfileService.Changed(target)
	PlotService.RefreshRoomAttrs(target)
	if target ~= admin then
		reply(target, `An admin gave you {what}.`, "Good")
	end
	return true, `Gave {target.Name} {what}.`
end

local function onCommand(source: TextSource, text: string)
	local admin = Players:GetPlayerByUserId(source.UserId)
	if admin == nil or not AdminService.IsAdmin(admin) then
		return -- non-admins get no response
	end
	local cmd, usage = Admin.Parse(text)
	if cmd == nil then
		reply(admin, usage or "Unknown command.", "Bad")
		return
	end
	local ok, result = run(admin, cmd)
	print(("[Admin] %s (UserId %d): %s -> %s"):format(admin.Name, admin.UserId, text, result))
	reply(admin, result, if ok then "Good" else "Bad")
end

function AdminService.Init()
	Net.HandleOpen("AdminAccess", function(...) return select("#", ...) == 0 end, function(player)
		if not AdminService.IsAdmin(player) then return false, "Unauthorized" end
		return true, { Events = Admin.EventIds(), MaxEventMinutes = Balance.Events.MaxAdminMinutes }
	end)
	Net.Handle("AdminResetToken", function(...)
		local name = ...
		return select("#", ...) == 1 and type(name) == "string" and #name > 0 and #name <= 32
	end, function(admin, name)
		if not AdminService.IsAdmin(admin) then return false, "Unauthorized" end
		local target = findPlayer(name, admin)
		if not target or not ProfileService.Get(target) then return false, "Player not found or not loaded" end
		local token = HttpService:GenerateGUID(false)
		resetTokens[admin] = { Token = token, UserId = target.UserId, Expires = os.clock() + 20 }
		return true, token
	end)
	Net.Handle("AdminAction", function(...)
		if select("#", ...) ~= 4 then return false end
		local action, target, value, confirmation = ...
		return type(action) == "string" and #action <= 20 and type(target) == "string" and #target > 0 and #target <= 32
			and type(value) == "number" and value == value and value >= 0 and value <= Admin.MAX_COINS and value % 1 == 0
			and type(confirmation) == "string" and #confirmation <= 40
	end, function(admin, action, targetName, value, confirmation)
		-- `admin` is supplied by Roblox's remote, never by the client. Its UserId
		-- is checked against server-only configuration for every action.
		if not AdminService.IsAdmin(admin) then return false, "Unauthorized" end
		if action == "EventStart" or action == "EventStop" then
			local command = Admin.PanelEvent(action, targetName, value, confirmation)
			if not command then return false, "Invalid event or duration" end
			local ok, result = run(admin, command)
			print(("[Admin] %s (%d) %s event=%s minutes=%s scope=%s -> %s"):format(admin.Name, admin.UserId, action, targetName, tostring(value), confirmation, result))
			return ok, result
		end
		if action == "GiveCoins" or action == "GiveXp" or action == "GiveDungeon" or action == "GiveRare" or action == "UnlockThreat" then
			if action ~= "UnlockThreat" and (value < 1 or value > (if action == "GiveCoins" then Admin.MAX_COINS elseif action == "GiveXp" then Admin.MAX_XP else Admin.MAX_BOXES)) then
				return false, "Amount out of range"
			end
			local cmd = { Action = if action == "GiveDungeon" or action == "GiveRare" then "GiveBox" else action, Target = targetName, Amount = value, Box = if action == "GiveRare" then "Rare" else "Dungeon" }
			local ok, result = run(admin, cmd)
			print(("[Admin] %s (%d) %s target=%s amount=%d -> %s"):format(admin.Name, admin.UserId, action, targetName, value, result))
			return ok, result
		end
		local target = findPlayer(targetName, admin)
		local profile = target and ProfileService.Get(target)
		if not target or not profile then return false, "Player not found or not loaded" end
		if action == "SetCoins" then
			profile.Coins = value
		elseif action == "ResetProfile" then
			local token = resetTokens[admin]
			resetTokens[admin] = nil -- consume before any validation, including a replay
			if not token or token.Token ~= confirmation or token.UserId ~= target.UserId or token.Expires < os.clock() then return false, "Reset confirmation expired" end
			if BuildService.IsBuilding(target) or EncounterService.InEncounter(target) then return false, "Player is building or in an encounter" end
			-- Keep persistence metadata and the existing table identity used by the store.
			local defaults = ProfileSchema.Default()
			for key, default in defaults do
				if key ~= "profileRevision" then profile[key] = default end
			end
			ProfileService.Changed(target)
			ProfileService.SetTransient(target, "ThreatUnlockAll", false)
			PlotService.Render(target)
			EncounterService.Reannounce(target)
		else
			return false, "Unknown action"
		end
		ProfileService.Changed(target)
		PlotService.RefreshRoomAttrs(target)
		print(("[Admin] %s (%d) %s target=%s (%d) value=%s"):format(admin.Name, admin.UserId, action, target.Name, target.UserId, tostring(value)))
		if target ~= admin then reply(target, "An admin updated your player data.", "Info") end
		return true, "Updated " .. target.Name
	end)
end

function AdminService.Start()
	local parent = TextChatService:FindFirstChild("TextChatCommands") or TextChatService
	for _, alias in ALIASES do
		local command = Instance.new("TextChatCommand")
		command.Name = "Admin" .. string.sub(alias, 2)
		command.PrimaryAlias = alias
		command.AutocompleteVisible = false
		command.Triggered:Connect(function(source, text)
			local ok, err = pcall(onCommand, source, text)
			if not ok then
				warn("[Admin] command failed: " .. tostring(err))
			end
		end)
		command.Parent = parent
	end
	Players.PlayerRemoving:Connect(function(player)
		resetTokens[player] = nil
	end)
end

return AdminService
