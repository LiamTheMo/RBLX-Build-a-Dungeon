-- Build mode: overview camera, local DRAFT layout, inventory of unplaced rooms,
-- ghost preview, route overlay and Commit/Cancel. The draft is only a request:
-- the server checks it (PreviewLayout, debounced) to draw the route and the
-- offending cell, re-validates CommitLayout and owns the real layout. Cells come
-- from the plot's server-built tiles (Ui/Cells); room data from the Catalog.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Ui = script.Parent.Parent.Ui
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
local lastTap = 0
local lastHint = -10
local returnAt = 0
-- Latest server answer for the draft (PreviewLayout). Sig identifies the draft it
-- belongs to; Pending while a check for the current draft is outstanding.
local preview = { Sig = nil :: string?, Gen = 0, Pending = false, Ok = true, Data = {} :: any, Cell = nil :: string? }

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
	return ("%s|%s|%s|%d"):format(room.Id, room.Rarity or "Common", table.concat(kinds, ","), room.Level or 1)
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
				g = { Key = k, Id = room.Id, Rarity = room.Rarity or "Common", Level = room.Level or 1, Perks = room.Perks or {}, Free = {} }
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

-- Flat tinted marker on a cell; nil hides it.
local function marker(name: string, key: string?, color: Color3?)
	local part = markers[name]
	if not key then
		if part then
			part.Parent = nil
		end
		return
	end
	if not part then
		part = make("Part", {
			Name = name,
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Material = Enum.Material.Neon,
			Transparency = 0.55,
			Size = Vector3.new(cellSize() - 0.4, 0.2, cellSize() - 0.4),
		})
		markers[name] = part
	end
	part.Color = color :: Color3
	part.CFrame = cellWorld(key, 0.15)
	part.Parent = worldFolder
end

local function clearDraftModels()
	for _, m in draftModels do
		m:Destroy()
	end
	table.clear(draftModels)
end

