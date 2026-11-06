--!strict
-- Deterministic encounter simulation (docs/PHASE0.md, "Encounter rules"). Pure:
-- no Instances, no clocks. EncounterService steps it and applies the payout in
-- the step that sets Result. Room i (1-based) is centred i * CellSize studs from
-- the entrance centre; the visitor walks the route and stops to duel defenders.
--
-- Room behaviour comes from the room definition and Balance.Rooms (2026-11-05
-- item model: no per-instance rarity multiplier; only the level and an event
-- modifier scale a room). Mechanics:
--   Defender   stops the visitor and duels it. Units fight one after another
--              (Goblin Barracks, Lich Sanctum); Ambush strikes on arrival
--              (Mimic); ReviveFraction rises once (Restless Crypt); Burn sets
--              the visitor on fire (Dragon Lair); Revives (Phoenix Nest) brings
--              the first knocked-out route defender back at full health.
--   Strike trap hits whoever is in its room every Cycle seconds (Spike Hall,
--              Arrow Gallery; Flame Vent also burns).
--   Zone trap  ZoneDamage per second while inside (Frost Chamber also chills
--              the next room and slows; Void Gate sends the visitor back once).
--   Spore      Mushroom Cavern: more damage from trap strikes and zones.
--   Den        Monster Den boosts adjacent route defenders.
-- Statuses: Slow (Slime; Frost while chilled; the strongest applies; Sure-footed
-- visitors ignore slows), Burn (ticks; blocks Mender healing), Chilled, Spored.

local Definitions = script.Parent.Parent.Definitions
local Grid = require(Definitions.Grid)
local Rooms = require(Definitions.Rooms)
local Balance = require(Definitions.Balance)
local Visitors = require(Definitions.Visitors)
local Events = require(script.Parent.Events)

local SUBSTEP = 0.05 -- seconds; keeps big dt values from skipping strikes
local EPS = 1e-9

-- levels/modifiers are per route index (default 1 / none); a level is capped by
-- the room definition's rarity. healthBonus (Stout Defenders) adds to every
-- defender's health. visitorHealth/visitorDamage multiply the visitor's stats
-- (threat tier and variant; default 1). A "Damage" modifier (Blazing) scales
-- that room's defender, trap, zone and burn damage.
export type Config = {
	route: { string },
	levels: { number }?,
	modifiers: { string }?,
	healthBonus: number?,
	visitorId: string,
	visitorHealth: number?,
	visitorDamage: number?,
}

local EncounterSim = {}
EncounterSim.__index = EncounterSim

-- Levels above 1 for `roomId` at `level`, capped by its definition's tier.
local function levelsAbove(roomId: string, level: number?): number
	local tier = Balance.RarityById[Rooms.Rarity(roomId)] or Balance.RarityById.Common
	local lv = if type(level) == "number" and level == level then math.clamp(math.floor(level), 1, tier.MaxLevel) else 1
	return lv - 1
end

-- The ordered units of a defender room (single defenders are one unit).
local function unitsOf(stats: any): { any }
	if stats.Units then
		return stats.Units
	end
	return { { Name = "", Health = stats.DefenderHealth, Damage = stats.AttackDamage, Interval = stats.AttackInterval } }
end

-- Max health of a defender room's first unit before any Monster Den boost; nil
-- if `roomId` has no defender.
function EncounterSim.DefenderHealth(roomId: string, level: number?, healthBonus: number?): number?
	local stats = Balance.Rooms[roomId]
	local def = Rooms.Get(roomId)
	if stats == nil or def == nil or def.Kind ~= "Defender" then
		return nil
	end
	local above = levelsAbove(roomId, level)
	return unitsOf(stats)[1].Health * (1 + above * Balance.Upgrades.HealthBonusPerLevel) * (1 + math.max(0, healthBonus or 0))
end

-- Makes unit `n` the active one.
local function setUnit(d: any, n: number)
	local u = d.Units[n]
	d.Unit = n
	d.Health = u.Health
	d.MaxHealth = u.Health
	d.Damage = u.Damage
	d.Interval = u.Interval
	d.Name = u.Name
end

