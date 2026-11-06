--!strict
-- Admin authorization and chat-command parsing (AdminService). Pure: the group
-- rank is looked up by the service and passed in.

local Balance = require(script.Parent.Parent.Definitions.Balance)

local Admin = {}

Admin.MAX_COINS = 1e9
Admin.MAX_BOXES = 999
Admin.MAX_XP = 1e6

-- True if `userId` is listed in `config.UserIds` or `rank` (in config.GroupId) is
-- at least config.MinRank. Anything malformed is not an admin.
function Admin.IsAdmin(userId: any, config: any, rank: any): boolean
	if type(userId) ~= "number" or type(config) ~= "table" then
		return false
	end
	if table.find(config.UserIds or {}, userId) then
		return true
	end
	return type(rank) == "number" and type(config.MinRank) == "number" and rank >= config.MinRank
end

-- A whole number in [1, max], else nil.
local function count(word: string?, max: number): number?
	local n = tonumber(word)
	if n == nil or n % 1 ~= 0 or n < 1 or n > max then
		return nil
	end
	return n
end

local function eventId(word: string?): string?
	for _, e in Balance.Events.List do
		if word and string.lower(word) == string.lower(e.Id) then
			return e.Id
		end
	end
	return nil
end

-- Parses one chat message. Returns a command table or (nil, usage):
--   /event start <id> [minutes]  -> {Action = "EventStart", Event, Minutes?}
--   /event stop | /event list     -> {Action = "EventStop" | "EventList"}
--   /give coins <n> [player]      -> {Action = "GiveCoins", Amount, Target?}
--   /give box <Dungeon|Rare> <n> [player] -> {Action = "GiveBox", Box, Amount, Target?}
--   /give xp <n> [player]         -> {Action = "GiveXp", Amount, Target?}
--   /threat unlockall [player]    -> {Action = "UnlockThreat", Target?}
function Admin.Parse(text: any): (any, string?)
	if type(text) ~= "string" or #text > 200 then
		return nil, "Too long."
	end
	local w = {}
	for word in string.gmatch(text, "%S+") do
		table.insert(w, word)
	end
	local cmd, sub = string.lower(w[1] or ""), string.lower(w[2] or "")
	if cmd == "/event" then
		if sub == "start" then
			local id = eventId(w[3])
			local minutes = if w[4] then count(w[4], Balance.Events.MaxAdminMinutes) else nil
			if id and (w[4] == nil or minutes) and #w <= 4 then
				return { Action = "EventStart", Event = id, Minutes = minutes }
			end
			return nil, `Usage: /event start <id> [1-{Balance.Events.MaxAdminMinutes} minutes]`
		elseif sub == "stop" and #w == 2 then
			return { Action = "EventStop" }
		elseif sub == "list" and #w == 2 then
			return { Action = "EventList" }
		end
		return nil, "Usage: /event start <id> [minutes] | /event stop | /event list"
	elseif cmd == "/give" then
		if sub == "coins" or sub == "xp" then
			local amount = count(w[3], if sub == "coins" then Admin.MAX_COINS else Admin.MAX_XP)
			if amount and #w <= 4 then
				return { Action = if sub == "coins" then "GiveCoins" else "GiveXp", Amount = amount, Target = w[4] }
			end
		elseif sub == "box" then
			local box = string.lower(w[3] or "")
			local amount = count(w[4], Admin.MAX_BOXES)
			if (box == "dungeon" or box == "rare") and amount and #w <= 5 then
				return { Action = "GiveBox", Box = if box == "rare" then "Rare" else "Dungeon", Amount = amount, Target = w[5] }
			end
		end
		return nil, "Usage: /give coins <n> [player] | /give box <Dungeon|Rare> <n> [player] | /give xp <n> [player]"
	elseif cmd == "/threat" then
		if sub == "unlockall" and #w <= 3 then
			return { Action = "UnlockThreat", Target = w[3] }
		end
		return nil, "Usage: /threat unlockall [player]"
	end
	return nil, "Unknown command."
end

-- Event ids for /event list.
function Admin.EventIds(): { string }
	local out = {}
	for _, e in Balance.Events.List do
		table.insert(out, e.Id)
	end
	return out
end

return table.freeze(Admin)
