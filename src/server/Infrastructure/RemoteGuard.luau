-- Pure request guard behind Net (no Instances, so specs run it headless). Order:
-- rate limit -> argument check -> ready check -> handler. Every refusal is
-- (false, "ReasonCode"); the client is never trusted to be well-formed.

local RemoteGuard = {}
RemoteGuard.__index = RemoteGuard

RemoteGuard.RATE = 8 -- requests per second, per player and remote
RemoteGuard.BURST = 12
RemoteGuard.MAX_ARGS = 8

export type Options = {
	clock: () -> number,
	ready: ((any) -> boolean)?,
	rate: number?,
	burst: number?,
	warn: ((string) -> ())?,
}

function RemoteGuard.new(options: Options)
	return setmetatable({
		_clock = options.clock,
		_ready = options.ready,
		_rate = options.rate or RemoteGuard.RATE,
		_burst = options.burst or RemoteGuard.BURST,
		_warn = options.warn or warn,
		_buckets = {}, -- owner -> remote name -> { tokens, at }
	}, RemoteGuard)
end

function RemoteGuard:SetReady(ready: (any) -> boolean)
	self._ready = ready
end

-- Token bucket per owner and remote. False when over the limit.
function RemoteGuard:Take(owner: any, name: string): boolean
	local now = self._clock()
	local perOwner = self._buckets[owner]
	if perOwner == nil then
		perOwner = {}
		self._buckets[owner] = perOwner
	end
	local bucket = perOwner[name]
	if bucket == nil then
		bucket = { tokens = self._burst, at = now }
		perOwner[name] = bucket
	end
	bucket.tokens = math.min(self._burst, bucket.tokens + math.max(0, now - bucket.at) * self._rate)
	bucket.at = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

-- Drops a leaving player's buckets.
function RemoteGuard:Forget(owner: any)
	self._buckets[owner] = nil
end

local function run(self, owner: any, name: string, check: (...any) -> boolean, handler: (any, ...any) -> (boolean, any, any), needsReady: boolean, ...)
	if not self:Take(owner, name) then
		return false, "RateLimited"
	end
	local args = table.pack(...)
	if args.n > RemoteGuard.MAX_ARGS then
		return false, "BadArgs"
	end
	local checked, valid = pcall(check, ...)
	if not checked or valid ~= true then
		return false, "BadArgs"
	end
	if needsReady and self._ready then
		local readyOk, ready = pcall(self._ready, owner)
		if not readyOk or ready ~= true then
			return false, "ProfileNotLoaded"
		end
	end
	local ran, ok, data, extra = pcall(handler, owner, ...)
	if not ran then
		self._warn(("[Net] %s handler failed: %s"):format(name, tostring(ok)))
		return false, "Busy"
	end
	return ok == true, data, extra
end

-- Runs one request. `check(...)` must return exactly true; `handler(owner, ...)`
-- returns (ok, reasonOrData, extra?). Returns (ok, reasonOrData, extra?); the
-- optional third value carries e.g. PreviewLayout's offending cell key.
function RemoteGuard:Call(owner: any, name: string, check: (...any) -> boolean, handler: (any, ...any) -> (boolean, any, any), ...)
	return run(self, owner, name, check, handler, true, ...)
end

-- Same as Call without the ready check, for static data that needs no loaded
-- profile (GetCatalog). Rate limit and argument check still apply.
function RemoteGuard:CallOpen(owner: any, name: string, check: (...any) -> boolean, handler: (any, ...any) -> (boolean, any, any), ...)
	return run(self, owner, name, check, handler, false, ...)
end

return RemoteGuard