function EncounterSim.new(config: Config): any
	local visitor = assert(Balance.Visitors[config.visitorId], "unknown visitor")
	local self: any = setmetatable({}, EncounterSim)
	self.Route = config.route
	self.Stats = visitor
	self.Time = 0
	self.Progress = 0
	self.MaxHealth = visitor.Health * (config.visitorHealth or 1)
	self.Health = self.MaxHealth
	self._damage = visitor.AttackDamage * (config.visitorDamage or 1)
	self.Result = nil -- "Defeated" | "Escaped" | "Robbed" once decided
	self.Slowed = false
	self.Spored = false
	self.Burning = false
	self.Chilled = false
	self.Fighting = 0 -- route index of the room being duelled, or 0
	-- [route index] = {Health, MaxHealth, Down, Unit, Units, Name, NextAttack, Damage, Interval, Stats, ...}
	self.Defenders = {}
	self._slowUntil = 0
	self._slowFraction = 0
	self._visitorNext = 0
	self._started = false
	self._traps = {} -- [route index] = {Next, Damage, Cycle, Burn?} strike traps
	self._zones = {} -- [route index] = {Damage, Slow, Next (chills the next room), Void, Used}
	self._caverns = {} -- [route index] = {Duration, Bonus} of a Mushroom Cavern not yet entered
	self._dens = {} -- [route index] = {Damage, Health} boost of a Monster Den
	self._revives = {} -- route indices of Phoenix Nests, one entry per revive charge
	self._sporedUntil = 0
	self._sporeBonus = 0
	self._burnUntil = 0
	self._burnDps = 0
	self._burnTick = 0
	self._burnFrom = 0
	self._pending = {} -- events for the first Step, after Spawn
	local vdef = Visitors.Get(config.visitorId)
	self._sureFooted = vdef ~= nil and table.find(vdef.Traits, "SureFooted") ~= nil
	self._mender = if vdef ~= nil and table.find(vdef.Traits, "Mender") then (visitor.HealPerSecond or 0) else 0

	local up = Balance.Upgrades
	for i, roomId in config.route do
		local def = Rooms.Get(roomId)
		local stats: any = Balance.Rooms[roomId]
		if def == nil or stats == nil then
			continue
		end
		local level = config.levels and config.levels[i]
		local above = levelsAbove(roomId, level)
		local mod = Events.Modifier(config.modifiers and config.modifiers[i])
		local damageScale = (1 + above * up.DamageBonusPerLevel) * (if mod and mod.Effect == "Damage" then 1 + mod.Amount else 1)
		local healthScale = (1 + above * up.HealthBonusPerLevel) * (1 + math.max(0, config.healthBonus or 0))
		if def.Kind == "Defender" then
			local units = {}
			for n, u in unitsOf(stats) do
				units[n] = { Name = u.Name, Health = u.Health * healthScale, Damage = u.Damage * damageScale, Interval = u.Interval }
			end
			local d = {
				Units = units,
				Down = false,
				Boosted = false,
				Risen = false,
				Engaged = false,
				NextAttack = 0,
				Stats = stats,
				Ambush = if stats.AmbushDamage then stats.AmbushDamage * damageScale else nil,
				BurnDps = if stats.Burn then Balance.Status.Burn.DamagePerSecond * damageScale else nil,
			}
			setUnit(d, 1)
			self.Defenders[i] = d
			for _ = 1, stats.Revives or 0 do
				table.insert(self._revives, i)
			end
		elseif stats.SporeDuration then
			local bonus = stats.TrapDamageBonus + above * (stats.TrapDamageBonusPerLevel or 0)
			self._caverns[i] = { Duration = stats.SporeDuration, Bonus = bonus }
		elseif stats.DamageBonus then
			local per = above * (stats.BonusPerLevel or 0)
			self._dens[i] = { Damage = stats.DamageBonus + per, Health = stats.HealthBonus + per }
		elseif stats.ZoneDamage then
			self._zones[i] = {
				Damage = stats.ZoneDamage * damageScale,
				Slow = stats.SlowFraction,
				Next = stats.ChillsNextRoom == true,
				Void = stats.SendsBack == true,
				Used = false,
			}
		elseif stats.Cycle then
			self._traps[i] = {
				Next = stats.Telegraph,
				Damage = stats.Damage * damageScale,
				Cycle = stats.Cycle,
				Burn = if stats.Burn then Balance.Status.Burn.DamagePerSecond * damageScale else nil,
			}
		end
	end

	-- Monster Den: each Defender next to a Den on the route gets one boost, from
	-- the strongest adjacent Den (the earlier one on a tie); every unit is boosted.
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
			for _, u in d.Units do
				u.Damage *= 1 + best.Damage
				u.Health *= 1 + best.Health
			end
			setUnit(d, 1)
			table.insert(self._pending, { Kind = "DenBoost", Index = j, Den = at })
		end
	end
	return self
