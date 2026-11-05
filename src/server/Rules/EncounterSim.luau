--!strict
-- Deterministic encounter simulation (docs/PHASE0.md, "Encounter rules"). Pure:
-- no Instances, no clocks. EncounterService steps it and applies the payout in
-- the step that sets Result. Room i (1-based) is centred i * CellSize studs from
-- the entrance centre; the visitor walks the route and stops to duel defenders.

local Shared = game:GetService("ReplicatedStorage").Shared
local Grid = require(Shared.Definitions.Grid)
local Rooms = require(Shared.Definitions.Rooms)
local Balance = require(Shared.Definitions.Balance)
local Visitors = require(Shared.Definitions.Visitors)

local SUBSTEP = 0.05 -- seconds; keeps big dt values from skipping strikes
local EPS = 1e-9

-- levels/rarities are per route index (default 1 / "Common"); a level is capped
-- by its rarity. healthBonus (Stout Defenders) adds to every defender's health.
export type Config = {
	route: { string },
	levels: { number }?,
	rarities: { string }?,
	healthBonus: number?,
	visitorId: string,
}

local EncounterSim = {}
EncounterSim.__index = EncounterSim

local function rarityOf(name: string?): any
	local r = Balance.Rarities[name or "Common"]
	return if type(r) == "table" and r.StatMultiplier then r else Balance.Rarities.Common
end

-- (levelsAbove1, statMultiplier) for a room at `level` of `rarity`.
local function scaling(level: number?, rarity: string?): (number, number)
	local r = rarityOf(rarity)
	local lv = if type(level) == "number" and level == level then math.clamp(math.floor(level), 1, r.MaxLevel) else 1
	return lv - 1, r.StatMultiplier
end

-- A defender's max health before any Monster Den boost; nil if `roomId` has no defender.
function EncounterSim.DefenderHealth(roomId: string, level: number?, rarity: string?, healthBonus: number?): number?
	local stats = Balance.Rooms[roomId]
	if stats == nil or stats.DefenderHealth == nil then
		return nil
	end
	local above, mult = scaling(level, rarity)
	return stats.DefenderHealth * (1 + above * Balance.Upgrades.HealthBonusPerLevel) * mult * (1 + math.max(0, healthBonus or 0))
end

function EncounterSim.new(config: Config): any
	local visitor = assert(Balance.Visitors[config.visitorId], "unknown visitor")
	local self: any = setmetatable({}, EncounterSim)
	self.Route = config.route
	self.Stats = visitor
	self.Time = 0
	self.Progress = 0
	self.MaxHealth = visitor.Health
	self.Health = visitor.Health
	self.Result = nil -- "Defeated" | "Escaped" | "Robbed" once decided
	self.Slowed = false
	self.Fighting = 0 -- route index of the room being duelled, or 0
	self.Defenders = {} -- [route index] = {Health, MaxHealth, Down, NextAttack, Damage, Stats}
	self._slowUntil = 0
	self._slowFraction = 0
	self._visitorNext = 0
	self._started = false
	self._traps = {} -- [route index] = {Next, Damage, Stats}
	self._caverns = {} -- [route index] = {Duration, Bonus} of a Mushroom Cavern not yet entered
	self._dens = {} -- [route index] = {Damage, Health} boost of a Monster Den
	self._sporedUntil = 0
	self.Spored = false
	self._pending = {} -- events for the first Step, after Spawn
	local def = Visitors.Get(config.visitorId)
	self._sureFooted = def ~= nil and table.find(def.Traits, "SureFooted") ~= nil
	self._mender = if def ~= nil and table.find(def.Traits, "Mender") then (visitor.HealPerSecond or 0) else 0

	local up = Balance.Upgrades
	for i, roomId in config.route do
		local def = Rooms.Get(roomId)
		local stats = Balance.Rooms[roomId]
		local level, rarity = config.levels and config.levels[i], config.rarities and config.rarities[i]
		local above, mult = scaling(level, rarity)
		local damageScale = (1 + above * up.DamageBonusPerLevel) * mult
		if def and def.Kind == "Defender" and stats then
			local health = EncounterSim.DefenderHealth(roomId, level, rarity, config.healthBonus) :: number
			self.Defenders[i] = {
				Health = health,
				MaxHealth = health,
				Down = false,
				Boosted = false,
				Risen = false,
				NextAttack = 0,
				Damage = stats.AttackDamage * damageScale,
				Stats = stats,
			}
		elseif def and def.Kind == "Trap" and stats and stats.SporeDuration then
			local bonus = (stats.TrapDamageBonus + above * (stats.TrapDamageBonusPerLevel or 0)) * mult
			self._caverns[i] = { Duration = stats.SporeDuration, Bonus = bonus }
		elseif def and def.Kind == "Support" and stats and stats.DamageBonus then
			local per = above * (stats.BonusPerLevel or 0)
			self._dens[i] = { Damage = (stats.DamageBonus + per) * mult, Health = (stats.HealthBonus + per) * mult }
		elseif def and def.Kind == "Trap" and stats then
			self._traps[i] = { Next = stats.Telegraph, Damage = stats.Damage * damageScale, Stats = stats }
		end
	end

	-- Monster Den: each Defender next to a Den on the route gets one boost, from
	-- the strongest adjacent Den (the earlier one on a tie).
	for j = 1, #config.route do
		local d = self.Defenders[j]
		local best, at = nil, 0
		for _, i in { j - 1, j + 1 } do
			local den = self._dens[i]
			if den and (best == nil or den.Damage + den.Health > best.Damage + best.Health) then
				best, at = den, i
			end
		end
		if d and best then
			d.Boosted = true
			d.Damage *= 1 + best.Damage
			d.MaxHealth *= 1 + best.Health
			d.Health = d.MaxHealth
			table.insert(self._pending, { Kind = "DenBoost", Index = j, Den = at })
		end
	end
	return self
