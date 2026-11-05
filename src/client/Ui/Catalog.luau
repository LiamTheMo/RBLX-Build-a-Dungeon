-- The server's display catalog (GetCatalog): room, visitor, rarity and upgrade
-- names and texts, prices, gates and the grid shape. Fetched once (retrying with
-- backoff) and cached; it never changes during a session. Display data only: the
-- server decides everything.
local Net = require(script.Parent.Net)

local Catalog = { Current = nil :: any }

local fetching = false
local rank: { [string]: number } = {}

local function fetch()
	local delay = 0.5
	while Catalog.Current == nil do
		local ok, data = Net.Invoke("GetCatalog")
		if ok and type(data) == "table" and type(data.Rooms) == "table" then
			for i, r in data.Rarities or {} do
				rank[r.Id] = i
			end
			Catalog.Current = data
			return
		end
		task.wait(delay)
		delay = math.min(delay * 2, 8)
	end
end

-- Starts the fetch if needed and yields until the catalog is here.
function Catalog.Wait(): any
	if Catalog.Current == nil and not fetching then
		fetching = true
		task.spawn(fetch)
	end
	while Catalog.Current == nil do
		task.wait(0.1)
	end
	return Catalog.Current
end

function Catalog.Room(id: any): any
	local c = Catalog.Current
	return c and type(id) == "string" and c.Rooms[id] or nil
end

function Catalog.Visitor(id: any): any
	local c = Catalog.Current
	return c and type(id) == "string" and c.Visitors[id] or nil
end

-- 1-based rank of a rarity id (lowest first), nil if unknown. For sorting only.
function Catalog.RarityRank(id: any): number?
	return rank[id]
end

return Catalog
