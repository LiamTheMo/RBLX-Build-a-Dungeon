-- Build mode: overview camera, local DRAFT layout, inventory of unplaced rooms,
-- ghost preview, route overlay and Commit/Cancel. The draft is only a request:
-- the server checks it (PreviewLayout, debounced) to draw the route and the
-- offending cell, re-validates CommitLayout and owns the real layout. Cells come
-- from the plot's server-built tiles (Ui/Cells); room data from the Catalog.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Ui = script.Parent.Parent.Ui
local Badges = require(Ui.Badges)
local Bus = require(Ui.Bus)
local Catalog = require(Ui.Catalog)
local Cells = require(Ui.Cells)
local Doors = require(Ui.Doors)
local Kit = require(Ui.Kit)
local Net = require(Ui.Net)
local Plots = require(Ui.Plots)
local P = require(Ui.PanelsKit)
local Sprites = require(Ui.Sprites)
local SpriteIds = require(Ui.SpriteIds)
local RarityColors = require(Ui.RarityColors)
local ReasonText = require(Ui.ReasonText)
local Scale = require(Ui.Scale)
local Settings = require(Ui.Settings)
local Sound = require(Ui.Sound)
local State = require(Ui.State)
local Theme = require(Ui.Theme)
local Toast = require(Ui.Toast)

local make = Kit.Make

local Build = {}

local KIND_COLOR = {
	Defender = Color3.fromRGB(90, 200, 110),
	Trap = Color3.fromRGB(220, 110, 70),
	Treasure = Color3.fromRGB(255, 200, 61),
	Support = Color3.fromRGB(90, 160, 230),
}
local GOOD, BAD = Color3.fromRGB(74, 222, 128), Color3.fromRGB(255, 92, 92)
local PREVIEW_DELAY = 0.15 -- seconds after the last draft change before asking the server

local active = false
local plot: Model? = nil
local anchor = CFrame.new()
local draft: { [string]: string } = {}
local selectedType: string? = nil
local selectedKind = "All"
local carry: string? = nil -- instance being moved
local selectedCell: string? = nil
local hintCell: string? = nil
local routeValid = true
local ui: any = nil
local worldFolder: Folder? = nil
local ghost: Instance? = nil
local ghostKey = ""
local draftModels: { Instance } = {}
local markers: { [string]: Part } = {}
local hintHand: BillboardGui? = nil
local lastTap = 0
local lastHint = -10
local returnAt = 0
-- Latest server answer for the draft (PreviewLayout). Sig identifies the draft it
-- belongs to; Pending while a check for the current draft is outstanding.
local preview = { Sig = nil :: string?, Gen = 0, Pending = false, Ok = true, Data = {} :: any, Cell = nil :: string?, Off = {} :: { [string]: boolean } }
local modelKeys: { [Instance]: string } = {}
local applyOffRoute

local function cellSize(): number
	return Catalog.Current.Grid.CellSize
end

local function entranceKey(): string
	return Catalog.Current.Grid.EntranceKey
end

local function cellWorld(key: string, y: number?): CFrame
	return (plot and Cells.World(plot, key, y)) or anchor
end

-- False for the entrance cell (tile attribute Placeable).
local function placeable(key: string): boolean
	local tile = plot and Cells.Tile(plot, key)
	return tile ~= nil and tile:GetAttribute("Placeable") == true
end

local function roomOf(instanceId: string): any
	local s = State.Current
	return s and s.Rooms and s.Rooms[instanceId]
end

local function placedSet(): { [string]: boolean }
	local set = {}
	for _, instanceId in draft do
		set[instanceId] = true
	end
	return set
end

-- Cards group owned rooms that look identical (id, rarity, perks, level).
local function groupKey(room: any): string
	local kinds = {}
	for _, p in room.Perks or {} do
		table.insert(kinds, p.Kind)
	end
	table.sort(kinds)
	return ("%s|%s|%s|%d|%s"):format(room.Id, Catalog.RoomRarity(room.Id, room), table.concat(kinds, ","), room.Level or 1, room.Modifier or "")
end

local function inventory(): ({ [string]: any }, { string })
	local s = State.Current
	local placed = placedSet()
	local groups: { [string]: any } = {}
	local keys = {}
	for instanceId, room in (s and s.Rooms) or {} do
		local def = Catalog.Room(room.Id)
		if def and def.Placeable then
			local k = groupKey(room)
			local g = groups[k]
			if not g then
				g = { Key = k, Id = room.Id, Rarity = Catalog.RoomRarity(room.Id, room), Level = room.Level or 1, Perks = room.Perks or {}, Modifier = room.Modifier, Free = {} }
				groups[k] = g
				table.insert(keys, k)
			end
			if not placed[instanceId] then
				table.insert(g.Free, instanceId)
			end
		end
	end
	for _, g in groups do
		table.sort(g.Free)
	end
	table.sort(keys, function(a, b)
		local ga, gb = groups[a], groups[b]
		local order = Catalog.Current.RoomOrder
		local ia, ib = table.find(order, ga.Id) or 99, table.find(order, gb.Id) or 99
		if ia ~= ib then
			return ia < ib
		end
		local ra, rb = Catalog.RarityRank(ga.Rarity) or 0, Catalog.RarityRank(gb.Rarity) or 0
		if ra ~= rb then
			return ra < rb
		end
		return a < b
	end)
	return groups, keys
