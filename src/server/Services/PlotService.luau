-- Plots: assignment, code-built base, room models and replicated attributes
-- (docs/ARCHITECTURE.md, "Replicated plot state"). Art is optional: missing
-- ReplicatedStorage.Art models fall back to code-built graybox.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Balance = require(script.Parent.Parent.Definitions.Balance)
local Grid = require(script.Parent.Parent.Definitions.Grid)
local PlotGeometry = require(script.Parent.Parent.Rules.PlotGeometry)
local Progression = require(script.Parent.Parent.Rules.Progression)
local Route = require(script.Parent.Parent.Rules.Route)
local EncounterSim = require(script.Parent.Parent.Rules.EncounterSim)
local LayoutRules = require(script.Parent.Parent.Rules.LayoutRules)
local ProfileService = require(script.Parent.ProfileService)

local PlotService = {}

local CELL = Grid.CellSize
local WALL = Grid.WallHeight
local VISITOR_ATTRS = {
	"NextVisitorAt",
	"VisitorId",
	"VisitorHealth",
	"VisitorMaxHealth",
	"VisitorProgress",
	"VisitorFighting",
	"VisitorSlowed",
	"VisitorReward",
	"VisitorRewardDestination",
	"VisitorTheft",
}
local TILE_LIFT = 0.04 -- studs; keeps EmptyCellTile art off the base slab (no z-fighting)
local entranceKey = Route.Key(Grid.EntranceCell.Column, Grid.EntranceCell.Row)

local plots = {} -- index -> { Index, Model, Anchor: CFrame, Owner: Player?, Sign: TextLabel }
local byPlayer = {} -- Player -> plot

