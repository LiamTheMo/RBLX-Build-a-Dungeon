-- Server events (Balance.Events): at most one at a time, started by the automatic
-- schedule or an admin (/event start). Replicated through Workspace attributes
-- ActiveEvent ("" when none) and EventEndsAt (workspace:GetServerTimeNow() time,
-- 0 when none), a ServerEvent broadcast {Kind = "Start" | "End", Id, EndsAt?}
-- and a Notice to everyone. Rules read the effects through Effects()/ActiveId().
-- The schedule: a random event MinGap..MaxGap seconds after the previous one
-- ended (or the server started); off in Studio unless Balance.Events.RunInStudio.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Balance = require(script.Parent.Parent.Definitions.Balance)
local Events = require(script.Parent.Parent.Rules.Events)
local Net = require(script.Parent.Parent.Infrastructure.Net)
local ProfileService = require(script.Parent.ProfileService)

local EventService = {}

local rng = Random.new()
local active = nil -- { Id, EndsAt } or nil
local nextAutoAt = nil -- server time of the next automatic event; nil while one runs or when off
local scheduled = not RunService:IsStudio() or Balance.Events.RunInStudio

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

-- Every player's State depends on the event (drop tables, box odds, interval).
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

function EventService.Init()
	replicate()
end

function EventService.Start()
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