end

-- World visuals are AI design assistant sprites on invisible flat parts (SurfaceGui, top face). The cell overlay sprites are opaque, so
-- their transparency is set here in code.
local WORLD = Kit.Spec("World")
local PX_PER_STUD = 40

local function flatPart(name: string, size: Vector3): (Part, SurfaceGui)
	local part = make("Part", {
		Name = name,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
		Size = size,
	})
	local sg = make("SurfaceGui", {
		Face = Enum.NormalId.Top,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = PX_PER_STUD,
		LightInfluence = 0,
		AlwaysOnTop = false,
		Adornee = part,
	}, part)
	return part, sg
end

local MARKER_SPEC = { Selected = "CellSelected", Offender = "CellInvalid", Hint = "CellValid", Ghost = "CellValid" }

-- Flat sprite marker on a cell (CellValid / CellInvalid / CellSelected); nil hides it. `spec` overrides the sprite name.
local function marker(name: string, key: string?, color: Color3?, spec: string?)
	local part = markers[name]
	if not key then
		if part then
			part.Parent = nil
		end
		return
	end
	if not part then
		local sg
		part, sg = flatPart(name, Vector3.new(cellSize() - 0.4, 0.05, cellSize() - 0.4))
		local img = Kit.Sprite(sg, "World." .. (spec or MARKER_SPEC[name] or "CellValid"), { Name = "Img", Size = UDim2.fromScale(1, 1), ImageTransparency = 0.45, ScaleType = Enum.ScaleType.Stretch })
		markers[name] = part
	end
	local img = part.SurfaceGui.Img
	local want = Kit.Spec("World." .. (spec or MARKER_SPEC[name] or "CellValid"))
	if want and img.Image ~= want.Id then
		img.Image = want.Id
	end
	img.ImageColor3 = if color then Color3.new(1, 1, 1):Lerp(color, 0.0) else Color3.new(1, 1, 1)
	part.CFrame = cellWorld(key, 0.15)
	part.Parent = worldFolder
end

local function clearDraftModels()
	for _, m in draftModels do
		m:Destroy()
	end
	table.clear(draftModels)
	table.clear(modelKeys)
end

local function artRoom(roomId: string): Instance?
	local art = ReplicatedStorage:FindFirstChild("Art")
	local rooms = art and art:FindFirstChild("Rooms")
	local def = Catalog.Room(roomId)
	return rooms and rooms:FindFirstChild((def and def.ArtSource) or roomId)
end

-- Tile art is hidden locally under draft rooms (the server hides it under placed ones).
local function setTilesHidden(hiddenAt: (string) -> boolean)
	local folder = plot and Cells.Folder(plot)
	for _, tile in if folder then folder:GetChildren() else {} do
		local key = tile:GetAttribute("CellKey")
		if type(key) == "string" then
			local modifier = if hiddenAt(key) then 1 else 0
			for _, part in Cells.Parts(tile) do
				part.LocalTransparencyModifier = modifier
			end
		end
	end
end

local function renderDraft()
	clearDraftModels()
	local function occupied(k: string): boolean
		return draft[k] ~= nil
	end
	setTilesHidden(occupied)
	for key, instanceId in draft do
		local room = roomOf(instanceId)
		local def = room and Catalog.Room(room.Id)
		if def then
			local model: Instance
			local art = artRoom(room.Id)
			if art then
				model = art:Clone()
				for _, d in model:GetDescendants() do
					if d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = false
						d.CanQuery = false
					end
				end
				if model:IsA("Model") then
					model:PivotTo(cellWorld(key))
				end
				Doors.Apply(model, key, occupied)
			else
				local p = make("Part", {
					Anchored = true,
					CanCollide = false,
					CanQuery = false,
					Size = Vector3.new(cellSize() - 0.6, 3, cellSize() - 0.6),
					Color = KIND_COLOR[def.Kind] or Theme.Accent,
					Material = Enum.Material.SmoothPlastic,
					CFrame = cellWorld(key, 1.5),
				})
				local gui = make("BillboardGui", { Size = UDim2.fromOffset(110, 28), StudsOffset = Vector3.new(0, 2.5, 0), AlwaysOnTop = true }, p)
				local l = Kit.Label(gui, def.DisplayName, 16, Theme.TextPrimary, true)
				l.Size = UDim2.fromScale(1, 1)
				l.TextStrokeTransparency = 0.2
				model = p
			end
			model.Parent = worldFolder
			table.insert(draftModels, model)
			modelKeys[model] = key
		end
	end
	applyOffRoute()
end

