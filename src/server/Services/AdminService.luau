-- Admin chat commands through TextChatService TextChatCommands created and handled
-- on the server (Triggered fires on the server for server-created commands). The
-- admin check (Config/Admins: listed UserId or group rank, cached per player) is
-- server-only; non-admins get no response. Every admin action is logged with the
-- admin's UserId. Syntax: Rules/Admin.Parse.

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local Admins = require(script.Parent.Parent.Config.Admins)
local Admin = require(script.Parent.Parent.Rules.Admin)
local ProfileSchema = require(script.Parent.Parent.Rules.ProfileSchema)
local Rewards = require(script.Parent.Parent.Rules.Rewards)
local Net = require(script.Parent.Parent.Infrastructure.Net)
local EventService = require(script.Parent.EventService)
local PlotService = require(script.Parent.PlotService)
local ProfileService = require(script.Parent.ProfileService)

local AdminService = {}

local ALIASES = { "/event", "/give", "/threat" }
local cache = {} -- Player -> boolean

function AdminService.IsAdmin(player: Player): boolean
	if cache[player] == nil then
		local ok, rank = pcall(player.GetRankInGroup, player, Admins.GroupId)
		local result = Admin.IsAdmin(player.UserId, Admins, if ok then rank else nil)
		if not ok then
			return result -- lookup failed: do not cache a negative, try again next time
		end
		cache[player] = result
	end
	return cache[player]
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
	local matches = {}
	for _, p in Players:GetPlayers() do
		if string.lower(p.Name) == lower or string.lower(p.DisplayName) == lower then
			return p
		elseif string.sub(string.lower(p.Name), 1, #lower) == lower then
			table.insert(matches, p)
		end
	end
	return if #matches == 1 then matches[1] else nil
end

local function run(admin: Player, cmd): (boolean, string)
	if cmd.Action == "EventStart" then
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
	Players.PlayerAdded:Connect(function(player)
		task.spawn(AdminService.IsAdmin, player) -- warm the cache
	end)
	Players.PlayerRemoving:Connect(function(player)
		cache[player] = nil
	end)
end

return AdminService