local function part(parent, name, size, cf, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function art(...)
	local node = ReplicatedStorage:FindFirstChild("Art")
	for _, name in { ... } do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function anchorFor(index: number): CFrame
	local map = workspace:FindFirstChild("Map")
	local anchors = map and map:FindFirstChild("PlotAnchors")
	local anchor = anchors and anchors:FindFirstChild("Plot" .. index)
	if anchor and anchor:IsA("BasePart") then
		anchor.CastShadow = false -- invisible marker part: must not cast a soft shadow blob on the pad
		return anchor.CFrame
	end
	return CFrame.new((index - 1) * 60 - 150, 0.5, 0)
end

local ROLE_COLOR = {
	SlimeNest = Color3.fromRGB(110, 200, 110),
	SpikeHall = Color3.fromRGB(190, 190, 200),
	GuardRoom = Color3.fromRGB(90, 130, 220),
	TreasureRoom = Color3.fromRGB(240, 200, 60),
}

-- Graybox room: floor, 4 corner posts, 4 Door_<Side> walls, a role-shaped prop.
-- North = -Z (back), South = +Z (front), East = +X, West = -X.
local function grayboxRoom(roomId: string, cf: CFrame): Model
	local model = Instance.new("Model")
	local accent = ROLE_COLOR[roomId] or Color3.fromRGB(200, 200, 200)
	local floor = part(model, "Floor", Vector3.new(CELL, 0.4, CELL), cf * CFrame.new(0, -0.2, 0), Color3.fromRGB(120, 112, 105))
	floor.CanCollide = true
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(model, "Post", Vector3.new(0.6, WALL, 0.6), cf * CFrame.new(sx * 2.7, WALL / 2, sz * 2.7), Color3.fromRGB(80, 74, 70))
		end
	end
	local walls = {
		Door_North = CFrame.new(0, WALL / 2, -2.85),
		Door_South = CFrame.new(0, WALL / 2, 2.85),
		Door_East = CFrame.new(2.85, WALL / 2, 0) * CFrame.Angles(0, math.rad(90), 0),
		Door_West = CFrame.new(-2.85, WALL / 2, 0) * CFrame.Angles(0, math.rad(90), 0),
	}
	for name, offset in walls do
		part(model, name, Vector3.new(4.8, WALL - 0.5, 0.3), cf * offset, Color3.fromRGB(150, 140, 130))
	end
	if roomId == "SlimeNest" then
		part(model, "Prop", Vector3.new(2.2, 2.2, 2.2), cf * CFrame.new(0, 1.1, 0), accent, nil, Enum.PartType.Ball)
	elseif roomId == "SpikeHall" then
		for ix = -1, 1 do
			for iz = -1, 1 do
				part(
					model,
					"Prop",
					Vector3.new(1.6, 0.9, 0.9),
					cf * CFrame.new(ix * 1.4, 0.8, iz * 1.4) * CFrame.Angles(0, 0, math.rad(90)),
					accent,
					Enum.Material.Metal,
					Enum.PartType.Cylinder
				)
			end
		end
	elseif roomId == "GuardRoom" then
		part(model, "Prop", Vector3.new(1.6, 3.2, 1.6), cf * CFrame.new(0, 1.6, 0), accent)
		part(model, "Prop", Vector3.new(0.3, 2, 1.6), cf * CFrame.new(1.2, 1.8, 0), Color3.fromRGB(230, 230, 240))
	elseif roomId == "TreasureRoom" then
		part(model, "Prop", Vector3.new(2.6, 1.4, 1.8), cf * CFrame.new(0, 0.7, 0), Color3.fromRGB(120, 80, 40), Enum.Material.Wood)
		part(model, "Prop", Vector3.new(2.7, 0.5, 1.9), cf * CFrame.new(0, 1.65, 0), accent, Enum.Material.Metal)
	end
	return model
end

local function buildBase(plot)
	local cf = plot.Anchor
	local base = Instance.new("Model")
	base.Name = "Base"
	local width, depth = Grid.Columns * CELL, Grid.Rows * CELL
	-- Grid (z -12..12) plus a 10-stud walkway and margins.
	local slab = part(base, "Floor", Vector3.new(width + 4, 1, depth + 24), cf * CFrame.new(0, -0.5, 5), Color3.fromRGB(70, 66, 74), Enum.Material.Slate)
	slab.CanCollide = true
	local lineColor = Color3.fromRGB(95, 90, 100)
	for i = 0, Grid.Columns do
		part(base, "GridLine", Vector3.new(0.15, 0.05, depth), cf * CFrame.new(-width / 2 + i * CELL, 0.03, 0), lineColor).CanQuery = false
	end
	for i = 0, Grid.Rows do
		part(base, "GridLine", Vector3.new(width, 0.05, 0.15), cf * CFrame.new(0, 0.03, -depth / 2 + i * CELL), lineColor).CanQuery = false
	end

	local entranceCf = cf * CFrame.new(PlotGeometry.CellLocal(Grid.EntranceCell.Column, Grid.EntranceCell.Row))
	local template = art("Rooms", "Entrance")
	if template and template:IsA("Model") then
		local clone = template:Clone()
		clone.Name = "Entrance"
		clone:PivotTo(entranceCf)
		clone.Parent = base
	else
		local arch = Instance.new("Model")
		arch.Name = "Entrance"
		local stone = Color3.fromRGB(140, 130, 120)
		part(arch, "PillarL", Vector3.new(0.8, WALL, 0.8), entranceCf * CFrame.new(-2.2, WALL / 2, CELL / 2), stone)
		part(arch, "PillarR", Vector3.new(0.8, WALL, 0.8), entranceCf * CFrame.new(2.2, WALL / 2, CELL / 2), stone)
		part(arch, "Lintel", Vector3.new(5.2, 0.8, 0.8), entranceCf * CFrame.new(0, WALL + 0.4, CELL / 2), stone)
		arch.Parent = base
	end

	-- Cell tiles, one per grid cell (Base.Cells.<"c,r">): the client picks cells by
	-- raycasting them and reads their pivots for paths, overlays and ghosts, so it
	-- needs no grid maths. Attributes CellKey, Column, Row, Placeable (false on the
	-- entrance). Persistent, so every client always has every plot's tiles.
	local cells = Instance.new("Model")
	cells.Name = "Cells"
	cells.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local tileArt = art("Rooms", "EmptyCellTile")
	for column = 1, Grid.Columns do
		for row = 1, Grid.Rows do
			local key = Route.Key(column, row)
			local cellCf = cf * CFrame.new(PlotGeometry.CellLocal(column, row))
			local tile
			if tileArt and tileArt:IsA("Model") then
				tile = tileArt:Clone()
				tile:PivotTo(cellCf)
				for _, d in tile:GetDescendants() do
					if d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = false
						d.CanTouch = false
						d.CanQuery = true
						if d ~= tile.PrimaryPart then
							d.CFrame = d.CFrame + cellCf.UpVector * TILE_LIFT
							d:SetAttribute("TileT", d.Transparency) -- restored when the cell empties
						end
					end
				end
			else
				tile = part(cells, key, Vector3.new(CELL, 0.05, CELL), cellCf, Color3.fromRGB(70, 66, 74))
				tile.Transparency = 1
				tile.CanTouch = false
			end
			tile.Name = key
			tile:SetAttribute("CellKey", key)
			tile:SetAttribute("Column", column)
			tile:SetAttribute("Row", row)
			tile:SetAttribute("Placeable", key ~= entranceKey)
			tile.Parent = cells
		end
	end
	-- Where visitors appear (one cell in front of the entrance): the path's first point.
	local spawn = part(cells, "VisitorSpawn", Vector3.new(0.2, 0.2, 0.2), cf * CFrame.new(PlotGeometry.SpawnLocal()), Color3.new(1, 1, 1))
	spawn.Transparency = 1
	spawn.CanQuery = false
	spawn.CanTouch = false
	cells.Parent = base
	plot.Cells = cells

	-- Owner sign on a post in front of the plot.
	part(base, "SignPost", Vector3.new(0.4, 3, 0.4), cf * CFrame.new(0, 1.5, 17), Color3.fromRGB(90, 70, 50)).CanQuery = false
	local anchor = part(base, "Sign", Vector3.new(0.2, 0.2, 0.2), cf * CFrame.new(0, 3.3, 17), Color3.fromRGB(90, 70, 50))
	anchor.Transparency = 1
	anchor.CanQuery = false
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(6, 1) -- studs, so the sign does not grow with the camera or overlap from above
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	gui.Adornee = anchor
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(35, 30, 40)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = "Free plot"
	label.Parent = gui
	plot.Sign = label
	base.Parent = plot.Model
end

-- Shows tile art only on empty cells (a placed room or the entrance covers it).
local function showTiles(plot, occupied: { [string]: any })
	for _, tile in plot.Cells:GetChildren() do
		local key = tile:GetAttribute("CellKey")
		if key then
			local shown = key ~= entranceKey and occupied[key] == nil
			for _, d in tile:GetDescendants() do
				local t = d:GetAttribute("TileT")
				if t ~= nil and d:IsA("BasePart") then
					d.Transparency = if shown then t else 1
				end
			end
		end
	end
end

local function clearRooms(plot)
	for _, child in plot.Model.Rooms:GetChildren() do
		child:Destroy()
	end
	showTiles(plot, {})
end

local function resetPlot(plot)
	clearRooms(plot)
	local m = plot.Model
	m:SetAttribute("OwnerUserId", 0)
	m:SetAttribute("Route", "")
	m:SetAttribute("State", "Idle")
	for _, name in VISITOR_ATTRS do
		m:SetAttribute(name, nil)
	end
	plot.Sign.Text = "Free plot"
	plot.Owner = nil
end

local function teleport(player: Player)
	local plot = byPlayer[player]
	local character = player.Character
	if plot and character and character:FindFirstChild("HumanoidRootPart") then
		local pos = (plot.Anchor * CFrame.new(9, 3, 22)).Position -- front walkway, beside the owner sign so it is not blocked
		local target = (plot.Anchor * CFrame.new(0, 3, 0)).Position
		character:PivotTo(CFrame.lookAt(pos, target))
	end
end

function PlotService.GetPlot(player: Player)
	local plot = byPlayer[player]
	return plot and plot.Model
end

function PlotService.ByIndex(index: number)
	local plot = plots[index]
	return plot and plot.Model
end

-- Occupied plots: iterate (player, plotModel).
function PlotService.Owned()
	local out = {}
	for player, plot in byPlayer do
		out[player] = plot.Model
	end
	return out
end

-- Level, Rarity and defender health attributes (rarity and Stout Defenders
-- included, Monster Den boost not); defenders reset to full if `resetHealth`.
local function setLevelAttrs(model: Instance, instance, profile, resetHealth: boolean)
	model:SetAttribute("Level", instance.Level)
	model:SetAttribute("Rarity", instance.Rarity or "Common")
	local health =
		EncounterSim.DefenderHealth(instance.Id, instance.Level, instance.Rarity, Progression.DefenderHealthBonus(profile))
	if health then
		model:SetAttribute("DefenderMaxHealth", health)
		if resetHealth then
			model:SetAttribute("DefenderHealth", health)
		end
	end
end

-- Re-syncs Level/defender attributes of existing room models (after an upgrade or
-- an encounter). Defender health is left alone while an encounter runs.
function PlotService.RefreshRoomAttrs(player: Player)
	local plot = byPlayer[player]
	local profile = ProfileService.Get(player)
	if plot == nil or profile == nil then
		return
	end
	local idle = plot.Model:GetAttribute("State") ~= "Encounter"
	for _, model in plot.Model.Rooms:GetChildren() do
		local instance = profile.Rooms[model:GetAttribute("InstanceId")]
		if instance then
			setLevelAttrs(model, instance, profile, idle)
		end
	end
end

-- Rebuilds the room models and the Route attribute from profile.Layout.
function PlotService.Render(player: Player)
	local plot = byPlayer[player]
	local profile = ProfileService.Get(player)
	if plot == nil or profile == nil then
		return
	end
	clearRooms(plot)
	local ok, routeCells, cells = LayoutRules.Validate(profile, profile.Layout)
	if not ok then
		routeCells, cells = {}, {}
	end
	local order = {}
	for i, key in routeCells do
		order[key] = i
	end
	for key, roomId in cells do
		local column, row = Route.Parse(key)
		if column and row then
			local instanceId = profile.Layout[key]
			local instance = profile.Rooms[instanceId]
			local cf = plot.Anchor * CFrame.new(PlotGeometry.CellLocal(column, row))
			local template = art("Rooms", roomId)
			local model
			if template and template:IsA("Model") then
				model = template:Clone()
				model:PivotTo(cf)
			else
				model = grayboxRoom(roomId, cf)
			end
			model.Name = key
			model:SetAttribute("RoomId", roomId)
			model:SetAttribute("InstanceId", instanceId)
			model:SetAttribute("RouteIndex", order[key] or 0)
			setLevelAttrs(model, instance, profile, true)
			model.Parent = plot.Model.Rooms
		end
	end
	showTiles(plot, cells)
	plot.Model:SetAttribute("Route", table.concat(routeCells, "|"))
end

local function assign(player: Player)
	if byPlayer[player] then
		return
	end
	for _, plot in plots do
		if plot.Owner == nil then
			plot.Owner = player
			byPlayer[player] = plot
			plot.Model:SetAttribute("OwnerUserId", player.UserId)
			plot.Model:SetAttribute("State", "Idle")
			plot.Sign.Text = player.DisplayName .. "'s Dungeon"
			PlotService.Render(player)
			teleport(player)
			return
		end
	end
	player:Kick("All dungeons on this server are taken right now. Please try again or join another server.")
end

local function release(player: Player)
	local plot = byPlayer[player]
	if plot then
		byPlayer[player] = nil
		resetPlot(plot)
	end
end

function PlotService.Init()
	local folder = Instance.new("Folder")
	folder.Name = "Plots"
	for index = 1, Balance.Server.MaxPlots do
		local model = Instance.new("Model")
		model.Name = "Plot" .. index
		model:SetAttribute("Index", index)
		local roomsFolder = Instance.new("Folder")
		roomsFolder.Name = "Rooms"
		roomsFolder.Parent = model
		local plot = { Index = index, Model = model, Anchor = anchorFor(index) }
		buildBase(plot)
		resetPlot(plot)
		model.Parent = folder
		plots[index] = plot
	end
	folder.Parent = workspace
end

function PlotService.Start()
	ProfileService.Loaded:Connect(assign)
	ProfileService.Left:Connect(release)
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart", 10)
			task.defer(teleport, player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return PlotService