-- Rooms the server says are off the route (any cell is allowed; they just never see visitors) are dimmed
-- and carry a small "off route" tag.
function applyOffRoute()
	for model, key in modelKeys do
		local off = preview.Off[key] == true
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = if off then 0.55 else 0
			end
		end
		if model:IsA("BasePart") then
			model.LocalTransparencyModifier = if off then 0.55 else 0
		end
		local tag = model:FindFirstChild("OffRouteTag")
		if off and not tag then
			local adornee = if model:IsA("BasePart") then model else model:FindFirstChildWhichIsA("BasePart", true)
			if adornee then
				local gui = make("BillboardGui", { Name = "OffRouteTag", Adornee = adornee, Size = UDim2.fromOffset(44, 44), StudsOffset = Vector3.new(0, 5, 0), AlwaysOnTop = true, MaxDistance = 200 }, model)
				Kit.Icon(gui, "Map", UDim2.fromScale(1, 1))
				local x = Kit.Icon(gui, "Cross", UDim2.fromScale(0.5, 0.5))
				x.AnchorPoint, x.Position = Vector2.new(1, 1), UDim2.fromScale(1, 1)
			end
		elseif not off and tag then
			tag:Destroy()
		end
	end
end

local function renderRoute(order: { string }?)
	local old = worldFolder and worldFolder:FindFirstChild("Overlay")
	if old then
		old:Destroy()
	end
	if not order or #order == 0 then
		return
	end
	local overlay = make("Folder", { Name = "Overlay" }, worldFolder)
	local prev = cellWorld(entranceKey(), 0.4).Position
	local WIDTH = 1.6
	for _, key in order do
		local nextPos = cellWorld(key, 0.4).Position
		local len = (nextPos - prev).Magnitude
		if len > 0.5 then
			-- One flat strip per leg: a row of RouteDot sprites with a RouteArrow in the middle pointing along the path.
			local part, sg = flatPart("Leg", Vector3.new(WIDTH, 0.05, len))
			part.CFrame = CFrame.lookAt((prev + nextPos) / 2, nextPos)
			local w, h = WIDTH * PX_PER_STUD, len * PX_PER_STUD
			local dots = math.max(2, math.floor(len / 1.4))
			for i = 1, dots do
				local f = (i - 0.5) / dots
				if math.abs(f - 0.5) > 0.12 then
					local d = Kit.Sprite(sg, "World.RouteDot", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(w / 2, h * f), Size = UDim2.fromOffset(w * 0.4, w * 0.4), ImageTransparency = 0.15 })
					d.ZIndex = 1
				end
			end
			-- Top-face "up" is the part's -Z, which looks toward the next cell.
			Kit.Sprite(sg, "World.RouteArrow", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(w / 2, h / 2), Size = UDim2.fromOffset(w * 0.8, w * 0.95), ZIndex = 2 })
			part.Parent = overlay
		end
		prev = nextPos
	end
end

local function remaining(key: string?): number
	local g = key and inventory()[key]
	return if g then #g.Free else 0
end