end

local function span(index: number): (number, number)
	return (index - 0.5) * Grid.CellSize, (index + 0.5) * Grid.CellSize
end

local function inRoom(self: any, index: number): boolean
	local lo, hi = span(index)
	return self.Progress >= lo - EPS and self.Progress <= hi + EPS
end

-- The next place the visitor must stop: (position, kind, route index). Kinds:
-- "Defender" (a standing defender), "Void" (an unused Void Gate centre), "End".
local function nextStop(self: any): (number, string, number)
	for i = 1, #self.Route do
		local d = self.Defenders[i]
		if d and not d.Down then
			return i * Grid.CellSize, "Defender", i
		end
		local z = self._zones[i]
		if z and z.Void and not z.Used then
			return i * Grid.CellSize, "Void", i
		end
	end
	return #self.Route * Grid.CellSize, "End", 0
end

-- Trap damage multiplier from spores at time `t`.
local function sporeMult(self: any, t: number): number
	return if t < self._sporedUntil then 1 + self._sporeBonus else 1
end

-- Sets the visitor burning (refresh the duration, keep the stronger damage).
local function ignite(self: any, t: number, dps: number, from: number)
	local burn = Balance.Status.Burn
	if t >= self._burnUntil then
		self._burnTick = t + burn.Tick
		self._burnDps = dps
	else
		self._burnDps = math.max(self._burnDps, dps)
	end
	self._burnFrom = from
	self._burnUntil = math.max(self._burnUntil, t + burn.Duration)
end

