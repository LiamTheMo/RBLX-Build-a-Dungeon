-- A plot's server-built cell tiles (Plot.Base.Cells.<"c,r">, attributes CellKey,
-- Column, Row, Placeable) and its VisitorSpawn marker. The client picks cells by
-- raycasting the tiles and places things at their pivots, so it has no grid maths.
local Cells = {}

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include

-- The plot's Cells model, nil if it has not replicated yet. Never yields.
function Cells.Folder(plot: Instance): Instance?
	local base = plot:FindFirstChild("Base")
	return base and base:FindFirstChild("Cells")
end

-- Yields (up to ~10 s) until the plot's Cells model exists.
function Cells.WaitFolder(plot: Instance): Instance?
	local base = plot:WaitForChild("Base", 10)
	return base and base:WaitForChild("Cells", 10)
end

function Cells.Tile(plot: Instance, key: string): Instance?
	local folder = Cells.Folder(plot)
	local tile = folder and folder:FindFirstChild(key)
	return if tile and tile:GetAttribute("CellKey") == key then tile else nil
end

-- World CFrame of a cell's centre on the floor top, raised by `y` studs.
function Cells.World(plot: Instance, key: string, y: number?): CFrame?
	local tile = Cells.Tile(plot, key)
	if not tile or not tile:IsA("PVInstance") then
		return nil
	end
	return (tile :: PVInstance):GetPivot() * CFrame.new(0, y or 0, 0)
end

-- Where visitors appear (one cell in front of the entrance).
function Cells.Spawn(plot: Instance): CFrame?
	local folder = Cells.Folder(plot)
	local spawn = folder and folder:FindFirstChild("VisitorSpawn")
	return if spawn and spawn:IsA("BasePart") then spawn.CFrame else nil
end

-- Cell key under a viewport point, or nil off the grid.
function Cells.KeyAt(plot: Instance, viewportPos: Vector2): string?
	local folder = Cells.Folder(plot)
	if not folder then
		return nil
	end
	local ray = workspace.CurrentCamera:ViewportPointToRay(viewportPos.X, viewportPos.Y)
	params.FilterDescendantsInstances = { folder }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	local node: Instance? = hit and hit.Instance
	while node and node ~= folder do
		local key = node:GetAttribute("CellKey")
		if type(key) == "string" then
			return key
		end
		node = node.Parent
	end
	return nil
end

-- The visible parts of a tile (for hiding tile art locally under draft rooms).
function Cells.Parts(tile: Instance): { BasePart }
	local out = {}
	if tile:IsA("BasePart") then
		table.insert(out, tile)
	end
	for _, d in tile:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

return Cells
