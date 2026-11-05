-- The only module that calls DataStore APIs. Wraps one store with retries and
-- exponential backoff. A failed write is never reported as a success: callers get
-- (false, reason) and keep their data pending.

local DataStoreGateway = {}
DataStoreGateway.__index = DataStoreGateway

DataStoreGateway.MAX_ATTEMPTS = 5
DataStoreGateway.BASE_DELAY_SECONDS = 2

export type Options = {
	store: any, -- a DataStore, or any object with UpdateAsync
	sleep: ((number) -> ())?,
	waitForBudget: (() -> ())?,
	maxAttempts: number?,
	baseDelay: number?,
}

function DataStoreGateway.new(options: Options)
	return setmetatable({
		_store = options.store,
		_sleep = options.sleep or task.wait,
		_waitForBudget = options.waitForBudget or function() end,
		_maxAttempts = options.maxAttempts or DataStoreGateway.MAX_ATTEMPTS,
		_baseDelay = options.baseDelay or DataStoreGateway.BASE_DELAY_SECONDS,
	}, DataStoreGateway)
end

-- Fewer retries while the server shuts down (the close budget is short).
function DataStoreGateway:SetMaxAttempts(attempts: number)
	self._maxAttempts = attempts
end

-- Atomic read-modify-write. `transform(old)` returns the new value, or nil to
-- cancel without writing. Returns (ok, newValueOrNil | errorMessage).
function DataStoreGateway:Update(key: string, transform: (any) -> any)
	local lastError
	for attempt = 1, self._maxAttempts do
		self._waitForBudget()
		local ok, result = pcall(self._store.UpdateAsync, self._store, key, transform)
		if ok then
			return true, result
		end
		lastError = result
		if attempt < self._maxAttempts then
			self._sleep(self._baseDelay * 2 ^ (attempt - 1))
		end
	end
	return false, tostring(lastError)
end

return DataStoreGateway