local function artRoom(roomId: string): Instance?
	local art = ReplicatedStorage:FindFirstChild("Art")
	local rooms = art and art:FindFirstChild("Rooms")
	return rooms and rooms:FindFirstChild(roomId)
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
	for _, key in order do
		local nextPos = cellWorld(key, 0.4).Position
		local len = (nextPos - prev).Magnitude
		make("Part", {
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			Material = Enum.Material.Neon,
			Color = Theme.Success,
			Size = Vector3.new(0.35, 0.2, len + 0.35),
			CFrame = CFrame.lookAt((prev + nextPos) / 2, nextPos),
		}, overlay)
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
	local phone = Scale.Phone
	local cardW, cardH = if phone then 112 else 132, if phone then 128 else 150
	for i, key in keys do
		local g = groups[key]
		local def = Catalog.Room(g.Id)
		local count = #g.Free
		local btn = Kit.Button(ui.Scroll, {
			Text = "",
			Size = UDim2.fromOffset(cardW, cardH),
			LayoutOrder = i,
			Rarity = g.Rarity,
			OnClick = function()
				carry = nil
				selectedCell = nil
				selectedType = if selectedType == key then nil else key
				Build.Refresh()
			end,
		})
		local inner = make("CanvasGroup", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), GroupTransparency = if count > 0 then 0 else 0.5, ZIndex = 2 }, btn.Instance)
		make("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1) }, inner)
		make("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 28), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, inner)
		P.RoomImage(inner, g.Id, if phone then 38 else 52, def.Kind).LayoutOrder = 0
		local name = Kit.Label(inner, def.DisplayName .. (if g.Level > 1 then " Lv" .. g.Level else ""), if phone then 14 else 16, Theme.TextPrimary, true)
		name.Size, name.LayoutOrder = UDim2.new(1, 0, 0, if phone then 28 else 34), 1
		Kit.Rarity(inner, g.Rarity).LayoutOrder = 2
		if #g.Perks > 0 then
			Kit.Perks(inner, g.Perks, phone).LayoutOrder = 3
		end
		if RarityColors.Shimmer[g.Rarity] then
			btn.Shimmer()
		end
		local gem = Kit.Gem(btn.Instance, g.Rarity, UDim2.fromOffset(if phone then 20 else 24, if phone then 20 else 24))
		gem.AnchorPoint, gem.Position, gem.ZIndex = Vector2.new(1, 0), UDim2.new(1, -8, 0, 8), 4
		local pill = Kit.Pill(btn.Instance, ("x%d"):format(count), if count > 0 then Theme.Gold else Theme.Disabled, if count > 0 then Theme.TextOnGold else Theme.DisabledText, 20)
		pill.AnchorPoint, pill.Position, pill.ZIndex = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -10), 4
		btn.SetSelected(selectedType == key)
		btn.SetEnabled(count > 0)
		if selectedType == key and btn.Stroke.Enabled then
			btn.Stroke.Thickness = 5
		end
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
		ui.Status.Text = "Checking route..."
		ui.IconOk.Visible, ui.IconBad.Visible = false, false
		ui.StatusStroke.Color = Theme.TextMuted
		ui.Commit.SetEnabled(false, "Checking...")
		ui.Commit.SetStyle("Primary")
		marker("Offender", nil)
		return
	end
	local ok, orderOrReason, offender = preview.Ok, preview.Data, preview.Cell
	routeValid = ok
	if ok then
		local n = #orderOrReason
		ui.Status.Text = if n == 0 then "Route connected - place rooms next to the entrance" else ("Route connected: %d rooms"):format(n)
		ui.IconOk.Visible, ui.IconBad.Visible = true, false
		ui.StatusStroke.Color = Theme.Success
		renderRoute(orderOrReason)
	else
		ui.Status.Text = ReasonText.Get(orderOrReason)
		ui.IconOk.Visible, ui.IconBad.Visible = false, true
		ui.StatusStroke.Color = Theme.Danger
		renderRoute(nil)
	end
	ui.Commit.SetEnabled(ok, "Fix route")
	ui.Commit.SetStyle(if ok then "Success" else "Primary")
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
	marker("Hint", if hintCell and not draft[hintCell] then hintCell else nil, Theme.Gold)
	renderDraft()
	refreshInventory()

	local room = selectedCell and roomOf(draft[selectedCell])
	ui.Callout.Visible = room ~= nil
	if room then
		local def = Catalog.Room(room.Id)
		ui.CalloutName.Text = if def then def.DisplayName else room.Id
		local rid = SpriteIds.Rooms[room.Id]
		ui.CalloutIcon.Image = if Sprites.Ok(rid) then rid else ""
	end
end

local function cellAtViewport(pos: Vector2): string?
	return plot and Cells.KeyAt(plot, pos)
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
		return
	end
	local key = cellAtViewport(UserInputService:GetMouseLocation())
	if not key then
		if ghost then
			ghost.Parent = nil
		end
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
			ghost = make("Part", {
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				Transparency = 0.5,
				Material = Enum.Material.Neon,
				Size = Vector3.new(cellSize() - 0.6, 3, cellSize() - 0.6),
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
	if g:IsA("BasePart") then
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

local function camGoal(): CFrame
	return anchor * CFrame.lookAt(Vector3.new(0, 36, 26), Vector3.new(0, 0, -2))
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
	startCamera()
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
	if worldFolder then
		worldFolder:Destroy()
	end
	worldFolder, ghost, ghostKey = nil, nil, ""
	table.clear(markers)
	setServerRoomsHidden(false)
	returning = true
	returnAt = os.clock()
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
	local bn, bs = ui.Banner, ui.Inventory
	if phone then
		bn.AnchorPoint, bn.Position, bn.Size = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 52), UDim2.fromOffset(420, 40)
		bs.AnchorPoint, bs.Position, bs.Size = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -4), UDim2.fromOffset(560, 148)
		ui.Buttons.AnchorPoint, ui.Buttons.Position, ui.Buttons.Size = Vector2.new(1, 0.5), UDim2.new(1, -8, 0.5, 0), UDim2.fromOffset(120, 120)
		ui.Callout.AnchorPoint, ui.Callout.Position = Vector2.new(0, 0), UDim2.new(0, 8, 0, 100)
	else
		bn.AnchorPoint, bn.Position, bn.Size = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 96), UDim2.fromOffset(640, 44)
		bs.AnchorPoint, bs.Position, bs.Size = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -16), UDim2.fromOffset(900, 176)
		ui.Buttons.AnchorPoint, ui.Buttons.Position, ui.Buttons.Size = Vector2.new(1, 1), UDim2.new(1, -16, 1, -204), UDim2.fromOffset(160, 120)
		ui.Callout.AnchorPoint, ui.Callout.Position = Vector2.new(0, 1), UDim2.new(0, 16, 1, -204)
	end
	ui.Commit.Instance.Size = UDim2.new(1, 0, 0, 56)
	ui.Cancel.Instance.Size = UDim2.new(1, 0, 0, 56)