-- Chill zone covering the visitor now: (slow fraction, damage per second, zone index).
local function chill(self: any): (number, number, number)
	local slow, dps, at = 0, 0, 0
	for i, z in self._zones do
		if not z.Void and (inRoom(self, i) or (z.Next and i < #self.Route and inRoom(self, i + 1))) then
			slow = math.max(slow, z.Slow or 0)
			dps += z.Damage
			at = if at == 0 then i else at
		end
	end
	return slow, dps, at
end

-- A defender's health reached 0: next unit, Crypt rise, Phoenix revive or down.
local function knockedOut(self: any, index: number, events: { any })
	local d = self.Defenders[index]
	if d.Unit < #d.Units then
		setUnit(d, d.Unit + 1)
		d.NextAttack = self._now + d.Interval * 0.5 -- the next unit needs a moment to step in
		table.insert(events, { Kind = "Unit", Index = index, Unit = d.Unit, Name = d.Name })
	elseif d.Stats.ReviveFraction and not d.Risen then
		d.Risen = true
		d.Health = d.MaxHealth * d.Stats.ReviveFraction
		table.insert(events, { Kind = "Rise", Index = index })
	elseif #self._revives > 0 then
		local by = table.remove(self._revives, 1)
		d.Health = d.MaxHealth
		table.insert(events, { Kind = "Revive", Index = index, By = by })
	else
		d.Health = 0
		d.Down = true
		self.Fighting = 0
		table.insert(events, { Kind = "DefenderDown", Index = index })
	end
end

local function substep(self: any, h: number, events: { any })
	local t0 = self.Time
	local t1 = t0 + h
	self._now = t0
	local stats = self.Stats
	local atEnd = false

	-- Movement (stopped while duelling). Slows: the strongest of the Slime slow
	-- and a chill zone; Sure-footed visitors ignore both.
	local chillSlow, chillDps, chillAt = chill(self)
	if self.Fighting == 0 then
		if self._mender > 0 and t0 >= self._burnUntil then
			self.Health = math.min(self.MaxHealth, self.Health + self._mender * h)
		end
		local slow = math.max(if t0 < self._slowUntil then self._slowFraction else 0, chillSlow)
		local speed = stats.WalkSpeed * (if self._sureFooted then 1 else 1 - slow)
		local stop, kind, index = nextStop(self)
		local need = math.max(0, stop - self.Progress) / speed
		if need <= h + EPS then
			self.Progress = stop
			local at = t0 + need
			if kind == "End" then
				atEnd = true
			elseif kind == "Void" then
				local z = self._zones[index]
				z.Used = true
				self.Progress = 0
				table.insert(events, { Kind = "Void", Index = index })
			else
				local d = self.Defenders[index]
				self.Fighting = index
				self._visitorNext = at
				d.NextAttack = at
				if not d.Engaged then
					d.Engaged = true
					if d.Stats.Summon then
						table.insert(events, { Kind = "Summon", Index = index, Name = d.Name })
					end
					if d.Ambush then
						self.Health -= d.Ambush
						d.NextAttack = at + d.Interval
						table.insert(events, { Kind = "Ambush", Index = index, Damage = d.Ambush })
					end
				end
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

	-- Strike traps in this window hit whoever stands in the trap's room.
	for i = 1, #self.Route do
		local trap = self._traps[i]
		while trap and trap.Next <= t1 + EPS and self.Health > 0 do
			local hit = inRoom(self, i)
			local spored = trap.Next < self._sporedUntil
			if hit then
				self.Health -= trap.Damage * sporeMult(self, trap.Next)
				if trap.Burn then
					ignite(self, trap.Next, trap.Burn, i)
				end
			end
			table.insert(events, { Kind = "Trap", Index = i, Hit = hit, Spored = hit and spored, Burn = (hit and trap.Burn ~= nil) or nil })
			trap.Next += trap.Cycle
		end
	end

	-- Zones: chill (this room and the next) and the void's own room.
	local chilled = chillAt ~= 0
	if chilled and not self.Chilled then
		table.insert(events, { Kind = "Chill", Index = chillAt })
	end
	self.Chilled = chilled
	local zoneDps = chillDps
	for i, z in self._zones do
		if z.Void and inRoom(self, i) then
			zoneDps += z.Damage
		end
	end
	if zoneDps > 0 then
		self.Health -= zoneDps * h * sporeMult(self, t0)
	end

	-- Burn ticks (not trap strikes: spores do not raise them).
	local tick = Balance.Status.Burn.Tick
	while self._burnTick <= t1 + EPS and self._burnTick <= self._burnUntil + EPS and self._burnDps > 0 and self.Health > 0 do
		local dmg = self._burnDps * tick
		self.Health -= dmg
		table.insert(events, { Kind = "Burn", Index = self._burnFrom, Damage = dmg })
		self._burnTick += tick
	end

	-- Duel: both sides strike on their own intervals; simultaneous hits both land.
	while self.Fighting > 0 and self.Health > 0 do
		local index = self.Fighting
		local d = self.Defenders[index]
		local tNext = math.min(self._visitorNext, d.NextAttack)
		if tNext > t1 + EPS then
			break
		end
		self._now = tNext
		local visitorActs = self._visitorNext <= tNext + EPS
		local defenderActs = d.NextAttack <= tNext + EPS
		if visitorActs then
			d.Health -= self._damage
			self._visitorNext += stats.AttackInterval
			table.insert(events, { Kind = "Attack", By = "Visitor", Index = index, Damage = self._damage })
		end
		if defenderActs then
			self.Health -= d.Damage
			d.NextAttack += d.Interval
			table.insert(events, { Kind = "Attack", By = "Defender", Index = index, Damage = d.Damage, Burn = d.BurnDps and true or nil })
			if d.BurnDps then
				ignite(self, tNext, d.BurnDps, index)
			end
			if d.Stats.SlowFraction and not self._sureFooted then
				self._slowUntil = tNext + d.Stats.SlowDuration
				self._slowFraction = d.Stats.SlowFraction
				table.insert(events, { Kind = "Slow", Index = index })
			end
		end
		if d.Health <= 0 then
			knockedOut(self, index, events)
		end
	end

	self.Time = t1
	local slowNow = math.max(if t1 < self._slowUntil then self._slowFraction else 0, (chill(self)))
	self.Slowed = slowNow > 0 and not self._sureFooted
	self.Spored = t1 < self._sporedUntil
	self.Burning = t1 < self._burnUntil
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
