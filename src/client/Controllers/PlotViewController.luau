-- Local rendering of every plot: the visitor, defenders, traps, doorways and
-- end-of-encounter effects. Everything here is cosmetic and driven by the
-- replicated plot attributes and EncounterFx events; it never decides outcomes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Balance = require(Shared.Definitions.Balance)
local Grid = require(Shared.Definitions.Grid)
local PlotGeometry = require(Shared.Rules.PlotGeometry)
local Route = require(Shared.Rules.Route)
local Rooms = require(Shared.Definitions.Rooms)
local SoundIds = require(Shared.UI.SoundIds)

local Ui = script.Parent.Parent.Ui
local Doors = require(Ui.Doors)
local Net = require(Ui.Net)
local Settings = require(Ui.Settings)
local Sound = require(Ui.Sound)
local Theme = require(Ui.Theme)

local View = {}

local DEFENDER_ART = { SlimeNest = "Slime", GuardRoom = "Guard", RestlessCrypt = "Skeleton" }
local RARITY_COLOR = {
	Uncommon = Theme.Success,
	Rare = Color3.fromRGB(90, 160, 255),
	Mythic = Color3.fromRGB(190, 110, 255),
}
local SPORE_GREEN = Color3.fromRGB(150, 220, 60)
local BOX_COLOR = { Dungeon = Theme.Gold, Rare = Color3.fromRGB(90, 160, 255) }
local JOINTS = { "Neck", "LeftShoulder", "RightShoulder", "LeftHip", "RightHip" }
local MAX_SPEED = 8 -- studs/s the displayed visitor may chase the replicated progress
local FX_CAP = 6
local COIN_CAP = 30

local views: { [Instance]: any } = {}
local fxFolder: Folder
local fxText, fxCoins, fxDrops, fxRings = 0, 0, 0, 0
local pulsing: { [Instance]: boolean } = {}

-- SoundIds slot played through the Ui helper (a missing id stays silent).
local function play(name: string)
	Sound.Play(name)
end

local function make(class: string, props: { [string]: any }, parent: Instance?): any
	local i = Instance.new(class)
	for k, v in props do
		(i :: any)[k] = v
	end
	i.Parent = parent
	return i
end

-- Models -----------------------------------------------------------------

local function bodyPart(parent: Instance, name: string, size: Vector3, color: Color3): Part
	return make("Part", {
		Name = name,
		Size = size,
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Massless = true,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
	}, parent)
end

local function motor(name: string, p0: BasePart, p1: BasePart, c0: CFrame, c1: CFrame)
	make("Motor6D", { Name = name, Part0 = p0, Part1 = p1, C0 = c0, C1 = c1 }, p1)
end

local function newRoot(model: Model): Part
	local root = bodyPart(model, "Root", Vector3.new(0.4, 0.2, 0.4), Color3.new(1, 1, 1))
	root.Anchored = true
	root.Transparency = 1
	model.PrimaryPart = root
	return root
end

-- Blocky graybox person (about 2.1 studs tall) with the contract's joint names.
local function grayboxPerson(color: Color3, k: number): Model
	local model = make("Model", { Name = "Graybox" })
	local root = newRoot(model)
	local torso = bodyPart(model, "Torso", Vector3.new(0.7, 0.8, 0.4) * k, color)
	motor("RootJoint", root, torso, CFrame.new(0, 1.2 * k, 0), CFrame.new())
	local head = bodyPart(model, "Head", Vector3.new(0.5, 0.5, 0.5) * k, Color3.fromRGB(240, 205, 165))
	motor("Neck", torso, head, CFrame.new(0, 0.4 * k, 0), CFrame.new(0, -0.25 * k, 0))
	local armSize, legSize = Vector3.new(0.3, 0.8, 0.3) * k, Vector3.new(0.3, 0.8, 0.3) * k
	local armColor, legColor = color:Lerp(Color3.new(1, 1, 1), 0.2), color:Lerp(Color3.new(0, 0, 0), 0.4)
	for _, side in { { "Left", -1 }, { "Right", 1 } } do
		local arm = bodyPart(model, side[1] .. "Arm", armSize, armColor)
		motor(side[1] .. "Shoulder", torso, arm, CFrame.new(side[2] * 0.5 * k, 0.35 * k, 0), CFrame.new(0, 0.35 * k, 0))
		local leg = bodyPart(model, side[1] .. "Leg", legSize, legColor)
		motor(side[1] .. "Hip", torso, leg, CFrame.new(side[2] * 0.17 * k, -0.4 * k, 0), CFrame.new(0, 0.4 * k, 0))
	end
	return model
end