end

local function buildUi()
	local gui = Kit.Screen("Build", 2)
	gui.Enabled = false
	ui = { Gui = gui }

	-- Plain drawn pill: its border colour is the route state (green / red / grey) next to a check or "!".
	ui.Banner = Kit.Panel(gui, { Sprite = false, BackgroundColor3 = Theme.BgPanel })
	ui.Banner:FindFirstChildOfClass("UICorner").CornerRadius = Theme.CornerPill
	ui.StatusStroke = ui.Banner:FindFirstChildOfClass("UIStroke")
	ui.IconOk = Kit.Icon(ui.Banner, "Check", UDim2.fromOffset(28, 28), Theme.Success)
	ui.IconOk.Position = UDim2.fromOffset(12, 6)
	ui.IconBad = Kit.Label(ui.Banner, "!", 24, Theme.Danger, true)
	ui.IconBad.Size = UDim2.fromOffset(40, 40)
	ui.IconBad.Visible = false
	ui.Status = Kit.Label(ui.Banner, "", Theme.TextSize.Body, Theme.TextPrimary)
	ui.Status.Position = UDim2.fromOffset(48, 0)
	ui.Status.Size = UDim2.new(1, -60, 1, 0)
	ui.Status.TextXAlignment = Enum.TextXAlignment.Left

	ui.Inventory = Kit.Panel(gui, { Sprite = "Large" })
	ui.Scroll = make("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -28, 1, -16),
		Position = UDim2.fromOffset(14, 8),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 6,
		BorderSizePixel = 0,
	}, ui.Inventory)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, ui.Scroll)
	make("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 6) }, ui.Scroll)

	ui.Buttons = make("Frame", { BackgroundTransparency = 1 }, gui)
	make("UIListLayout", { Padding = UDim.new(0, 8) }, ui.Buttons)
	ui.Commit = Kit.Button(ui.Buttons, {
		Text = "Commit",
		Style = "Success",
		Icon = "Check",
		IconLayout = "Row",
		TextSize = 20,
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
		Style = "Cancel",
		Icon = "Cross",
		IconLayout = "Row",
		TextSize = 20,
		OnClick = function()
			if requestBuilding(false) then
				exit()
			end
		end,
	})

	ui.Callout = Kit.Panel(gui, { Visible = false, Size = UDim2.fromOffset(300, 128) })
	ui.CalloutIcon = make("ImageLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 6), Size = UDim2.fromOffset(44, 44), ScaleType = Enum.ScaleType.Fit, Image = "" }, ui.Callout)
	ui.CalloutName = Kit.Label(ui.Callout, "", 20, Theme.TextPrimary, true)
	ui.CalloutName.Position = UDim2.fromOffset(64, 0)
	ui.CalloutName.Size = UDim2.new(1, -72, 0, 52)
	Kit.Button(ui.Callout, {
		Text = "Move",
		Size = UDim2.fromOffset(130, 52),
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
	}).Instance.Position = UDim2.fromOffset(14, 58)
	Kit.Button(ui.Callout, {
		Text = "Remove",
		Style = "Danger",
		Size = UDim2.fromOffset(130, 52),
		OnClick = function()
			if selectedCell then
				draft[selectedCell] = nil
				selectedCell = nil
				Sound.Play("Remove")
				Build.Refresh()
			end
		end,
	}).Instance.Position = UDim2.fromOffset(156, 58)

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
