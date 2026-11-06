-- Load tracking for the uploaded UI sprites (SpriteIds, SpriteIds3, SpriteIds4). Every id is preloaded once;
-- an id that is missing or fails to load is marked Failed, and the UI pieces that use it switch to the minimal
-- neutral fallback image (Sprites.Fallback; never a code-drawn replacement shape). Status holds the last fetch
-- status per id.
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

local Ids = require(script.Parent.SpriteIds)
local Ids3 = require(script.Parent.SpriteIds3)
local IconIds = require(script.Parent.IconIds)
local ids4Module = script.Parent:FindFirstChild("SpriteIds4") -- v4 frames and reel art (optional until it lands)
local Ids4 = if ids4Module then require(ids4Module) else {}

local Sprites = { Failed = {} :: { [string]: boolean }, Status = {} :: { [string]: string }, Ids = Ids, Ids3 = Ids3, Ids4 = Ids4 }

local watchers: { [string]: { () -> () } } = {}

-- Minimal neutral image shown when a sprite is unusable: the plain small panel (a AI design assistant sprite itself).
local fallbackSpec = if type((Ids4 :: any).Panels) == "table" then (Ids4 :: any).Panels.Small else nil
Sprites.Fallback = fallbackSpec
Sprites.FallbackId = if fallbackSpec then fallbackSpec.Id else (Ids.Kit and Ids.Kit.PanelSmall and Ids.Kit.PanelSmall.Id) or ""

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

-- Looks a sprite up by dotted path in the v4 set ("Reel.Pointer", "Frames.Pill", ...): an id string or a
-- spec table, nil until SpriteIds4 has it. Every element still waiting for AI design assistant art routes through here, so
-- landing the art only needs ids, no code changes.
function Sprites.Get(path: string): any
	local node: any = Ids4
	for part in string.gmatch(path, "[^%.]+") do
		if type(node) ~= "table" then
			return nil
		end
		node = node[part]
	end
	if type(node) == "string" and not Sprites.Ok(node) then
		return nil
	end
	return node
end

-- True when the id is usable (present and not known to have failed).
function Sprites.Ok(id: any): boolean
	return type(id) == "string" and id ~= "" and not Sprites.Failed[id]
end

-- Runs onFail when the id fails to load (now if it already has).
function Sprites.Watch(id: string, onFail: () -> ())
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
end

local function markFailed(id: string)
	if Sprites.Failed[id] then
		return
	end
	Sprites.Failed[id] = true
	local list = watchers[id]
	watchers[id] = nil
	for _, fn in list or {} do
		task.spawn(fn)
	end
end

task.spawn(function()
	local ids = {}
	collect(Ids, ids)
	collect(Ids3, ids)
	collect(IconIds, ids)
	collect(Ids4, ids)
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
