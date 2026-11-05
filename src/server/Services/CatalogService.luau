-- GetCatalog: the frozen display catalog (Rules/Catalog), built once from the
-- server definitions. Static and the same for everyone, so it needs no loaded
-- profile (a player whose load failed still gets names for the failure screen);
-- the rate limit and the no-arguments check still apply.

local Net = require(script.Parent.Parent.Infrastructure.Net)
local Catalog = require(script.Parent.Parent.Rules.Catalog)

local CatalogService = {}

local catalog = nil

function CatalogService.Get()
	if catalog == nil then
		catalog = Catalog.Build()
	end
	return catalog
end

function CatalogService.Init()
	Net.HandleOpen("GetCatalog", function(...)
		return select("#", ...) == 0
	end, function()
		return true, CatalogService.Get()
	end)
end

return CatalogService