local function grayboxSlime(): Model
	local model = make("Model", { Name = "GrayboxSlime" })
	local root = newRoot(model)
	local body = bodyPart(model, "Body", Vector3.new(1.6, 1.2, 1.6), Color3.fromRGB(90, 210, 110))
	body.Shape = Enum.PartType.Ball
	body.Transparency = 0.15
	motor("Body", root, body, CFrame.new(0, 0.6, 0), CFrame.new())
	for _, x in { -0.3, 0.3 } do
		local eye = bodyPart(model, "Eye", Vector3.new(0.25, 0.25, 0.25), Color3.fromRGB(20, 20, 30))
		motor("Eye", body, eye, CFrame.new(x, 0.15, -0.7), CFrame.new())
	end
	return model
end

local function characterTemplate(name: string): Model?
	local art = ReplicatedStorage:FindFirstChild("Art")
	local chars = art and art:FindFirstChild("Characters")
	local m = chars and chars:FindFirstChild(name)
	if m and m:IsA("Model") and (m.PrimaryPart or m:FindFirstChild("Root")) then
		return m
	end
	return nil
end

local GRAYBOX = {
	Scout = function()
		return grayboxPerson(Color3.fromRGB(110, 175, 120), 0.95)
	end,
	Cleric = function()
		return grayboxPerson(Color3.fromRGB(235, 228, 200), 1.05)
	end,
	Skeleton = function()
		return grayboxPerson(Color3.fromRGB(225, 220, 200), 1)
	end,
	Practice = function()
		return grayboxPerson(Color3.fromRGB(150, 170, 220), 0.9)
	end,
	Novice = function()
		return grayboxPerson(Color3.fromRGB(110, 140, 220), 1)
	end,
	ArmoredChallenger = function()
		return grayboxPerson(Color3.fromRGB(150, 150, 165), 1.15)
	end,
	Guard = function()
		return grayboxPerson(Color3.fromRGB(70, 100, 170), 1.1)
	end,
	Slime = grayboxSlime,
}

-- An actor wraps a character model with procedural animation state.
local function newActor(name: string)
	local model: Model
	local template = characterTemplate(name)
	if template then
		model = template:Clone()
		if not model.PrimaryPart then
			model.PrimaryPart = model:FindFirstChild("Root") :: BasePart
		end
	else
		model = (GRAYBOX[name] or GRAYBOX.Novice)()
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	model.PrimaryPart.Anchored = true
	model.Parent = fxFolder
	local actor = { Model = model, Joints = {}, Phase = 0, Down = 0, Seed = math.random() * 6.28 }
	for _, j in JOINTS do
		local m = model:FindFirstChild(j, true)
		if m and m:IsA("Motor6D") then
			actor.Joints[j] = m
		end
	end
	return actor
end

local function flash(actor, color: Color3, duration: number)
	if not actor then
		return
	end
	if not actor.Highlight then
		actor.Highlight = make("Highlight", {
			Adornee = actor.Model,
			FillTransparency = 0.35,
			OutlineTransparency = 1,
			Enabled = false,
		}, actor.Model)
	end
	actor.Highlight.FillColor = color
	actor.Highlight.Enabled = true
	actor.FlashUntil = os.clock() + duration
end

local function swing(actor)
	if actor then
		actor.Swing = os.clock()
	end
end

-- Walk cycle and attack swing through Motor6D.Transform; returns the forward lunge.
local function animate(actor, dt: number, moving: boolean, speedScale: number): number
	local j = actor.Joints
	if actor.Highlight and actor.FlashUntil and os.clock() > actor.FlashUntil and not actor.KeepHighlight then
		actor.Highlight.Enabled = false
	end
	local ls, rs, lh, rh = j.LeftShoulder, j.RightShoulder, j.LeftHip, j.RightHip
	if moving then
		actor.Phase += dt * 8 * speedScale
		local s = math.sin(actor.Phase)
		if ls then
			ls.Transform = CFrame.Angles(s * 0.8, 0, 0)
		end
		if rs then
			rs.Transform = CFrame.Angles(-s * 0.8, 0, 0)
		end
		if lh then
			lh.Transform = CFrame.Angles(-s * 0.9, 0, 0)
		end
		if rh then
			rh.Transform = CFrame.Angles(s * 0.9, 0, 0)
		end
	else
		for _, m in { ls, rs, lh, rh } do
			if m then
				m.Transform = m.Transform:Lerp(CFrame.new(), math.min(1, dt * 12))
			end
		end
	end
	local lunge = 0
	if actor.Swing then
		local t = (os.clock() - actor.Swing) / 0.35
		if t >= 1 then
			actor.Swing = nil
		else
			local w = math.sin(math.pi * t)
			if rs then
				rs.Transform = CFrame.Angles(-w * 2, 0, 0)
			end
			lunge = w * 0.6
		end
	end
	return lunge