end

local function span(index: number): (number, number)
	return (index - 0.5) * Grid.CellSize, (index + 0.5) * Grid.CellSize
end

-- Nearest defender ahead that is still standing, else the end of the route.
local function nextStop(self: any): (number, number)
	for i = 1, #self.Route do
		local d = self.Defenders[i]
		if d and not d.Down then
			return i * Grid.CellSize, i
		end
	end
	return #self.Route * Grid.CellSize, 0
end

local function substep(self: any, h: number, events: { any })
	local t0 = self.Time
	local t1 = t0 + h
	local stats = self.Stats
	local atEnd = false

	-- Movement (stopped while duelling).
	if self.Fighting == 0 then
		if self._mender > 0 then
			self.Health = math.min(self.MaxHealth, self.Health + self._mender * h)
		end
		local slowed = t0 < self._slowUntil and not self._sureFooted
		local speed = stats.WalkSpeed * (if slowed then 1 - self._slowFraction else 1)
		local stop, index = nextStop(self)
		local need = math.max(0, stop - self.Progress) / speed
		if need <= h + EPS then
			self.Progress = stop
			if index == 0 then
				atEnd = true
			else
				local d = self.Defenders[index]
				self.Fighting = index
				self._visitorNext = t0 + need
				d.NextAttack = t0 + need
			end
		else
			self.Progress += speed * h
		end
	end

	-- Entering a Mushroom Cavern spores the visitor.
	for i, cavern in self._caverns do
		if self.Progress >= span(i) - EPS then
			self._caverns[i] = nil
			self._sporedUntil = t1 + cavern.Duration
			self._sporeBonus = cavern.Bonus
			table.insert(events, { Kind = "Spored", Index = i })
		end
	end

	-- Trap strikes in this window hit whoever stands on the trap's cell.
	for i = 1, #self.Route do
		local trap = self._traps[i]
		while trap and trap.Next <= t1 + EPS and self.Health > 0 do
			local lo, hi = span(i)
			local hit = self.Progress >= lo - EPS and self.Progress <= hi + EPS
			local spored = trap.Next < self._sporedUntil
			if hit then
				self.Health -= trap.Damage * (if spored then 1 + self._sporeBonus else 1)
			end
			table.insert(events, { Kind = "Trap", Index = i, Hit = hit, Spored = hit and spored })
			trap.Next += trap.Stats.Cycle
		end
	end

	-- Duel: both sides strike on their own intervals; simultaneous hits both land.
	while self.Fighting > 0 and self.Health > 0 do
		local index = self.Fighting
		local d = self.Defenders[index]
		local tNext = math.min(self._visitorNext, d.NextAttack)
		if tNext > t1 + EPS then
			break
		end
		local visitorActs = self._visitorNext <= tNext + EPS
		local defenderActs = d.NextAttack <= tNext + EPS
		if visitorActs then
			d.Health -= stats.AttackDamage
			self._visitorNext += stats.AttackInterval
			table.insert(events, { Kind = "Attack", By = "Visitor", Index = index, Damage = stats.AttackDamage })
		end
		if defenderActs then
			self.Health -= d.Damage
			d.NextAttack += d.Stats.AttackInterval
			table.insert(events, { Kind = "Attack", By = "Defender", Index = index, Damage = d.Damage })
			if d.Stats.SlowFraction and not self._sureFooted then
				self._slowUntil = tNext + d.Stats.SlowDuration
				self._slowFraction = d.Stats.SlowFraction
				table.insert(events, { Kind = "Slow", Index = index })
			end
		end
		if d.Health <= 0 and d.Stats.ReviveFraction and not d.Risen then
			d.Risen = true
			d.Health = d.MaxHealth * d.Stats.ReviveFraction
			table.insert(events, { Kind = "Rise", Index = index })
		elseif d.Health <= 0 then
			d.Health = 0
			d.Down = true
			self.Fighting = 0
			table.insert(events, { Kind = "DefenderDown", Index = index })
		end
	end

	self.Time = t1
	self.Slowed = t1 < self._slowUntil
	self.Spored = t1 < self._sporedUntil
	if self.Health <= 0 then
		self.Health = 0
		self.Result = "Defeated"
	elseif atEnd then
		local last = Rooms.Get(self.Route[#self.Route] or "")
		self.Result = if last and last.Kind == "Treasure" then "Robbed" else "Escaped"
	end
end

function EncounterSim.Step(self: any, dt: number): { any }
	local events = {}
	if self.Result ~= nil or not (dt > 0) and self._started then
		return events
	end
	if not self._started then
		self._started = true
		table.insert(events, { Kind = "Spawn" })
		for _, e in self._pending do
			table.insert(events, e)
		end
		self._pending = {}
	end
	local remaining = if dt > 0 then dt else 0
	repeat
		local h = math.min(SUBSTEP, remaining)
		substep(self, h, events)
		remaining -= h
	until self.Result ~= nil or remaining <= 0
	if self.Result ~= nil then
		table.insert(events, { Kind = "End", Result = self.Result })
	end
	return events
end

return EncounterSim
