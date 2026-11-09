-- Load tracking for the uploaded UI sprites (SpriteIds6 kit, SpriteIds / SpriteIds3 / SpriteIds4 icon and world art). Every id is preloaded once;
-- an id that is missing or fails to load is marked Failed, and the UI pieces that use it switch to the minimal
-- neutral fallback image (Sprites.Fallback; never a code-drawn replacement shape). Status holds the last fetch
-- status per id.
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

local Ids = require(script.Parent.SpriteIds)
local Ids3 = require(script.Parent.SpriteIds3)
local IconIds = require(script.Parent.IconIds)
local Ids4 = require(script.Parent.SpriteIds4) -- icons and in-world art only
local Ids6 = require(script.Parent.SpriteIds6) -- the unified UI kit: every frame, button, bar, chip, badge and toast

local Sprites = { Failed = {} :: { [string]: boolean }, Status = {} :: { [string]: string }, Ids = Ids, Ids3 = Ids3, Ids4 = Ids4, Ids6 = Ids6 }

local watchers: { [string]: { () -> () } } = {}

-- Minimal neutral image shown when a sprite is unusable: the plain section panel (a kit sprite itself).
local fallbackSpec = Ids6.Panel.Section
Sprites.Fallback = fallbackSpec
Sprites.FallbackId = fallbackSpec.Id

local function collect(node: any, out: { string })
	if type(node) == "string" then
		if string.sub(node, 1, 13) == "rbxassetid://" then
			table.insert(out, node)
		end
	elseif type(node) == "table" then
		if type(node.Id) == "string" then
			table.insert(out, node.Id)
		end
		for k, v in node do
			if k ~= "Id" then
				collect(v, out)
			end
		end
	end
end

-- True when the id is usable (present and not known to have failed).
function Sprites.Ok(id: any): boolean
	return type(id) == "string" and id ~= "" and not Sprites.Failed[id]
end

-- Runs onFail when the id fails to load (now if it already has).
function Sprites.Watch(id: string, onFail: () -> (), owner: Instance?)
	if Sprites.Failed[id] then
		task.defer(onFail)
		return
	end
	local list = watchers[id]
	if not list then
		list = {}
		watchers[id] = list
	end
	table.insert(list, onFail)
	if owner then
		owner.Destroying:Once(function()
			local i = table.find(list, onFail)
			if i then table.remove(list, i) end
		end)
	end
end

local function markFailed(id: string)
	if Sprites.Failed[id] then
		return
	end
	Sprites.Failed[id] = true
	local list = watchers[id]
	watchers[id] = nil
	for _, fn in table.clone(list or {}) do
		task.spawn(fn)
	end
end
Sprites.Fail = markFailed

task.spawn(function()
	local ids = {}
	collect(Ids, ids)
	collect(Ids3, ids)
	collect(IconIds, ids)
	collect(Ids4, ids)
	collect(Ids6, ids)
	local seen, unique = {}, {}
	for _, id in ids do
		if not seen[id] then
			seen[id] = true
			table.insert(unique, id)
		end
	end
	local ok = pcall(function()
		ContentProvider:PreloadAsync(unique, function(contentId: string, status: Enum.AssetFetchStatus)
			Sprites.Status[contentId] = status.Name
			-- Studio Play reports Failure for assets that do load (verified: ImageLabels render), so
			-- there the status is only recorded; published servers switch to the drawn fallback.
			if (status == Enum.AssetFetchStatus.Failure or status == Enum.AssetFetchStatus.TimedOut) and not RunService:IsStudio() then
				markFailed(contentId)
			end
		end)
	end)
	if not ok then
		warn("[Sprites] PreloadAsync failed; sprites load on demand")
	end
end)

return Sprites