end

-- Effects (capped) -----------------------------------------------------------

local function floatText(pos: Vector3, text: string, color: Color3)
	if fxText >= FX_CAP then
		return
	end
	fxText += 1
	local anchorPart = make("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		Transparency = 1,
		Size = Vector3.new(0.2, 0.2, 0.2),
		Position = pos,
	}, fxFolder)
	local gui = make("BillboardGui", { Size = UDim2.fromOffset(140, 36), AlwaysOnTop = true, MaxDistance = 150 }, anchorPart)
	local label = make("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = text,
		TextColor3 = color,
		TextStrokeColor3 = Theme.Stroke,
		TextStrokeTransparency = 0.2,
		TextSize = 26,
		FontFace = Theme.HeadingFont,
	}, gui)
	local reduced = Settings.Reduced()
	local info = TweenInfo.new(if reduced then 1 else 1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if not reduced then
		TweenService:Create(anchorPart, info, { Position = pos + Vector3.new(0, 3, 0) }):Play()
	end
	TweenService:Create(label, TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, info.Time - 0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(info.Time + 0.05, function()
		anchorPart:Destroy()
		fxText -= 1
	end)
end

local function coinBurst(pos: Vector3)
	if Settings.Reduced() then
		return
	end
	for _ = 1, 8 do
		if fxCoins >= COIN_CAP then
			return
		end
		fxCoins += 1
		local coin = make("Part", {
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.12, 0.6, 0.6),
			Color = Theme.Gold,
			Material = Enum.Material.Neon,
			CFrame = CFrame.new(pos + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		}, fxFolder)
		local spread = Vector3.new(math.random() * 5 - 2.5, 0, math.random() * 5 - 2.5)
		local up = TweenService:Create(coin, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = pos + Vector3.new(0, 3.5, 0) + spread * 0.5,
		})
		local down = TweenService:Create(coin, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = pos + Vector3.new(0, 0.3, 0) + spread,
			Transparency = 1,
		})
		up.Completed:Once(function()
			down:Play()
		end)
		down.Completed:Once(function()
			coin:Destroy()
			fxCoins -= 1
		end)
		up:Play()
	end
end

-- Temporary invisible anchor for emitters and icons; destroyed after `life` seconds.
local function tempPart(pos: Vector3, life: number): Part
	local p = make("Part", { Anchored = true, CanCollide = false, CanQuery = false, Transparency = 1, Size = Vector3.one * 0.2, Position = pos }, fxFolder)
	task.delay(life, function()
		p:Destroy()
	end)
	return p
end

-- One-shot particle puff (count reduced under reduced motion).
local function puff(pos: Vector3, color: Color3, count: number, speed: number, life: number)
	local p = tempPart(pos, life + 0.5)
	local e = make("ParticleEmitter", {
		Enabled = false,
		Color = ColorSequence.new(color),
		Lifetime = NumberRange.new(life * 0.6, life),
		Speed = NumberRange.new(speed * 0.5, speed),
		SpreadAngle = Vector2.new(180, 180),
		Rate = 0,
		LightEmission = 0.4,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
	}, p)
	e:Emit(if Settings.Reduced() then math.ceil(count / 4) else count)
end

-- Pulse a named part of a room model (art), or flash a temporary ring when the art has none.
local function pulseRoom(model: Model, partName: string, color: Color3, diameter: number)
	local part = model:FindFirstChild(partName, true)
	if part and part:IsA("BasePart") then
		if pulsing[part] or Settings.Reduced() then
			return
		end
		pulsing[part] = true
		local size = part.Size
		local t = TweenService:Create(part, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { Size = size * 1.25 })
		t.Completed:Once(function()
			part.Size = size
			pulsing[part] = nil
		end)
		t:Play()
		return
	end
	if fxRings >= 6 then
		return
	end
	fxRings += 1
	local ring = make("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 0.4,
		Size = Vector3.new(0.1, diameter * 0.6, diameter * 0.6),
		CFrame = model:GetPivot() * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.pi / 2),
	}, fxFolder)
	local info = TweenInfo.new(if Settings.Reduced() then 0.01 else 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local goal = { Transparency = 1 }
	if not Settings.Reduced() then
		goal.Size = Vector3.new(0.1, diameter, diameter)
	end
	local t = TweenService:Create(ring, info, goal)
	t.Completed:Once(function()
		ring:Destroy()
		fxRings -= 1
	end)
	t:Play()
end

-- Floating drop pill ("Dungeon Box", "Blueprint: Guard Room") that rises and fades.
local function dropPill(pos: Vector3, text: string, color: Color3, delay: number)
	if fxDrops >= 6 then
		return
	end
	fxDrops += 1
	local reduced = Settings.Reduced()
	local anchor = tempPart(pos, delay + 2.2)
	local gui = make("BillboardGui", { Size = UDim2.fromOffset(190, 32), AlwaysOnTop = true, MaxDistance = 150, Enabled = false }, anchor)
	local pill = make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.BgDeep,
		Text = text,
		TextColor3 = Theme.TextPrimary,
		TextSize = 16,
		FontFace = Theme.HeadingFont,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, pill)
	local stroke = make("UIStroke", { Color = color, Thickness = 3 }, pill)
	task.delay(delay, function()
		if not anchor.Parent then
			fxDrops -= 1
			return
		end
		gui.Enabled = true
		if not reduced then
			TweenService:Create(anchor, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = pos + Vector3.new(0, 2.5, 0) }):Play()
		end
		task.delay(1.6, function()
			TweenService:Create(pill, TweenInfo.new(0.4), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
			TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
			task.delay(0.45, function()
				fxDrops -= 1
				anchor:Destroy()
			end)
		end)
	end)