local function refreshInventory()
	for _, c in ui.Scroll:GetChildren() do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	local groups, keys = inventory()
	local filtered = {}
	for _, key in keys do
		local def = Catalog.Room(groups[key].Id)
		if selectedKind == "All" or (def and def.Kind == selectedKind) then table.insert(filtered, key) end
	end
	keys = filtered
	for kind, tab in ui.KindTabs do tab.SetSelected(kind == selectedKind) end
	local phone = Scale.Phone
	if ui.Empty then
		ui.Empty.Visible = #keys == 0
	end
	-- The tray holds one row of whole rarity frames (Rarity.* art, 0.72:1) as tall as the tray's Inner rect.
	local cardH = math.max(60, math.floor((ui.TrayInnerH or 110) - (if phone then 4 else 12)))
	local rs = Kit.Spec("Rarity.Common")
	local cardW = math.floor(cardH * rs.Size.X / rs.Size.Y)
	local roomSize = math.floor(cardH * 0.36)
	-- ONE name size for every card of this layout: 18, or the largest size at which the longest single word of any name fits the
	-- card (a word never breaks mid-letter). It never varies per card.
	local nameSize = Theme.TextSize.Label
	local availW = cardW * 0.96
	for _, k in keys do
		local nm = Catalog.Room(groups[k].Id)
		for word in string.gmatch(if nm then nm.DisplayName else "", "%S+") do
			local w = Kit.Measure(word, Theme.TextSize.Label, Theme.HeadingFont, 2000).X
			if w > availW then
				nameSize = math.min(nameSize, math.floor(Theme.TextSize.Label * availW / w))
			end
		end
	end
	nameSize = math.max(nameSize, 11)
	-- The count chip rests on the card's top edge: the content starts 20 px lower, the room icon takes what the name leaves.
	roomSize = math.clamp(cardH - 14 - math.ceil(nameSize * 2.2) - 2, 24, math.floor(cardH * 0.62))
	for i, key in keys do
		local g = groups[key]
		local def = Catalog.Room(g.Id)
		local count = #g.Free
		local btn = Kit.Button(ui.Scroll, {
			Text = "",
			Size = UDim2.fromOffset(cardW, cardH),
			LayoutOrder = i,
			Rarity = g.Rarity,
			Tip = g.Rarity,
			OnClick = function()
				carry = nil
				selectedCell = nil
				selectedType = if selectedType == key then nil else key
				Build.Refresh()
			end,
		})
		-- Content sits inside the frame's Inner rect: icon, then the name wrapped on up to two lines, then perks. The count chip
		-- rests on the top-right corner, clear of the name.
		-- 130% of the Inner width (still inside the card art): names are one fixed size, so they need room not to break mid-word.
		local inner = make("CanvasGroup", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(1.3, 1), GroupTransparency = if count > 0 then 0 else 0.5, ZIndex = 2 }, btn.Content)
		make("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1) }, inner)
		make("UIPadding", { PaddingTop = UDim.new(0, 14) }, inner)
		P.RoomImage(inner, g.Id, roomSize, def.Kind).LayoutOrder = 0
		local hasPerks = #g.Perks > 0 and not phone
		local name = Kit.Label(inner, def.DisplayName .. (if g.Level > 1 then " Lv" .. g.Level else ""), if phone then 14 else 18, Theme.TextPrimary, true)
		-- One fixed name size (18) on every card, desktop and phone; the row holds two lines, a long name wraps.
		name.Size, name.LayoutOrder = UDim2.new(1, 0, 0, math.ceil(nameSize * 2.2)), 1
		name.TextYAlignment = Enum.TextYAlignment.Center
		name.TextWrapped = true
		Kit.FixedText(name, nameSize)
		Kit.Stroke(name, Theme.Stroke, 2)
		if hasPerks then
			Kit.Perks(inner, g.Perks, true).LayoutOrder = 3
		end
		if RarityColors.Shimmer[g.Rarity] then
			btn.Shimmer()
		end
		if g.Modifier then
			local mod = Badges.Modifier(btn.Instance, g.Modifier, if phone then 22 else 26)
			if mod then
				mod.AnchorPoint, mod.Position, mod.ZIndex = Vector2.new(0, 0), UDim2.new(0, 6, 0, 6), 4
				for _, d in mod:GetDescendants() do
					if d:IsA("GuiObject") then
						d.ZIndex = 4
					end
				end
			end
		end
		local pill = Kit.Count(btn.Instance, ("x%d"):format(count), count > 0, if phone then 28 else 32)
		pill.AnchorPoint, pill.Position, pill.ZIndex = Vector2.new(1, 0), UDim2.new(1, -2, 0, -8), 6
		Kit.PillLabel(pill).ZIndex = 7
		btn.SetSelected(selectedType == key)
		btn.SetEnabled(count > 0)
	end
end

-- Banner, Commit button, route overlay and offender marker from the latest
-- server check of the draft ("checking" while one is outstanding).
local function showRouteStatus()
	if not active then
		return
	end
	if preview.Pending then
		routeValid = false
		ui.Status.Text = "..."
		ui.BannerSpec("Info")
		ui.Commit.SetEnabled(false, "Confirm")
		marker("Offender", nil)
		return
	end
	local ok, orderOrReason, offender = preview.Ok, preview.Data, preview.Cell
	routeValid = ok
	if ok then
		local n = #orderOrReason
		local offCount = 0
		for _ in preview.Off do
			offCount += 1
		end
		ui.Status.Text = if n == 0 then "Place a room" elseif offCount > 0 then ("%d rooms, %d off route"):format(n, offCount) else ("%d rooms"):format(n)
		ui.BannerSpec("Good")
		renderRoute(orderOrReason)
		applyOffRoute()
	else
		ui.Status.Text = ReasonText.Get(orderOrReason)
		ui.BannerSpec("Bad")
		renderRoute(nil)
	end
	ui.Commit.SetEnabled(ok, "Confirm")
	marker("Offender", if ok then nil else offender, BAD)
end

local function draftSignature(): string
	local parts = {}
	for key, instanceId in draft do
		table.insert(parts, key .. "=" .. instanceId)
	end
	table.sort(parts)
	return table.concat(parts, ";")
end

-- Asks the server to check the draft PREVIEW_DELAY s after it last changed. Only
-- the newest request's answer is shown; Commit is still validated on its own.
local function requestPreview()
	local sig = draftSignature()
	if sig == preview.Sig then
		return -- this draft is already checked or being checked
	end
	preview.Sig = sig
	preview.Gen += 1
	preview.Pending = true
	local gen = preview.Gen
	task.delay(PREVIEW_DELAY, function()
		if gen ~= preview.Gen or not active then
			return
		end
		local ok, data, cell = Net.Invoke("PreviewLayout", table.clone(draft))
		if gen ~= preview.Gen or not active then
			return
		end
		if not ok and (data == "RateLimited" or data == "Busy") then
			task.delay(0.5, function()
				if gen == preview.Gen and active then
					preview.Sig = nil -- ask again
					requestPreview()
					showRouteStatus()
				end
			end)
			return
		end
		preview.Pending = false
		preview.Ok = ok
		preview.Data = if ok and type(data) ~= "table" then {} else data
		preview.Cell = if type(cell) == "string" then cell else nil
		preview.Off = {}
		if ok and type(cell) == "table" then -- third value: cells of rooms that are off the route
			for _, k in cell do
				preview.Off[k] = true
			end
		end
		showRouteStatus()
	end)
end

-- Recompute route status and everything drawn from the draft.
function Build.Refresh()
	if not active then
		return
	end
	-- Prune instances the server no longer lists.
	for key, instanceId in draft do
		if not roomOf(instanceId) then
			draft[key] = nil
		end
	end
	requestPreview()
	showRouteStatus()
	marker("Selected", selectedCell, Theme.TextPrimary)
	marker("Hint", if hintCell and not draft[hintCell] then hintCell else nil, nil)
	if not hintHand then
		hintHand = make("BillboardGui", { Name = "TapHint", Size = UDim2.fromOffset(56, 56), StudsOffset = Vector3.new(0, 3, 0), AlwaysOnTop = true, LightInfluence = 0 })
		Kit.Icon(hintHand, "TapHand", UDim2.fromScale(1, 1))
	end
	if hintCell and not draft[hintCell] and markers.Hint then
		hintHand.Adornee = markers.Hint
		hintHand.Parent = worldFolder
	else
		hintHand.Parent = nil
	end
	renderDraft()
	refreshInventory()

	local room = selectedCell and roomOf(draft[selectedCell])
	ui.Callout.Visible = room ~= nil
	if room then
		local def = Catalog.Room(room.Id)
		ui.CalloutName.Text = if def then def.DisplayName else room.Id
		Kit.SetIcon(ui.CalloutIcon, room.Id)
	end
end

local function cellAtViewport(pos: Vector2): string?
	local inset = GuiService:GetGuiInset()
	return plot and Cells.KeyAt(plot, pos - inset)
end

local function placeAt(key: string)
	local instanceId = carry
	if not instanceId and selectedType then
		local g = inventory()[selectedType]
		instanceId = g and g.Free[1]
	end
	if not instanceId then
		Toast.Show("None of that room left. Remove one from the dungeon first.", "Info")
		selectedType = nil
		Build.Refresh()
		return
	end
	draft[key] = instanceId
	Sound.Play("Place")
	carry = nil
	selectedCell = nil
	if selectedType and remaining(selectedType) - 0 <= 0 then
		selectedType = nil
	end
	Build.Refresh()
end

local function tapAt(pos: Vector2)
	if not active or os.clock() - lastTap < 0.1 then
		return
	end
	lastTap = os.clock()
	local key = cellAtViewport(pos)
	if not key then
		if os.clock() - lastHint > 2 then
			lastHint = os.clock()
			Toast.Show("Tap a grid square", "Info")
		end
		selectedCell = nil
		Build.Refresh()
		return
	end
	if not placeable(key) then
		Toast.Show(ReasonText.Get("OnEntrance"), "Bad")
		Sound.Play("Error")
		return
	end
	if draft[key] then
		selectedCell = key
		local scale = math.max(Scale.Value, 0.1)
		local inset = GuiService:GetGuiInset()
		local viewport = workspace.CurrentCamera.ViewportSize
		local x = math.clamp((pos.X - inset.X) / scale + 12, 4, math.max(4, viewport.X / scale - 304))
		local bottom = math.min((viewport.Y - inset.Y) / scale, ui.Buttons.AbsolutePosition.Y / scale)
		local y = math.clamp((pos.Y - inset.Y) / scale - 70, 4, math.max(4, bottom - 148))
		ui.Callout.AnchorPoint, ui.Callout.Position = Vector2.zero, UDim2.fromOffset(x, y)
		Build.Refresh()
	elseif selectedType or carry then
		placeAt(key)
	else
		selectedCell = nil
		Build.Refresh()
	end
end

-- Ghost follows the mouse (touch places directly on tap).
local function updateGhost()
	if not UserInputService.MouseEnabled or (not selectedType and not carry) then
		if ghost then
			ghost.Parent = nil
		end
		marker("GhostMark", nil)
		return
	end
	local key = cellAtViewport(UserInputService:GetMouseLocation())
	if not key then
		if ghost then
			ghost.Parent = nil
		end
		marker("GhostMark", nil)
		return
	end
	local valid = placeable(key) and draft[key] == nil
	local tag = key .. (valid and "1" or "0")
	if tag == ghostKey and ghost and ghost.Parent then
		return
	end
	ghostKey = tag
	if not ghost then
		local art = ReplicatedStorage:FindFirstChild("Art")
		local props = art and art:FindFirstChild("Props")
		local template = props and props:FindFirstChild("GhostRoom")
		if template then
			ghost = template:Clone()
			for _, d in ghost:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
				end
			end
		else
			-- No ghost art: an empty anchor (the GhostOk / GhostBad cell sprite below carries the preview).
			ghost = make("Part", {
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				Transparency = 1,
				Size = Vector3.new(0.2, 0.2, 0.2),
			})
		end
	end
	local g = ghost :: Instance
	if g:IsA("Model") then
		g:PivotTo(cellWorld(key))
	elseif g:IsA("BasePart") then
		g.CFrame = cellWorld(key, if g.Name == "GhostRoom" then 0 else 1.5)
	end
	local color = if valid then GOOD else BAD
	marker("GhostMark", key, nil, if valid then "GhostOk" else "GhostBad")
	if g:IsA("BasePart") and g.Transparency < 1 then
		g.Color = color
	end
	for _, d in g:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color = color
		end
	end
	g.Parent = worldFolder
end

-- Camera ----------------------------------------------------------------

local camConn: RBXScriptConnection? = nil
local savedType, savedCF = Enum.CameraType.Custom, CFrame.new()
local returning = false
local overview = true -- default to a clear view of the plot
local savedZoom: { Min: number, Max: number }? = nil

-- Normal camera, pushed out a little so the whole plot fits: raises the minimum zoom distance.
local function freeCamera()
	if camConn then
		camConn:Disconnect()
		camConn = nil
	end
	local cam = workspace.CurrentCamera
	if cam.CameraType == Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Custom
	end
	local player = Players.LocalPlayer
	if not savedZoom then
		savedZoom = { Min = player.CameraMinZoomDistance, Max = player.CameraMaxZoomDistance }
	end
	player.CameraMaxZoomDistance = math.max(savedZoom.Max, 90)
	player.CameraMinZoomDistance = math.max(savedZoom.Min, 12)
end

local function restoreZoom()
	if savedZoom then
		local player = Players.LocalPlayer
		player.CameraMinZoomDistance = savedZoom.Min
		player.CameraMaxZoomDistance = savedZoom.Max
		savedZoom = nil
	end
end

local function camGoal(): CFrame
	return anchor * CFrame.lookAt(Vector3.new(0, 25, 18), Vector3.new(0, 0, -2))
end

local function startCamera()
	local cam = workspace.CurrentCamera
	if not camConn then -- re-entering mid-return must keep the original camera
		savedType, savedCF = cam.CameraType, cam.CFrame
	end
	cam.CameraType = Enum.CameraType.Scriptable
	returning = false
	if camConn then
		camConn:Disconnect()
	end
	camConn = RunService.RenderStepped:Connect(function(dt)
		local target = if returning then savedCF else camGoal()
		if Settings.Reduced() then
			cam.CFrame = target
		else
			cam.CFrame = cam.CFrame:Lerp(target, 1 - math.exp(-8 * dt))
		end
		if returning and ((cam.CFrame.Position - target.Position).Magnitude < 0.3 or os.clock() - returnAt > 2) then
			cam.CFrame = target
			cam.CameraType = if savedType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else savedType
			if camConn then
				camConn:Disconnect()
				camConn = nil
			end
		end
	end)
end

-- Enter / exit -----------------------------------------------------------

local function setServerRoomsHidden(hidden: boolean)
	local rooms = plot and plot:FindFirstChild("Rooms")
	if not rooms then
		return
	end
	for _, d in rooms:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

local function enter()
	if active or not ui then
		return
	end
	local s = State.Current
	plot = Plots.WaitOwn()
	Cells.WaitFolder(plot)
	if active then
		return -- entered while waiting
	end
	anchor = plot:GetPivot()
	draft = table.clone((s and s.Layout) or {})
	selectedType, carry, selectedCell = nil, nil, nil
	preview.Sig, preview.Gen = nil, preview.Gen + 1
	active = true
	worldFolder = make("Folder", { Name = "BuildDraft" }, workspace)
	setServerRoomsHidden(true)
	if overview then
		startCamera()
	else
		freeCamera()
	end
	ui.Gui.Enabled = true
	Build.Layout()
	Build.Refresh()
end

local function exit()
	if not active then
		return
	end
	active = false
	preview.Gen += 1
	ui.Gui.Enabled = false
	clearDraftModels()
	setTilesHidden(function()
		return false
	end)
	if hintHand then hintHand.Parent = nil end
	if worldFolder then
		worldFolder:Destroy()
	end
	worldFolder, ghost, ghostKey = nil, nil, ""
	table.clear(markers)
	setServerRoomsHidden(false)
	returning = true
	returnAt = os.clock()
	restoreZoom()
	if not camConn then
		workspace.CurrentCamera.CameraType = if savedType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else savedType
	end
end

local function requestBuilding(on: boolean): boolean
	local ok, reason = Net.Invoke("SetBuilding", on)
	if not ok then
		Toast.Show(ReasonText.Get(reason), "Bad")
		Sound.Play("Error")
	end
	return ok
end

-- UI ----------------------------------------------------------------------

function Build.Layout()
	if not ui then
		return
	end
	local phone = Scale.Phone
	local sc = math.max(Scale.Value, 0.01)
	local view = ui.Gui.AbsoluteSize / sc
	if view.X < 50 or view.Y < 50 then
		view = workspace.CurrentCamera.ViewportSize / sc
	end
	local bn, bs = ui.Banner, ui.Inventory
	-- Tray: Panel.Tray is one whole image (5.6:1); its height follows its width, kept to 40% of the screen.
	local tray = Kit.Spec("Panel.Tray")
	local ratio = tray.Size.X / tray.Size.Y
	local trayW = math.min(view.X - (if phone then 8 else 24), if phone then 1180 else 1700)
	local trayH = trayW / ratio
	if trayH > view.Y * (if phone then 0.46 else 0.4) then
		trayH = view.Y * (if phone then 0.46 else 0.4)
		trayW = trayH * ratio
	end
	local invBottom = if phone then 4 else 12
	bs.AnchorPoint, bs.Position, bs.Size = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -invBottom), UDim2.fromOffset(trayW, trayH)
	ui.TrayInnerH = trayH * (tray.Inner.Max.Y - tray.Inner.Min.Y) / tray.Size.Y
	-- Kind tabs (Tab.On / Tab.Off, 2.6:1) sit on a row just above the tray; boxes are >= 44 real px tall.
	local tabH = math.max(if phone then 44 else 56, (if phone then 44 else 46) / sc)
	local tabW = math.floor(tabH * Kit.Spec("Tab.On").Size.X / Kit.Spec("Tab.On").Size.Y)
	ui.KindRow.AnchorPoint, ui.KindRow.Position = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -(invBottom + trayH + 2))
	ui.KindRow.Size = UDim2.fromOffset(tabW * 5 + 4 * 6, tabH)
	for _, tab in ui.KindTabs do
		tab.Instance.Size = UDim2.fromOffset(tabW, tabH)
	end
	local bannerW = if phone then 380 else 440
	local banner = Kit.Spec("ToastWide.Info")
	bn.AnchorPoint, bn.Position, bn.Size = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, if phone then 96 else 122), UDim2.fromOffset(bannerW, bannerW * banner.Size.Y / banner.Size.X)
	-- Confirm / Cancel: centred right above the kind tabs, big touch targets (wide art, ~3.9:1).
	local above = invBottom + trayH + 2 + tabH + (if phone then 6 else 10)
	ui.Buttons.AnchorPoint, ui.Buttons.Position = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -above)
	local bh = math.max(if phone then 52 else 60, 46 / sc)
	local bw = math.floor(bh * 3.9)
	ui.Commit.Instance.Size = UDim2.fromOffset(bw, bh)
	ui.Cancel.Instance.Size = UDim2.fromOffset(bw, bh)
	ui.View.Instance.AnchorPoint = Vector2.new(1, 1)
	ui.View.Instance.Position = UDim2.new(1, if phone then -8 else -16, 1, -above)
	ui.Commit.SetTextSize(22)
	ui.Cancel.SetTextSize(22)
