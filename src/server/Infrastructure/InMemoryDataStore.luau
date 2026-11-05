-- In-memory stand-in for a DataStore (UpdateAsync/GetAsync). Used by specs and by
-- Studio sessions without API access; data is lost when the server stops.
-- ProfileService only uses it when RunService:IsStudio(), never in a live server.
-- `failNext` makes the next N calls error, to exercise retry paths.

local InMemoryDataStore = {}
InMemoryDataStore.__index = InMemoryDataStore

local function copy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, inner in value do
		out[key] = copy(inner)
	end
	return out
end

function InMemoryDataStore.new()
	return setmetatable({ _data = {}, failNext = 0, calls = 0 }, InMemoryDataStore)
end

function InMemoryDataStore:_maybeFail()
	self.calls += 1
	if self.failNext > 0 then
		self.failNext -= 1
		error("InMemoryDataStore: simulated failure")
	end
end

function InMemoryDataStore:UpdateAsync(key: string, transform: (any) -> any)
	self:_maybeFail()
	local new = transform(copy(self._data[key]))
	if new ~= nil then
		self._data[key] = copy(new)
	end
	return copy(new)
end

function InMemoryDataStore:GetAsync(key: string)
	self:_maybeFail()
	return copy(self._data[key])
end

return InMemoryDataStore