end

-- Paths ----------------------------------------------------------------------

local function buildPath(plot: Instance)
	local entrance = Grid.EntranceCell
	local pts = { PlotGeometry.SpawnLocal(), PlotGeometry.CellLocal(entrance.Column, entrance.Row) }
	for _, key in string.split((plot:GetAttribute("Route") :: string) or "", "|") do
		local c, r = Route.Parse(key)
		if c and r then
			table.insert(pts, PlotGeometry.CellLocal(c, r))
		end
	end
	local cum = { 0 }
	for i = 2, #pts do
		cum[i] = cum[i - 1] + (pts[i] - pts[i - 1]).Magnitude
	end
	return { Points = pts, Cum = cum }
end

-- Returns local position and direction at distance d along the path.
local function sample(path, d: number): (Vector3, Vector3)
	local pts, cum = path.Points, path.Cum
	d = math.clamp(d, 0, cum[#cum])
	for i = 2, #pts do
		if d <= cum[i] or i == #pts then
			local seg = pts[i] - pts[i - 1]
			local len = math.max(seg.Magnitude, 1e-3)
			return pts[i - 1] + seg * ((d - cum[i - 1]) / len), seg / len
		end
	end
	return pts[1], Vector3.new(0, 0, -1)
end

-- Per-plot view ------------------------------------------------------------------

local function destroyVisitor(view)
	if view.Visitor then
		view.Visitor.Model:Destroy()
		view.Visitor = nil
		view.VisitorId = nil
		view.Chase = nil
	end
end

local function destroyDefender(def)
	def.Actor.Model:Destroy()
end

local function destroyTrap(trap)
	if trap.Fallback then
		trap.Fallback:Destroy()
	end
end

local function newVisitor(view, id: string)
	local actor = newActor(id)
	local gui = make("BillboardGui", {
		Adornee = actor.Model.PrimaryPart,
		Size = UDim2.fromOffset(64, 10),
		StudsOffset = Vector3.new(0, 3, 0),
		MaxDistance = 150,
	}, actor.Model)
	local bg = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Stroke, BorderSizePixel = 0 }, gui)
	local fill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Success, BorderSizePixel = 0 }, bg)
	for _, f in { bg, fill } do
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
	end
	actor.HealthFill = fill
	view.Visitor, view.VisitorId = actor, id
	view.Chase = nil
end

local function clearDeco(view, m: Instance)
	local d = view.Deco[m]
	if d then
		d.Folder:Destroy()
		view.Deco[m] = nil
	end
end

-- Subtle rarity mark: a thin glowing frame on the floor edge plus a small badge
-- (Common none). Mythic also sparkles unless motion is reduced.
local function applyRarity(view, m: Model)
	local rarity = m:GetAttribute("Rarity")
	local d = view.Deco[m]
	if d and d.Rarity == rarity then
		d.Sparkle.Enabled = d.Mythic and not Settings.Reduced()
		return
	end
	clearDeco(view, m)
	local color = RARITY_COLOR[rarity]
	if not color then
		return
	end
	local folder = make("Folder", { Name = "Rarity" }, fxFolder)
	local cf, half = m:GetPivot(), 2.9
	local front
	for _, side in { { 0, half, 5.8, 0.12 }, { 0, -half, 5.8, 0.12 }, { half, 0, 0.12, 5.8 }, { -half, 0, 0.12, 5.8 } } do
		local bar = make("Part", {
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Material = Enum.Material.Neon,
			Color = color,
			Transparency = 0.45,
			Size = Vector3.new(side[3], 0.12, side[4]),
			CFrame = cf * CFrame.new(side[1], 0.15, side[2]),
		}, folder)
		front = front or bar
	end
	local badge = make("BillboardGui", { Adornee = front, Size = UDim2.fromOffset(96, 24), StudsOffset = Vector3.new(0, 1.6, 0), MaxDistance = 70 }, folder)
	local pill = make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.BgDeep,
		Text = string.upper(rarity),
		TextColor3 = color,
		TextSize = 14,
		FontFace = Theme.HeadingFont,
	}, badge)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, pill)
	make("UIStroke", { Color = color, Thickness = 2 }, pill)
	local mythic = rarity == "Mythic"
	local sparkle = make("ParticleEmitter", {
		Enabled = mythic and not Settings.Reduced(),
		Color = ColorSequence.new(color),
		Rate = 4,
		Lifetime = NumberRange.new(1, 1.6),
		Speed = NumberRange.new(0.5, 1.5),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 0.6,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
	}, front)
	view.Deco[m] = { Folder = folder, Rarity = rarity, Mythic = mythic, Sparkle = sparkle }
