-- Server events (Balance.Events): at most one at a time, started by the automatic
-- schedule or an admin (/event start). Replicated through Workspace attributes
-- ActiveEvent ("" when none) and EventEndsAt (workspace:GetServerTimeNow() time,
-- 0 when none), a ServerEvent broadcast {Kind = "Start" | "End", Id, EndsAt?}
-- and a Notice to everyone. Rules read the effects through Effects()/ActiveId().
-- The schedule: a random event MinGap..MaxGap seconds after the previous one
-- ended (or the server started); off in Studio unless Balance.Events.RunInStudio.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MemoryStoreService = game:GetService("MemoryStoreService")

local Balance = require(script.Parent.Parent.Definitions.Balance)
local Events = require(script.Parent.Parent.Rules.Events)
local Net = require(script.Parent.Parent.Infrastructure.Net)
local ProfileService = require(script.Parent.ProfileService)

local EventService = {}

local rng = Random.new()
local active = nil -- { Id, EndsAt } or nil
local nextAutoAt = nil -- server time of the next automatic event; nil while one runs or when off
local scheduled = not RunService:IsStudio() or Balance.Events.RunInStudio
local globalEvents = MemoryStoreService:GetSortedMap("AdminGlobalEventsV1")
local globalRevision = 0

function EventService.ActiveId(): string?
	return active and active.Id
end

function EventService.Effects()
	return Events.Effects(active and active.Id)
end

-- {Id, EndsAt} of the running event, or nil.
function EventService.Active()
	return if active then { Id = active.Id, EndsAt = active.EndsAt } else nil
end

-- Every player's State depends on the event (drop tables, box odds, XP, variant chance).
local function refreshAll()
	for _, player in Players:GetPlayers() do
		ProfileService.Changed(player)
	end
end

local function replicate()
	workspace:SetAttribute("ActiveEvent", if active then active.Id else "")
	workspace:SetAttribute("EventEndsAt", if active then active.EndsAt else 0)
end

-- Starts `id` for `seconds` (default Duration), replacing a running event.
-- Returns (true, endsAt) or (false, "UnknownEvent").
function EventService.Begin(id: string, seconds: number?)
	local def = Events.Get(id)
	if def == nil then
		return false, "UnknownEvent"
	end
	active = { Id = id, EndsAt = workspace:GetServerTimeNow() + (seconds or Balance.Events.Duration) }
	nextAutoAt = nil
	replicate()
	Net.FireAll("ServerEvent", { Kind = "Start", Id = id, EndsAt = active.EndsAt })
	Net.FireAll("Notice", { Text = `{def.Name}! {def.Text}`, Kind = "Good" })
	refreshAll()
	return true, active.EndsAt
end

-- Ends the running event; false if none.
function EventService.End(): boolean
	if active == nil then
		return false
	end
	local def = Events.Get(active.Id)
	active = nil
	if scheduled then
		nextAutoAt = workspace:GetServerTimeNow() + Events.NextGap(rng)
	end
	replicate()
	Net.FireAll("ServerEvent", { Kind = "End", Id = def.Id })
	Net.FireAll("Notice", { Text = `{def.Name} has ended.`, Kind = "Info" })
	refreshAll()
	return true
end

-- A shared, expiring command lets active and newly started servers converge even
-- if one server temporarily cannot reach the memory store.
local function applyGlobal(command)
	if type(command) ~= "table" or type(command.Revision) ~= "number" or command.Revision <= globalRevision then return end
	globalRevision = command.Revision
	if command.Id == "" then
		EventService.End()
	elseif type(command.Id) == "string" and type(command.EndsAt) == "number" and Events.Get(command.Id) then
		local remaining = command.EndsAt - os.time()
		if remaining > 0 then EventService.Begin(command.Id, remaining) end
	end
end

function EventService.Global(id: string?, seconds: number?)
	if id and (not Events.Get(id) or type(seconds) ~= "number" or seconds <= 0 or seconds > Balance.Events.MaxAdminMinutes * 60) then
		return false, "Invalid event or duration"
	end
	local ok, command = pcall(function()
		return globalEvents:UpdateAsync("current", function(previous)
			return { Revision = math.max(os.time() * 1000, (if type(previous) == "table" and type(previous.Revision) == "number" then previous.Revision else 0) + 1),
				Id = id or "", EndsAt = os.time() + (seconds or 0) }
		end, Balance.Events.MaxAdminMinutes * 60 + 300)
	end)
	if not ok then return false, "Global event service unavailable; try again" end
	applyGlobal(command)
	return true, if id then "Global event started; other servers will update shortly." else "Global event stopped; other servers will update shortly."
end

function EventService.Init()
	replicate()
end

function EventService.Start()
	task.spawn(function()
		while true do
			local ok, command = pcall(function() return globalEvents:GetAsync("current") end)
			if ok then applyGlobal(command) else warn("[EventService] Global event sync failed: " .. tostring(command)) end
			task.wait(15)
		end
	end)
	if scheduled then
		nextAutoAt = workspace:GetServerTimeNow() + Events.NextGap(rng)
	end
	task.spawn(function()
		while true do
			task.wait(1)
			local now = workspace:GetServerTimeNow()
			local ok, err = pcall(function()
				if active and now >= active.EndsAt then
					EventService.End()
				elseif active == nil and nextAutoAt and now >= nextAutoAt then
					EventService.Begin(Events.RollEvent(rng))
				end
			end)
			if not ok then
				warn("[EventService] " .. tostring(err))
			end
		end
	end)
end

return EventService