end

local function buildUi()
	local gui = Kit.Screen("Build", 2)
	gui.Enabled = false
	ui = { Gui = gui }

	-- Route-state banner: ToastWide Info (checking) / Good (valid) / Bad (blocked), one whole image with the matching icon.
	ui.Banner = Kit.Panel(gui, { Sprite = "ToastWideInfo" })
	ui.BannerSpec = function(kind: string)
		local spec = Kit.Spec("ToastWide." .. kind)
		if spec and ui.Banner.Image ~= spec.Id then
			Kit.RepaintPanel(ui.Banner, "ToastWide" .. kind)
		end
		ui.IconInfo.Visible, ui.IconOk.Visible, ui.IconBad.Visible = kind == "Info", kind == "Good", kind == "Bad"
	end
	local function bannerIcon(name: string)
		local ic = Kit.Icon(ui.Banner, name, UDim2.fromScale(1, 1))
		make("UIAspectRatioConstraint", { AspectRatio = 1, AspectType = Enum.AspectType.FitWithinMaxSize, DominantAxis = Enum.DominantAxis.Height }, ic)
		ic.AnchorPoint, ic.Position = Vector2.new(0, 0.5), UDim2.fromScale(0, 0.5)
		return ic
	end
	ui.IconInfo, ui.IconOk, ui.IconBad = bannerIcon("Info"), bannerIcon("Good"), bannerIcon("Warn")
	ui.IconOk.Visible, ui.IconBad.Visible = false, false
	ui.Status = Kit.Label(ui.Banner, "", Theme.TextSize.Body, Theme.TextPrimary, true)
	ui.Status.Position = UDim2.new(0, 58, 0, 0)
	ui.Status.Size = UDim2.new(1, -66, 1, 0)
	ui.Status.TextXAlignment = Enum.TextXAlignment.Left
	ui.Status.TextWrapped = true
	Kit.FixedText(ui.Status, 22)

	-- The tray: Panel.Tray (one whole image, 5.6:1) holding a single scrolling row of room cards; the kind tabs sit above it.
	ui.Inventory = Kit.Panel(gui, { Sprite = "Tray" })
	ui.KindTabs = {}
	ui.KindRow = make("Frame", { Name = "KindTabs", BackgroundTransparency = 1 }, gui)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, ui.KindRow)
	for order, kind in { "All", "Defender", "Trap", "Treasure", "Support" } do
		local tab = Kit.Button(ui.KindRow, { Text = kind, Style = "Tab", TextSize = 24, Size = UDim2.fromOffset(146, 56), LayoutOrder = order, OnClick = function()
			selectedKind = kind
			if not carry then selectedType = nil end
			ui.Scroll.CanvasPosition = Vector2.zero
			Build.Refresh()
		end })
		ui.KindTabs[kind] = tab
	end
	ui.Scroll = make("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 6,
		HorizontalScrollBarInset = Enum.ScrollBarInset.None,
		BorderSizePixel = 0,
	}, ui.Inventory)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 14),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, ui.Scroll)
	make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, ui.Scroll)
	ui.Empty = P.Empty(ui.Inventory, "No rooms to place", 1)
	ui.Empty.AnchorPoint, ui.Empty.Position, ui.Empty.Visible = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), false

	ui.Buttons = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY }, gui)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 16), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom, SortOrder = Enum.SortOrder.LayoutOrder }, ui.Buttons)
	ui.Commit = Kit.Button(ui.Buttons, {
		Text = "Confirm",
		Style = "Success",
		Icon = "Check",
		IconLayout = "Row",
		TextSize = 24,
		LayoutOrder = 1,
		OnClick = function()
			if not routeValid then
				return
			end
			local layout = table.clone(draft)
			local ok, reason = Net.Invoke("CommitLayout", layout)
			if not ok then
				Toast.Show(ReasonText.Get(reason), "Bad")
				Sound.Play("Error")
				return
			end
			Sound.Play("Commit")
			if requestBuilding(false) then
				exit()
			end
		end,
	})
	ui.Cancel = Kit.Button(ui.Buttons, {
		Text = "Cancel",
		Style = "Danger",
		Icon = "Cross",
		IconLayout = "Row",
		TextSize = 24,
		LayoutOrder = 2,
		OnClick = function()
			if requestBuilding(false) then
				exit()
			end
		end,
	})

	-- View toggle: normal camera (default) or the angled overview.
	ui.View = Kit.Button(gui, {
		Text = "",
		Icon = "Map",
		IconScale = 0.7,
		Style = "Secondary",
		Round = true,
		Size = UDim2.fromOffset(56, 56),
		Tip = "Overview",
		OnClick = function()
			overview = not overview
			ui.View.SetSelected(overview)
			if overview then
				restoreZoom()
				startCamera()
			else
				if camConn then
					camConn:Disconnect()
					camConn = nil
				end
				workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
				freeCamera()
			end
		end,
	})

	ui.View.SetSelected(overview)

	-- Selected-room callout: icon + name, then Move / Remove side by side.
	ui.Callout = Kit.Panel(gui, { Visible = false, Size = UDim2.fromOffset(360, 127) }) -- Panel.Section 706:248, whole
	ui.CalloutIcon = make("ImageLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(38, 38), ScaleType = Enum.ScaleType.Fit, Image = "" }, ui.Callout)
	ui.CalloutName = Kit.Label(ui.Callout, "", 20, Theme.TextPrimary, true)
	ui.CalloutName.Position = UDim2.fromOffset(46, 0)
	ui.CalloutName.Size = UDim2.new(1, -46, 0, 38)
	ui.CalloutName.TextXAlignment = Enum.TextXAlignment.Left
	Kit.FixedText(ui.CalloutName, 20)
	local move = Kit.Button(ui.Callout, {
		Text = "Move",
		Size = UDim2.new(0.5, -4, 0, 46),
		OnClick = function()
			local instanceId = selectedCell and draft[selectedCell]
			if instanceId then
				draft[selectedCell :: string] = nil
				carry = instanceId
				local room = roomOf(instanceId)
				selectedType = room and groupKey(room)
				selectedCell = nil
				Build.Refresh()
			end
		end,
	})
	move.Instance.Position = UDim2.fromOffset(0, 42)
	local remove = Kit.Button(ui.Callout, {
		Text = "Remove",
		Style = "Danger",
		Size = UDim2.new(0.5, -4, 0, 46),
		OnClick = function()
			if selectedCell then
				draft[selectedCell] = nil
				selectedCell = nil
				Sound.Play("Remove")
				Build.Refresh()
			end
		end,
	})
	remove.Instance.AnchorPoint, remove.Instance.Position = Vector2.new(1, 0), UDim2.new(1, 0, 0, 42)

	Scale.Changed:Connect(function()
		Build.Layout()
		if active then
			Build.Refresh()
		end
	end)
	Build.Layout()
end

function Build.Init()
	State.Start()
end

function Build.Start()
	task.spawn(function()
		Catalog.Wait()
		buildUi()
		Plots.WaitOwn()
	end)

	Bus.BuildRequested:Connect(function()
		if active then
			return
		end
		local s = State.Current
		if s and s.LoadState == "Failed" then
			return
		end
		if requestBuilding(true) then
			enter()
		end
	end)
	Bus.CellHint:Connect(function(key)
		hintCell = key
		Build.Refresh()
	end)

	State.Changed:Connect(function(s)
		if s.Building and not active then
			enter()
		elseif not s.Building and active then
			exit()
		elseif active then
			Build.Refresh()
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if active and not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then
			tapAt(UserInputService:GetMouseLocation())
		end
	end)
	UserInputService.TouchTapInWorld:Connect(function(position, processedByUI)
		if active and not processedByUI then
			tapAt(position)
		end
	end)
	RunService.RenderStepped:Connect(function()
		if active then
			updateGhost()
		end
	end)
end

return Build