end

local function roomAt(view, index: number): Model?
	local rooms = view.Plot:FindFirstChild("Rooms")
	for _, m in if rooms then rooms:GetChildren() else {} do
		if m:GetAttribute("RouteIndex") == index then
			return m :: Model
		end
	end
	return nil
end

-- Rescan Rooms: defender actors, trap parts and doorways.
local function refreshRooms(view)
	local plot = view.Plot
	local rooms = plot:FindFirstChild("Rooms")
	local seen = {}
	local occupied = {}
	if rooms then
		for _, m in rooms:GetChildren() do
			occupied[m.Name] = true
		end
		for _, m in rooms:GetChildren() do
			seen[m] = true
			local roomId = m:GetAttribute("RoomId")
			local c, r = Route.Parse(m.Name)
			if c and r then
				Doors.Apply(m, c, r, function(k)
					return occupied[k] == true
				end)
			end
			applyRarity(view, m)
			if DEFENDER_ART[roomId] and not view.Defenders[m] then
				view.Defenders[m] = { Actor = newActor(DEFENDER_ART[roomId]), Model = m }
			elseif roomId == "SpikeHall" and not view.Traps[m] then
				local parts = {}
				for _, d in m:GetDescendants() do
					if d.Name == "Spike" and d:IsA("BasePart") then
						table.insert(parts, { Part = d, Rest = d.CFrame, Color = d.Color })
					end
				end
				local trap = { Model = m, Parts = parts }
				if #parts == 0 then
					-- Code-made plate with 9 spikes, used only when the art has none.
					local folder = make("Folder", { Name = "FallbackSpikes" }, fxFolder)
					local origin = m:GetPivot() * CFrame.new(0, 0.1, 0)
					make("Part", { Anchored = true, CanCollide = false, CanQuery = false, Size = Vector3.new(4.4, 0.2, 4.4), Color = Color3.fromRGB(90, 80, 100), CFrame = origin }, folder)
					for x = -1, 1 do
						for z = -1, 1 do
							local s = make("Part", {
								Name = "Spike",
								Anchored = true,
								CanCollide = false,
								CanQuery = false,
								Size = Vector3.new(0.4, 1, 0.4),
								Color = Color3.fromRGB(200, 200, 210),
								CFrame = origin * CFrame.new(x * 1.3, 0.1, z * 1.3),
							}, folder)
							table.insert(parts, { Part = s, Rest = s.CFrame, Color = s.Color })
						end
					end
					trap.Fallback = folder
				end
				view.Traps[m] = trap
			end
		end
	end
	for m in view.Deco do
		if not seen[m] or not m.Parent then
			clearDeco(view, m)
		end
	end
	for m, def in view.Defenders do
		if not seen[m] or not m.Parent then
			destroyDefender(def)
			view.Defenders[m] = nil
		end
	end
	for m, trap in view.Traps do
		if not seen[m] or not m.Parent then
			destroyTrap(trap)
			view.Traps[m] = nil
		end
	end
end

local function defenderAt(view, index: number)
	for m, def in view.Defenders do
		if m:GetAttribute("RouteIndex") == index then
			return def
		end
	end
	return nil
end

local function trapAt(view, index: number)
	for m, trap in view.Traps do
		if m:GetAttribute("RouteIndex") == index then
			return trap
		end
	end
	return nil
end

local function spotCF(view, def, anchor: CFrame): CFrame
	local spot = def.Model:FindFirstChild("DefenderSpot", true)
	local facing = anchor.Rotation * CFrame.Angles(0, math.pi, 0) -- toward the front, where visitors come from
	if spot and spot:IsA("Attachment") then
		return CFrame.new(spot.WorldPosition) * facing
	end
	return CFrame.new(def.Model:GetPivot().Position + anchor.LookVector * -1.8) * facing
end

local function stepView(view, dt: number)
	local plot = view.Plot
	if not plot.Parent then
		return
	end
	local anchor = plot:GetPivot()
	local reduced = Settings.Reduced()
	local state = plot:GetAttribute("State")
	local inEncounter = state == "Encounter"
	if not inEncounter then
		view.EncStart = nil
	end

	-- Visitor
	local id = plot:GetAttribute("VisitorId")
	if type(id) ~= "string" or id == "" then
		destroyVisitor(view)
	else
		if view.VisitorId ~= id then
			destroyVisitor(view)
			newVisitor(view, id)
		end
		local v = view.Visitor
		local routeStr = plot:GetAttribute("Route") or ""
		if view.RouteStr ~= routeStr or not view.Path then
			view.RouteStr = routeStr
			view.Path = buildPath(plot)
		end
		local target = (plot:GetAttribute("VisitorProgress") or 0) + Grid.CellSize
		local chase = view.Chase or 0
		local step = math.clamp(target - chase, -MAX_SPEED * dt, MAX_SPEED * dt)
		if math.abs(target - chase) > 3 * Grid.CellSize then
			step = target - chase
		end
		view.Chase = chase + step
		local lp, dir = sample(view.Path, view.Chase)
		local worldPos = anchor:PointToWorldSpace(lp)
		local worldDir = anchor:VectorToWorldSpace(Vector3.new(dir.X, 0, dir.Z))
		if worldDir.Magnitude < 1e-3 then
			worldDir = anchor.LookVector * -1
		end
		local slowed = plot:GetAttribute("VisitorSlowed") == true
		local moving = math.abs(step) / math.max(dt, 1e-3) > 0.4
		local lunge = animate(v, dt, moving, if slowed then 0.5 else 1)
		local look = CFrame.lookAt(worldPos, worldPos + worldDir)
		v.Model:PivotTo(look * CFrame.new(0, 0, -lunge))
		view.VisitorPos = worldPos
		local tint = if plot:GetAttribute("VisitorSpored") == true then SPORE_GREEN elseif slowed then Theme.Success else nil
		v.KeepHighlight = tint ~= nil
		if tint and v.Highlight and not (v.FlashUntil and os.clock() < v.FlashUntil) then
			v.Highlight.FillColor = tint
			v.Highlight.FillTransparency = 0.65
			v.Highlight.Enabled = true
		elseif v.Highlight then
			v.Highlight.FillTransparency = 0.35
		end
		if tint and not v.Highlight then
			flash(v, tint, 0)
			v.Highlight.FillTransparency = 0.65
		end
		local max = math.max(plot:GetAttribute("VisitorMaxHealth") or 1, 1)
		-- Cleric HealGlow: green motes while it walks and mends (never while duelling).
		local healing = id == "Cleric" and inEncounter and (plot:GetAttribute("VisitorFighting") or 0) == 0 and (plot:GetAttribute("VisitorHealth") or max) < max
		if not v.HealFx then
			v.HealFx = make("ParticleEmitter", {
				Enabled = false,
				Color = ColorSequence.new(Theme.Success),
				Texture = "rbxasset://textures/particles/sparkles_main.dds",
				Lifetime = NumberRange.new(0.8, 1.2),
				Speed = NumberRange.new(1, 2),
				EmissionDirection = Enum.NormalId.Top,
				SpreadAngle = Vector2.new(25, 25),
				LightEmission = 0.7,
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
			}, v.Model.PrimaryPart)
		end
		v.HealFx.Rate = if reduced then 2 else 8
		if healing and not v.Healing then
			play("Heal")
		end
		v.Healing = healing
		v.HealFx.Enabled = healing
		local frac = math.clamp((plot:GetAttribute("VisitorHealth") or max) / max, 0, 1)
		v.HealthFill.Size = UDim2.fromScale(frac, 1)
		v.HealthFill.BackgroundColor3 = if frac < 0.3 then Theme.Danger else Theme.Success
	end

	-- Defenders
	for m, def in view.Defenders do
		local a = def.Actor
		local hp = m:GetAttribute("DefenderHealth")
		local down = (hp ~= nil and hp <= 0) or (def.Forced and inEncounter)
		if not inEncounter then
			def.Forced = false
		end
		local goal = if down then 1 else 0
		local rate = if a.RiseUntil and os.clock() < a.RiseUntil then 1.2 else 4 -- Rise stands up slowly
		a.Down = if reduced then goal else a.Down + math.clamp(goal - a.Down, -dt * rate, dt * rate)
		-- DenBoost glow while the boosted defender is in the encounter.
		local boosted = def.Boosted == true and inEncounter
		if not inEncounter then
			def.Boosted = false
		end
		a.KeepHighlight = boosted
		if boosted and not a.Highlight then
			flash(a, Theme.Warning, 0)
		end
		if a.Highlight then
			if boosted and not (a.FlashUntil and os.clock() < a.FlashUntil) then
				a.Highlight.FillColor, a.Highlight.FillTransparency, a.Highlight.Enabled = Theme.Warning, 0.7, true
			elseif a.FlashUntil and os.clock() < a.FlashUntil then
				a.Highlight.FillTransparency = 0.35
			end
		end
		local lunge = animate(a, dt, false, 1)
		local bob = if reduced or down then 0 else math.sin(os.clock() * 2 + a.Seed) * 0.1
		local cf = spotCF(view, def, anchor)
		a.Model:PivotTo(cf * CFrame.new(0, bob - a.Down * 0.3, -lunge) * CFrame.Angles(-a.Down * 1.4, 0, 0))
	end

	-- Traps: telegraph from the fixed cycle, strike from Trap events.
	local cfg = Balance.Rooms.SpikeHall
	local telegraph = false
	if view.EncStart then
		telegraph = (os.clock() - view.EncStart) % cfg.Cycle < cfg.Telegraph
	end
	for _, trap in view.Traps do
		local raise = 0
		local struck = false
		if trap.Strike then
			local t = (os.clock() - trap.Strike) / 0.3
			if t >= 1 then
				trap.Strike = nil
			else
				struck = true
				raise = if reduced then 0 else math.sin(math.pi * t) * 0.7
			end
		end
		local color = if struck and reduced then Theme.Warning elseif telegraph then Theme.Danger else nil
		local tag = if color then tostring(color) else ""
		for _, p in trap.Parts do
			if p.Part.Parent then
				if raise ~= 0 or trap.LastRaise ~= 0 then
					p.Part.CFrame = p.Rest * CFrame.new(0, raise, 0)
				end
				if trap.Tag ~= tag then
					p.Part.Color = color or p.Color
				end
			end
		end
		trap.LastRaise = raise
		trap.Tag = tag
	end

	view.Timer += dt
	if view.Timer > 1 then
		view.Timer = 0
		view.Dirty = true
	end
	if view.Dirty then
		view.Dirty = false
		refreshRooms(view)
	end
end

local function addPlot(plot: Instance)
	if not plot:IsA("Model") or views[plot] then
		return
	end
	local view = { Plot = plot, Defenders = {}, Traps = {}, Deco = {}, Timer = 0, Dirty = true }
	views[plot] = view
	plot:GetAttributeChangedSignal("Route"):Connect(function()
		view.Dirty = true
	end)
	local function hookRooms(rooms: Instance)
		rooms.ChildAdded:Connect(function()
			view.Dirty = true
		end)
		rooms.ChildRemoved:Connect(function()
			view.Dirty = true
		end)
	end
	local rooms = plot:FindFirstChild("Rooms")
	if rooms then
		hookRooms(rooms)
	else
		plot.ChildAdded:Connect(function(c)
			if c.Name == "Rooms" then
				hookRooms(c)
				view.Dirty = true
			end
		end)
	end
end

local function removePlot(plot: Instance)
	local view = views[plot]
	if not view then
		return
	end
	destroyVisitor(view)
	for _, d in view.Defenders do
		destroyDefender(d)
	end
	for _, t in view.Traps do
		destroyTrap(t)
	end
	for m in view.Deco do
		clearDeco(view, m)
	end
	views[plot] = nil
end

local function viewByIndex(n: any)
	for plot, view in views do
		if plot:GetAttribute("Index") == n then
			return view
		end
	end
	return nil
end

local function onFx(e: any)
	if type(e) ~= "table" or type(e.Kind) ~= "string" then
		return
	end
	local view = viewByIndex(e.Plot)
	if not view then
		return
	end
	local kind = e.Kind
	local v = view.Visitor
	local index = if type(e.Index) == "number" then e.Index else 0
	if kind == "Spawn" then
		view.EncStart = os.clock()
		play("VisitorArrive")
	elseif kind == "DenBoost" then
		local def = defenderAt(view, index)
		if def then
			def.Boosted = true
		end
		local den = if type(e.Den) == "number" then roomAt(view, e.Den) else nil
		if den then
			pulseRoom(den, "BuffRing", Theme.Warning, 5)
		end
	elseif kind == "Spored" then
		local cavern = roomAt(view, index)
		if cavern then
			pulseRoom(cavern, "Cap", SPORE_GREEN, 3)
			puff(cavern:GetPivot().Position + Vector3.new(0, 1.6, 0), SPORE_GREEN, 14, 3, 1.4)
		end
		play("Spores")
	elseif kind == "Rise" then
		local def = defenderAt(view, index)
		if def then
			def.Forced = false
			def.Actor.Down = math.max(def.Actor.Down, 1)
			def.Actor.RiseUntil = os.clock() + 1.4
			flash(def.Actor, Color3.fromRGB(190, 110, 255), 0.6)
			puff(def.Actor.Model:GetPivot().Position + Vector3.new(0, 0.5, 0), Color3.fromRGB(190, 110, 255), 10, 3, 1)
		end
		play("Rise")
	elseif kind == "Attack" then
		local def = defenderAt(view, index)
		if e.By == "Defender" then
			swing(def and def.Actor)
			flash(v, Theme.Danger, 0.15)
			if v and view.VisitorPos then
				floatText(view.VisitorPos + Vector3.new(0, 2.5, 0), "-" .. tostring(e.Damage or ""), Theme.Danger)
			end
		else
			swing(v)
			if def then
				flash(def.Actor, Theme.Danger, 0.15)
				floatText(def.Actor.Model:GetPivot().Position + Vector3.new(0, 2.5, 0), "-" .. tostring(e.Damage or ""), Theme.Warning)
			end
		end
		play(if e.By == "Defender" and def and def.Model:GetAttribute("RoomId") == "GuardRoom" then "GuardAttack" else "Hit")
	elseif kind == "Trap" then
		local trap = trapAt(view, index)
		if trap then
			trap.Strike = os.clock()
		end
		if e.Hit then
			flash(v, Theme.Danger, 0.15)
		end
		play("SpikeStrike")
	elseif kind == "Slow" then
		flash(v, Theme.Success, 0.3)
	elseif kind == "DefenderDown" then
		local def = defenderAt(view, index)
		if def then
			def.Forced = true
		end
	elseif kind == "End" then
		local pos = view.VisitorPos
		if not pos then
			local entrance = Grid.EntranceCell
			pos = view.Plot:GetPivot():PointToWorldSpace(PlotGeometry.CellLocal(entrance.Column, entrance.Row))
		end
		local amount = if type(e.Amount) == "number" then e.Amount else 0
		if e.Result == "Defeated" then
			floatText(pos + Vector3.new(0, 3, 0), "+" .. amount, Theme.Gold)
			coinBurst(pos)
			play("VisitorDefeated")
			play("CoinGain")
		elseif e.Result == "Robbed" then
			floatText(pos + Vector3.new(0, 3, 0), "Robbed -" .. amount, Theme.Danger)
			Sound.Play("Robbed")
		elseif e.Result == "Escaped" then
			floatText(pos + Vector3.new(0, 3, 0), "Escaped", Theme.TextMuted)
			Sound.Play("Escaped")
		end
		-- Drops pop out, then XP and level-up (applied by the server; this is display only).
		local drops = if type(e.Drops) == "table" then e.Drops else {}
		for i, d in drops do
			if i > 4 or type(d) ~= "table" then
				break
			end
			local text, color
			if d.Kind == "Blueprint" then
				local def = Rooms.Get(tostring(d.RoomId))
				text, color = "Blueprint: " .. (def and def.DisplayName or "?"), Theme.Accent
			else
				text, color = tostring(d.Type or "Dungeon") .. " Box", BOX_COLOR[d.Type] or Theme.Gold
			end
			if d.Source == "LevelUp" then
				text = "Level reward: " .. text
			end
			dropPill(pos + Vector3.new(0, 0.5 + i * 0.9, 0), text, color, (i - 1) * 0.25)
		end
		if type(e.Xp) == "number" and e.Xp > 0 then
			floatText(pos + Vector3.new(0, 4.6, 0), "+" .. e.Xp .. " XP", Color3.fromRGB(170, 160, 255))
		end
		if type(e.LevelUp) == "number" then
			floatText(pos + Vector3.new(0, 6, 0), "LEVEL UP! " .. e.LevelUp, Theme.Gold)
			puff(pos + Vector3.new(0, 1.5, 0), Theme.Gold, 30, 14, 1.2)
		end
	end
end

function View.Init() end

function View.Start()
	fxFolder = make("Folder", { Name = "ClientFx" }, workspace)

	Net.OnEvent("EncounterFx", onFx)

	task.spawn(function()
		local folder = workspace:WaitForChild("Plots")
		for _, p in folder:GetChildren() do
			addPlot(p)
		end
		folder.ChildAdded:Connect(addPlot)
		folder.ChildRemoved:Connect(removePlot)
	end)

	RunService.Heartbeat:Connect(function(dt)
		for _, view in views do
			local ok, err = pcall(stepView, view, dt)
			if not ok then
				warn("[PlotView] " .. tostring(err))
			end
		end
	end)
end

return View
