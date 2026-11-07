-- Local rendering of every plot: the visitor, defenders, traps, doorways and
-- end-of-encounter effects. Everything here is cosmetic and driven by the
-- replicated plot attributes and EncounterFx events; it never decides outcomes.
-- Positions come from the plot's server-built cell tiles (Ui/Cells), names and
-- trap timing from the Catalog.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Ui = script.Parent.Parent.Ui
local Badges = require(Ui.Badges)
local Bus = require(Ui.Bus)
local Catalog = require(Ui.Catalog)
local Kit = require(Ui.Kit)
local Cells = require(Ui.Cells)
local Doors = require(Ui.Doors)
local Net = require(Ui.Net)
local P = require(Ui.PanelsKit)
local RarityColors = require(Ui.RarityColors)
local RewardMotion = require(Ui.RewardMotion)
local RoomSounds = require(Ui.RoomSounds)
local Settings = require(Ui.Settings)
local Sound = require(Ui.Sound)
local Theme = require(Ui.Theme)

local View = {}

-- Room id -> defender actors (one per unit), the attachment each stands at and flight/wing settings. Units step through
-- in order (DefenderUnit): Goblin Barracks = 2 goblins, Lich Sanctum = summoned skeleton (SummonSpot) then the lich.
local DEFENDER_ART = {
	SlimeNest = { Actors = { "Slime" } },
	GuardRoom = { Actors = { "Guard" } },
	RestlessCrypt = { Actors = { "Skeleton" } },
	BatRoost = { Actors = { "Bat" }, Flyer = { Rate = 14, Amp = 0.8, Lift = 1.1 } },
	GoblinBarracks = { Actors = { "Goblin", "Goblin" }, Spots = { "DefenderSpot", "DefenderSpot2" }, StepIn = true },
	MimicRoom = { Actors = { "Mimic" } },
	GolemForge = { Actors = { "Golem" } },
	LichSanctum = { Actors = { "Skeleton", "Lich" }, Spots = { "SummonSpot", "DefenderSpot" }, Summoned = 1 },
	DragonLair = { Actors = { "Dragon" }, Wings = { Rate = 3.2, Amp = 0.3 } },
	PhoenixNest = { Actors = { "Phoenix" }, Flyer = { Rate = 6, Amp = 0.55, Lift = 0.9 } },
	EmeraldGuardroom = { Actors = { "Guard" }, Tint = Color3.fromRGB(70, 220, 130) },
	CrystalSentinel = { Actors = { "Golem" }, Tint = Color3.fromRGB(120, 220, 255) },
	SunfireSanctum = { Actors = { "Phoenix" }, Flyer = { Rate = 6, Amp = 0.55, Lift = 0.9 }, Tint = Color3.fromRGB(255, 210, 65) },
	EclipseBastion = { Actors = { "Dragon" }, Wings = { Rate = 3.2, Amp = 0.3 }, Tint = Color3.fromRGB(135, 80, 210) },
}
local FIRE = Color3.fromRGB(255, 140, 40)
local FROST = Color3.fromRGB(150, 215, 255)
local VOID = Color3.fromRGB(170, 90, 255)
local RARITY_COLOR = RarityColors.Accent
local SPORE_GREEN = Color3.fromRGB(150, 220, 60)
local BOX_COLOR = { Dungeon = Theme.Gold, Rare = Color3.fromRGB(90, 160, 255) }
local JOINTS = { "Neck", "LeftShoulder", "RightShoulder", "LeftHip", "RightHip", "Lid", "Jaw", "Tail" }
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
local function newActor(name: string, opts: any?)
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
			if opts and opts.Tint and d.Name ~= "Root" then d.Color = d.Color:Lerp(opts.Tint, 0.4) end
		end
	end
	model.PrimaryPart.Anchored = true
	model.Parent = fxFolder
	local actor = { Model = model, Joints = {}, Phase = 0, Down = 0, Seed = math.random() * 6.28, Wings = opts and (opts.Flyer or opts.Wings), Lift = opts and opts.Flyer and opts.Flyer.Lift or 0 }
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

-- Walk cycle and attack swing through Motor6D.Transform; returns the forward lunge. Winged creatures flap their
-- shoulders about Z (opposite signs) instead of swinging arms; Mimic lid, Dragon jaw/tail and Phoenix tail are driven too.
local function animate(actor, dt: number, moving: boolean, speedScale: number): number
	local j = actor.Joints
	if actor.Highlight and actor.FlashUntil and os.clock() > actor.FlashUntil and not actor.KeepHighlight then
		actor.Highlight.Enabled = false
	end
	local ls, rs, lh, rh = j.LeftShoulder, j.RightShoulder, j.LeftHip, j.RightHip
	local reduced = Settings.Reduced()
	local winged = actor.Wings ~= nil
	local swingW = 0
	local lunge = 0
	if actor.Swing then
		local t = (os.clock() - actor.Swing) / 0.35
		if t >= 1 then
			actor.Swing = nil
		else
			swingW = math.sin(math.pi * t)
			lunge = swingW * 0.6
		end
	end
	if winged then
		local w = actor.Wings
		local a = math.sin(os.clock() * w.Rate * (if reduced then 0.5 else 1) + actor.Seed) * w.Amp * (if reduced then 0.3 else 1)
		if ls then
			ls.Transform = CFrame.Angles(0, 0, a)
		end
		if rs then
			rs.Transform = CFrame.Angles(0, 0, -a)
		end
	elseif moving then
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
	if swingW > 0 and rs and not winged then
		rs.Transform = CFrame.Angles(-swingW * 2, 0, 0)
	end
	-- Ambush / attack open the mimic lid and the dragon jaw; tails sway.
	local open = swingW
	if actor.OpenUntil and os.clock() < actor.OpenUntil then
		open = math.max(open, math.clamp((actor.OpenUntil - os.clock()) / 0.6 + 0.4, 0, 1))
	end
	if j.Lid then
		j.Lid.Transform = CFrame.Angles(-open * 1.1, 0, 0)
	end
	if j.Jaw then
		j.Jaw.Transform = CFrame.Angles(open * 0.6, 0, 0)
	end
	if j.Tail then
		j.Tail.Transform = CFrame.Angles(0, if reduced then 0 else math.sin(os.clock() * 2.2 + actor.Seed) * 0.3, 0)
	end
	return lunge
end

-- Effects (capped) -----------------------------------------------------------

local function floatText(pos: Vector3, text: string, color: Color3, icon: string?, burst: boolean?)
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
	local gui = make("BillboardGui", { Size = UDim2.fromOffset(100, 28), AlwaysOnTop = true, MaxDistance = 150 }, anchorPart)
	local iconImg
	if icon then -- CoinFloat / XpFloat next to the amount
		iconImg = Kit.Icon(gui, icon, UDim2.fromOffset(32, 32))
		iconImg.AnchorPoint, iconImg.Position, iconImg.ZIndex = Vector2.new(1, 0.5), UDim2.new(0.5, -(#text * 6.5), 0.5, 0), 2
	end
	local label = make("TextLabel", {
		BackgroundTransparency = 1,
		ZIndex = 3,
		Size = UDim2.fromScale(1, 1),
		Text = text,
		TextColor3 = color,
		TextStrokeColor3 = Theme.Stroke,
		TextStrokeTransparency = 0.2,
		TextSize = 20,
		FontFace = Theme.HeadingFont,
	}, gui)
	local reduced = Settings.Reduced()
	local info = TweenInfo.new(if reduced then 1 else 1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if not reduced then
		TweenService:Create(anchorPart, info, { Position = pos + Vector3.new(0, 3, 0) }):Play()
	end
	local fade = TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, info.Time - 0.5)
	TweenService:Create(label, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	if iconImg then
		TweenService:Create(iconImg, fade, { ImageTransparency = 1 }):Play()
	end
	task.delay(info.Time + 0.05, function()
		anchorPart:Destroy()
		fxText -= 1
	end)
end

local coinTemplate: any = nil
local function coinModel(): Model?
	if coinTemplate == nil then
		local art = ReplicatedStorage:FindFirstChild("Art")
		local props = art and art:FindFirstChild("Props")
		local c = props and props:FindFirstChild("Coin")
		coinTemplate = if c and c:IsA("Model") and c.PrimaryPart then c else false
	end
	return coinTemplate or nil
end

-- Target the current character position throughout the flight, including when
-- the owner moves or respawns. All of this remains visual and capped locally.
local function flyHome(start: Vector3, ownerId: number, duration: number, update, done)
	local started = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local owner = Players:GetPlayerByUserId(ownerId)
		local root = owner and owner.Character and owner.Character:FindFirstChild("HumanoidRootPart")
		local t = math.clamp((os.clock() - started) / duration, 0, 1)
		if not root or not root:IsA("BasePart") then
			conn:Disconnect()
			done(false)
			return
		end
		update(RewardMotion.Position(start, root.Position, t), t)
		if t >= 1 then conn:Disconnect(); done(true) end
	end)
end

local function coinBurst(pos: Vector3, ownerId: number)
	if Settings.Reduced() then
		return
	end
	local template = coinModel()
	for coinIndex = 1, 8 do
		if fxCoins >= COIN_CAP then
			return
		end
		fxCoins += 1
		local start = CFrame.new(pos + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		local coin: Instance, mover: Instance, fade: boolean
		if template then
			local m = template:Clone()
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false
				end
			end
			m.PrimaryPart.Anchored = true
			m:PivotTo(CFrame.new(pos + Vector3.new(0, 1, 0)))
			m.Parent = fxFolder
			-- Models do not tween; drive the pivot through a CFrameValue.
			local cv = make("CFrameValue", { Value = m:GetPivot() }, m)
			cv.Changed:Connect(function(v)
				m:PivotTo(v)
			end)
			coin, mover, fade = m, cv, false
		else
			-- No coin art: a CoinFloat sprite on an invisible anchor.
			local p = make("Part", { Anchored = true, CanCollide = false, CanQuery = false, Transparency = 1, Size = Vector3.one * 0.2, CFrame = start }, fxFolder)
			local bb = make("BillboardGui", { Size = UDim2.fromOffset(34, 34), AlwaysOnTop = true, MaxDistance = 150 }, p)
			Kit.Icon(bb, "CoinFloat", UDim2.fromScale(1, 1))
			coin, mover, fade = p, p, true
		end
		local trailPart = if coin:IsA("Model") then coin.PrimaryPart else coin
		local a0 = make("Attachment", { Position = Vector3.new(0, 0.16, 0) }, trailPart)
		local a1 = make("Attachment", { Position = Vector3.new(0, -0.16, 0) }, trailPart)
		make("Trail", { Attachment0 = a0, Attachment1 = a1, Color = ColorSequence.new(Color3.new(1, 1, 1)), Lifetime = 0.22, LightEmission = 0.6, FaceCamera = true, MinLength = 0.02, WidthScale = NumberSequence.new(1, 0), Transparency = NumberSequence.new(0.15, 1) }, trailPart)
		local function at(v: Vector3): any
			return if template then { Value = CFrame.new(v) } else { Position = v }
		end
		local spread = Vector3.new(math.random() * 5 - 2.5, 0, math.random() * 5 - 2.5)
		local up = TweenService:Create(mover, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), at(pos + Vector3.new(0, 3.5, 0) + spread * 0.5))
		local downGoal = at(pos + Vector3.new(0, 0.3, 0) + spread)
		local down = TweenService:Create(mover, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), downGoal)
		up.Completed:Once(function()
			down:Play()
		end)
		down.Completed:Once(function()
			local origin = pos + Vector3.new(0, 0.3, 0) + spread
			task.delay((coinIndex - 1) * 0.08, function()
				flyHome(origin, ownerId, 0.55, function(position)
					if mover:IsA("CFrameValue") then mover.Value = CFrame.new(position) elseif mover:IsA("BasePart") then mover.Position = position end
				end, function(arrived)
					if arrived and ownerId == Players.LocalPlayer.UserId then Sound.Play("CoinCollect") end
					coin:Destroy(); fxCoins -= 1
				end)
			end)
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
		Texture = (Kit.Spec("World.VfxPuff") or {}).Id or "",
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

-- Pulse every part with this name in a room model (art), or flash a temporary ring when the art has none.
local function pulseRoom(model: Model, partName: string, color: Color3, diameter: number, scale: number?)
	local found = false
	for _, part in model:GetDescendants() do
		if part.Name == partName and part:IsA("BasePart") then
			found = true
			if not pulsing[part] and not Settings.Reduced() then
				pulsing[part] = true
				local size = part.Size
				local t = TweenService:Create(part, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { Size = size * (scale or 1.25) })
				t.Completed:Once(function()
					part.Size = size
					pulsing[part] = nil
				end)
				t:Play()
			end
		end
	end
	if found then
		return
	end
	if fxRings >= 6 then
		return
	end
	fxRings += 1
	-- No pulse part in the art: a VfxRing sprite on a flat invisible part that grows and fades.
	local ring = make("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		Transparency = 1,
		Size = Vector3.new(diameter * 0.6, 0.05, diameter * 0.6),
		CFrame = model:GetPivot() * CFrame.new(0, 0.25, 0),
	}, fxFolder)
	local sg = make("SurfaceGui", { Face = Enum.NormalId.Top, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 30, LightInfluence = 0, Adornee = ring }, ring)
	local ringImg = Kit.Sprite(sg, "World.VfxRing", { Size = UDim2.fromScale(1, 1), ImageColor3 = color, ImageTransparency = 0.2, ScaleType = Enum.ScaleType.Stretch })
	local info = TweenInfo.new(if Settings.Reduced() then 0.01 else 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local goal = { Size = Vector3.new(diameter, 0.05, diameter) }
	if Settings.Reduced() then
		goal = { Size = ring.Size }
	end
	TweenService:Create(ringImg, info, { ImageTransparency = 1 }):Play()
	local t = TweenService:Create(ring, info, goal)
	t.Completed:Once(function()
		ring:Destroy()
		fxRings -= 1
	end)
	t:Play()
end

-- Cosmetic drop orb: the server has already granted the reward.
local function dropOrb(pos: Vector3, color: Color3, icon: string, roomId: string?, ownerId: number, delay: number, blueprint: boolean?)
	if fxDrops >= 6 then return end
	fxDrops += 1
	task.delay(delay, function()
		local orb = make("Part", { Name = "DropOrb", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = color, Transparency = 0.25, Size = Vector3.one * 0.85, Position = pos }, fxFolder)
		local a = make("Attachment", { Position = Vector3.new(0, 0.25, 0) }, orb)
		local b = make("Attachment", { Position = Vector3.new(0, -0.25, 0) }, orb)
		make("Trail", { Attachment0 = a, Attachment1 = b, Color = ColorSequence.new(color), Lifetime = 0.3, LightEmission = 0.8, FaceCamera = true, MinLength = 0.02, WidthScale = NumberSequence.new(1, 0), Transparency = NumberSequence.new(0.15, 1) }, orb)
		local gui = make("BillboardGui", { Size = UDim2.fromOffset(34, 34), AlwaysOnTop = true, MaxDistance = 150 }, orb)
		if roomId then
			local portrait = P.RoomImage(gui, roomId, 34)
			portrait.Size = UDim2.fromScale(1, 1)
			if blueprint then
				local kind = Kit.Icon(gui, "Blueprint", UDim2.fromOffset(16, 16))
				kind.AnchorPoint, kind.Position, kind.ZIndex = Vector2.new(1, 1), UDim2.fromScale(1, 1), 2
			end
		else
			Kit.Icon(gui, icon, UDim2.fromScale(1, 1))
		end
		local function finish() orb:Destroy(); fxDrops -= 1 end
		if Settings.Reduced() then
			task.delay(0.5, finish)
		else
			local rise = TweenService:Create(orb, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = pos + Vector3.new(0, 1.5, 0) })
			rise.Completed:Once(function()
				flyHome(orb.Position, ownerId, 0.8, function(position, t)
					orb.Position, orb.Transparency = position, 0.25 + t * 0.6
				end, function(arrived)
					if arrived and ownerId == Players.LocalPlayer.UserId then Sound.Play("LootCollect") end
					finish()
				end)
			end)
			rise:Play()
		end
	end)
end

-- Local axis (unit vector) of a part's thinnest (thin = true) or longest extent.
local function partAxis(part: BasePart, thin: boolean): Vector3
	local sz = part.Size
	local axes = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }
	local best, bestV = 1, if thin then math.huge else -1
	for i, v in { sz.X, sz.Y, sz.Z } do
		if (thin and v < bestV) or (not thin and v > bestV) then
			best, bestV = i, v
		end
	end
	return axes[best]
end

-- Breath / flame cone: a one-shot emitter on a temp part at `from`, aimed at `to` (capped).
local fxBreath = 0
local function breath(from: Vector3, to: Vector3, color0: Color3, color1: Color3)
	if fxBreath >= 3 then
		return
	end
	fxBreath += 1
	local dir = to - from
	if dir.Magnitude < 0.1 then
		dir = Vector3.zAxis
	end
	local p = tempPart(from, 1.2)
	p.CFrame = CFrame.lookAt(from, from + dir)
	local e = make("ParticleEmitter", {
		Enabled = false,
		Color = ColorSequence.new(color0, color1),
		Texture = (Kit.Spec("World.VfxPuff") or {}).Id or "",
		Lifetime = NumberRange.new(0.35, 0.6),
		Speed = NumberRange.new(14, 20),
		SpreadAngle = Vector2.new(10, 10),
		EmissionDirection = Enum.NormalId.Front,
		Rate = 0,
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.6) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
	}, p)
	e:Emit(if Settings.Reduced() then 10 else 36)
	task.delay(1.2, function()
		fxBreath -= 1
	end)
end

-- Paths ----------------------------------------------------------------------

-- Plot-local points: the visitor spawn, the entrance, then each route cell (tile pivots).
local function buildPath(plot: Instance)
	local anchor = (plot :: Model):GetPivot()
	local spawn = Cells.Spawn(plot)
	local entrance = Cells.World(plot, Catalog.Current.Grid.EntranceKey)
	local pts = {}
	for _, cf in { spawn, entrance } do
		if cf then
			table.insert(pts, anchor:PointToObjectSpace(cf.Position))
		end
	end
	for _, key in string.split((plot:GetAttribute("Route") :: string) or "", "|") do
		local cf = key ~= "" and Cells.World(plot, key)
		if cf then
			table.insert(pts, anchor:PointToObjectSpace(cf.Position))
		end
	end
	if #pts == 0 then
		pts[1] = Vector3.zero
	end
	local cum = { 0 }
	for i = 2, #pts do
		cum[i] = cum[i - 1] + (pts[i] - pts[i - 1]).Magnitude
	end
	-- Rebuilt every frame until the tiles have replicated.
	return { Points = pts, Cum = cum, Complete = Cells.Folder(plot) ~= nil }
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
	for _, a in def.Actors do
		a.Model:Destroy()
	end
end

local function destroyTrap(trap)
	if trap.Fallback then
		trap.Fallback:Destroy()
	end
end

-- Use the same bar and model-relative anchor for every character.
local function addHealthBar(actor)
	local root = actor.Model.PrimaryPart
	local cf, size = actor.Model:GetBoundingBox()
	local halfHeight = (math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.LookVector.Y) * size.Z) / 2
	local anchorWorld = Vector3.new(cf.Position.X, cf.Position.Y + halfHeight + 0.35, cf.Position.Z)
	local anchor = make("Attachment", { Name = "HealthAnchor", Position = root.CFrame:PointToObjectSpace(anchorWorld) }, root)
	local gui = make("BillboardGui", { Name = "HealthBar", Adornee = anchor, Size = UDim2.fromOffset(80, 14), MaxDistance = 150 }, actor.Model)
	local bg = Kit.Sprite(gui, "Bars.Track", { Size = UDim2.fromScale(1, 1) })
	local clip = make("Frame", { Name = "Clip", BackgroundTransparency = 1, Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 1, -6), ClipsDescendants = true }, bg)
	local fill = make("ImageLabel", { Name = "Fill", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ImageColor3 = Theme.Success, Image = "" }, clip)
	Kit.SkinByHeight(fill, Kit.Spec("Bars.Fill"))
	actor.HealthBar, actor.HealthFill = gui, fill
	return anchor
end

local function newVisitor(view, id: string)
	local actor = newActor(id)
	local variant = view.Plot:GetAttribute("VisitorVariant")
	variant = if type(variant) == "string" and Badges.VariantTint[variant] then variant else ""
	local anchor = addHealthBar(actor)
	if variant ~= "" then
		-- Rare variant: nameplate above the health bar and a tint (sparkles for Shiny and Gilded).
		local badge = make("BillboardGui", { Name = "VariantBadge", Adornee = anchor, Size = UDim2.fromOffset(110, 30), StudsOffsetWorldSpace = Vector3.new(0, 0.7, 0), MaxDistance = 150 }, actor.Model)
		local plate = Badges.Variant(badge, variant, 30)
		if plate then
			plate.AnchorPoint, plate.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
		end
		actor.Variant = variant
		if variant ~= "Elite" and actor.Model.PrimaryPart then
			make("ParticleEmitter", {
				Enabled = not Settings.Reduced(),
				Color = ColorSequence.new(Badges.VariantTint[variant]),
				Texture = (Kit.Spec("World.VfxSparkle") or {}).Id or "",
				Rate = 7,
				Lifetime = NumberRange.new(0.8, 1.3),
				Speed = NumberRange.new(0.5, 1.5),
				SpreadAngle = Vector2.new(180, 180),
				LightEmission = 0.7,
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) }),
			}, actor.Model.PrimaryPart)
		end
	end
	view.Visitor, view.VisitorId = actor, id
	view.Chase = nil
end

-- Frame bars of shimmer-tier rooms: hue-cycled each frame (see Heartbeat below).
local shimmerBars: { any } = {} -- BaseParts (trim) and ImageLabels (floor ring sprite)

local function clearDeco(view, m: Instance)
	local d = view.Deco[m]
	if d then
		for i = #shimmerBars, 1, -1 do
			if shimmerBars[i] == d.Trim or shimmerBars[i]:IsDescendantOf(d.Folder) then
				table.remove(shimmerBars, i)
			end
		end
		d.Folder:Destroy()
		view.Deco[m] = nil
	end
end

-- Subtle rarity mark: a thin glowing frame on the floor edge plus a small badge
-- (Common none). Sparkle tiers also sparkle, and shimmer tiers cycle a soft
-- rainbow on the frame, unless motion is reduced.
local function applyRarity(view, m: Model)
	local rarity = m:GetAttribute("Rarity")
	local d = view.Deco[m]
	if d and d.Rarity == rarity then
		d.Sparkle.Enabled = d.Sparkles and not Settings.Reduced()
		return
	end
	clearDeco(view, m)
	local color = RARITY_COLOR[rarity] or RARITY_COLOR.Common
	-- The art's floor trim (a gold ring in the Blender models) takes the tier colour.
	local trim = m:FindFirstChild("RarityTrim", true)
	if trim and trim:IsA("BasePart") then
		trim.Color = color
	end
	if not RARITY_COLOR[rarity] or rarity == "Common" then
		return
	end
	-- Keep the existing coloured trim, but no floor circle or overhead tier label.
end

-- Room modifier badge and off-route dimming (rooms may sit in any cell; off-route ones never see visitors).
local function applyMarks(view, m: Model)
	local mod = m:GetAttribute("Modifier")
	mod = if type(mod) == "string" and Badges.ModifierColor[mod] then mod else ""
	local off = m:GetAttribute("OnRoute") == false
	local sig = "" -- no persistent badges; keep off-route dimming below
	local rec = view.Marks[m]
	if not rec or rec.Sig ~= sig or not rec.Gui.Parent then
		if rec then
			rec.Gui:Destroy()
			view.Marks[m] = nil
			rec = nil
		end
		local adornee = m:FindFirstChildWhichIsA("BasePart", true)
		if adornee and sig ~= "" then
			local gui = make("BillboardGui", { Name = "RoomMarks", Adornee = adornee, Size = UDim2.fromOffset(76, 34), StudsOffset = Vector3.new(0, 4.6, 0), MaxDistance = 90, LightInfluence = 0 }, m)
			make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4) }, gui)
			if mod ~= "" then
				Badges.Modifier(gui, mod, 32)
			end
			if off then
				local tag = Kit.Icon(gui, "Map", UDim2.fromOffset(32, 32))
				tag.ImageTransparency = 0.1
				local x = Kit.Icon(tag, "Cross", UDim2.fromScale(0.55, 0.55))
				x.AnchorPoint, x.Position = Vector2.new(1, 1), UDim2.fromScale(1, 1)
			end
			rec = { Sig = sig, Gui = gui }
			view.Marks[m] = rec
		end
	end
	if view.Plot:GetAttribute("State") ~= "Building" then
		local dim = if off then 0.5 else 0
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "Pivot" then
				d.LocalTransparencyModifier = dim
			end
		end
	end
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

-- Animated room art (client only). Spinners rotate about their thin axis; Stars twinkle; Arrows fly across on Trap
-- events; Flames burst on strikes. Parts are found by name in the art, so a room without them simply does nothing.
local ROOM_ANIM = { StormGallery = true, ArrowGallery = true, FlameVent = true, FrostChamber = true, VoidGate = true, VoidVault = true, CelestialCoffer = true }
local SPINNERS = {
	VoidGate = { PortalRing = 1.3, PortalRune = -0.8 },
	VoidVault = { Swirl = 2.2, SwirlArms = -1.4 },
	CelestialCoffer = { MagicCircle = 0.6 },
}

local function buildAnim(m: Model, roomId: string)
	local an: any = { Model = m, Id = roomId, Spin = {}, Stars = {}, Arrows = {}, Flames = {}, Angle = 0 }
	local center = m:GetPivot().Position
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			local speed = SPINNERS[roomId] and SPINNERS[roomId][d.Name]
			if speed then
				table.insert(an.Spin, { Part = d, Rest = d.CFrame, Axis = partAxis(d, true), Speed = speed })
			elseif roomId == "CelestialCoffer" and d.Name == "Star" then
				table.insert(an.Stars, { Part = d, Size = d.Size, Phase = #an.Stars * 1.7 })
			elseif (roomId == "ArrowGallery" or roomId == "StormGallery") and d.Name == "Arrow" then
				local rest = d.CFrame
				local dir = Vector3.new(center.X - rest.Position.X, 0, center.Z - rest.Position.Z)
				if dir.Magnitude < 0.5 then
					dir = rest.LookVector
				end
				dir = dir.Unit
				local axis = rest:VectorToWorldSpace(partAxis(d, false))
				if axis:Dot(dir) < 0 then
					axis = -axis
				end
				local cross = axis:Cross(dir)
				local fly = rest
				if cross.Magnitude > 1e-3 then
					fly = CFrame.fromAxisAngle(cross.Unit, math.acos(math.clamp(axis:Dot(dir), -1, 1))) * rest.Rotation + rest.Position
				end
				table.insert(an.Arrows, { Part = d, Rest = rest, Fly = fly, Dir = dir, Delay = #an.Arrows * 0.07 })
			elseif roomId == "FlameVent" and (d.Name == "Flame" or d.Name == "FlameCore") then
				table.insert(an.Flames, { Part = d, Size = d.Size })
			end
		end
	end
	return an
end

-- Opens the lid of a room's chest (treasure rooms, on Robbed) about its back edge, then closes it again.
local function openChest(m: Model)
	local lid = m:FindFirstChild("Lid", true)
	local lock = m:FindFirstChild("Lock", true)
	if not (lid and lid:IsA("BasePart")) or Settings.Reduced() or pulsing[lid] then
		return
	end
	pulsing[lid] = true
	local rest = lid.CFrame
	local sz = lid.Size
	local front = Vector3.new(0, 0, 1)
	if lock and lock:IsA("BasePart") then
		local lp = rest:PointToObjectSpace(lock.Position)
		front = if math.abs(lp.X) > math.abs(lp.Z) then Vector3.new(math.sign(lp.X), 0, 0) else Vector3.new(0, 0, math.sign(lp.Z))
	end
	local hinge = rest * CFrame.new(-front.X * sz.X / 2, -sz.Y / 2, -front.Z * sz.Z / 2)
	local function pose(a: number)
		local rot = if front.Z ~= 0 then CFrame.Angles(-front.Z * a, 0, 0) else CFrame.Angles(0, 0, front.X * a)
		lid.CFrame = hinge * rot * hinge:Inverse() * rest
	end
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - t0
		if t > 2.6 or not lid.Parent then
			conn:Disconnect()
			if lid.Parent then
				lid.CFrame = rest
			end
			pulsing[lid] = nil
			return
		end
		pose(1.2 * math.clamp(math.min(t / 0.25, (2.6 - t) / 0.5), 0, 1))
	end)
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
			Doors.Apply(m, m.Name, function(k)
				return occupied[k] == true
			end)
			applyRarity(view, m)
			applyMarks(view, m)
			local dcfg = DEFENDER_ART[roomId]
			if dcfg and not view.Defenders[m] then
				local actors = {}
				for i, name in dcfg.Actors do
					local actor = newActor(name, dcfg)
					addHealthBar(actor)
					actor.HealthBar.Enabled = false
					actors[i] = actor
				end
				view.Defenders[m] = { Actors = actors, Actor = actors[1], Model = m, Cfg = dcfg }
			end
			if ROOM_ANIM[roomId] and not view.Anims[m] then
				view.Anims[m] = buildAnim(m, roomId)
			end
			if (roomId == "SpikeHall" or roomId == "ArcaneBarricade") and not view.Traps[m] then
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
	for m in view.Anims do
		if not seen[m] or not m.Parent then
			view.Anims[m] = nil
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

local function spotCF(view, def, anchor: CFrame, i: number?): CFrame
	local name = def.Cfg and def.Cfg.Spots and def.Cfg.Spots[i or 1] or "DefenderSpot"
	local spot = def.Model:FindFirstChild(name, true)
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
		if view.RouteStr ~= routeStr or not view.Path or not view.Path.Complete then
			view.RouteStr = routeStr
			view.Path = buildPath(plot)
		end
		-- Progress counts from the entrance centre; the path starts at the spawn point.
		local cellSize = Catalog.Current.Grid.CellSize
		local target = (plot:GetAttribute("VisitorProgress") or 0) + (view.Path.Cum[2] or 0)
		local chase = view.Chase or 0
		local step = math.clamp(target - chase, -MAX_SPEED * dt, MAX_SPEED * dt)
		if math.abs(target - chase) > 3 * cellSize then
			step = target - chase
		end
		-- Void Gate: the visitor SNAPS back to the entrance (no tween) with a portal flash at both ends.
		if view.SnapUntil then
			if os.clock() > view.SnapUntil then
				view.SnapUntil = nil
			elseif target < chase - 1 then
				step = target - chase
				view.SnapUntil = nil
				local entrance = Cells.World(plot, Catalog.Current.Grid.EntranceKey)
				local at = if entrance then entrance.Position + Vector3.new(0, 1.2, 0) else nil
				if at then
					puff(at, VOID, 22, 8, 0.9)
				end
				flash(v, VOID, 0.4)
			end
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
		local burning = plot:GetAttribute("VisitorBurning") == true
		local chilled = plot:GetAttribute("VisitorChilled") == true
		-- Status particles (flames while burning, frost motes while chilled).
		for _, st in { { "BurnFx", burning, FIRE, 14, "VfxPuff", 0.9 }, { "ChillFx", chilled, FROST, 8, "VfxSparkle", 0.55 } } do
			local fx = v[st[1]]
			if not fx then
				fx = make("ParticleEmitter", {
					Enabled = false,
					Color = ColorSequence.new(st[3]),
					Texture = (Kit.Spec("World." .. st[5]) or {}).Id or "",
					Lifetime = NumberRange.new(0.5, 0.9),
					Speed = NumberRange.new(1, 2.5),
					EmissionDirection = Enum.NormalId.Top,
					SpreadAngle = Vector2.new(30, 30),
					LightEmission = 0.9,
					Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, st[6]), NumberSequenceKeypoint.new(1, 0) }),
				}, v.Model.PrimaryPart)
				v[st[1]] = fx
			end
			fx.Rate = if reduced then math.ceil(st[4] / 4) else st[4]
			fx.Enabled = st[2]
		end
		local tint = if plot:GetAttribute("VisitorSpored") == true then SPORE_GREEN elseif burning then FIRE elseif chilled then FROST elseif slowed then Theme.Success else Badges.VariantTint[v.Variant or ""]
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
				Texture = (Kit.Spec("World.VfxSparkle") or {}).Id or "",
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
		v.HealthFill.Visible = frac > 0
		v.HealthFill.ImageColor3 = if frac < 0.3 then Theme.Danger else Theme.Success
	end

	-- Defenders: one actor per unit; the active unit (DefenderUnit) fights, finished units lie down, a Goblin
	-- steps in from its own spot, the Lich's skeleton only exists once summoned.
	for m, def in view.Defenders do
		local cfg = def.Cfg
		local hp = m:GetAttribute("DefenderHealth")
		local roomDown = (hp ~= nil and hp <= 0) or (def.Forced and inEncounter)
		if not inEncounter then
			def.Forced = false
			def.UnitEvt = 1
			def.SummonAt = nil
		end
		local attrUnit = m:GetAttribute("DefenderUnit")
		local unit = math.clamp(math.max(if type(attrUnit) == "number" then attrUnit else 1, def.UnitEvt or 1), 1, #def.Actors)
		def.Actor = def.Actors[unit]
		-- DenBoost glow while the boosted defender is in the encounter.
		local boosted = def.Boosted == true and inEncounter
		if not inEncounter then
			def.Boosted = false
		end
		for i, a in def.Actors do
			local maxHp = m:GetAttribute("DefenderMaxHealth")
			local fraction = if type(hp) == "number" and type(maxHp) == "number" and maxHp > 0 then math.clamp(hp / maxHp, 0, 1) else 1
			a.HealthBar.Enabled = inEncounter and i == unit and not roomDown and fraction < 1
			a.HealthFill.Size = UDim2.fromScale(fraction, 1)
			a.HealthFill.Visible = fraction > 0
			a.HealthFill.ImageColor3 = if fraction < 0.3 then Theme.Danger else Theme.Success
			local hidden = cfg.Summoned == i and not (def.SummonAt and inEncounter)
			if a.Hidden ~= hidden then
				a.Hidden = hidden
				a.Model.Parent = if hidden then nil else fxFolder
			end
			if not hidden then
				local down = roomDown or i < unit
				local goal = if down then 1 else 0
				local rate = if a.RiseUntil and os.clock() < a.RiseUntil then 1.2 else 4 -- Rise stands up slowly
				a.Down = if reduced then goal else a.Down + math.clamp(goal - a.Down, -dt * rate, dt * rate)
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
				local flyer = cfg.Flyer ~= nil
				local bob = if reduced or down then 0 else math.sin(os.clock() * (if flyer then 3 else 2) + a.Seed) * (if flyer then 0.22 else 0.1)
				local cf = spotCF(view, def, anchor, i)
				-- Goblins: the active one walks over to the front spot.
				if cfg.StepIn and i > 1 then
					local want = if i == unit and not down then 1 else 0
					a.StepP = math.clamp((a.StepP or 0) + (want * 2 - 1) * dt / 0.5, 0, 1)
					if a.StepP > 0 then
						local front = spotCF(view, def, anchor, 1)
						cf = cf:Lerp(front, a.StepP)
					end
				end
				a.Model:PivotTo(cf * CFrame.new(0, bob + a.Lift * (1 - a.Down) - a.Down * 0.3, -lunge) * CFrame.Angles(-a.Down * 1.4, 0, 0))
			end
		end
	end

	-- Traps: telegraph from the fixed cycle, strike from Trap events.
	for model, trap in view.Traps do
		local cfg = Catalog.Room(model:GetAttribute("RoomId") or "SpikeHall")
		local telegraph = view.EncStart and cfg and cfg.TrapCycle and cfg.TrapTelegraph
			and (os.clock() - view.EncStart) % cfg.TrapCycle < cfg.TrapTelegraph
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

	-- Animated room art.
	local now = os.clock()
	for m, an in view.Anims do
		if not m.Parent then
			continue
		end
		if not reduced then
			for _, sp in an.Spin do
				if sp.Part.Parent then
					sp.Part.CFrame = sp.Rest * CFrame.fromAxisAngle(sp.Axis, now * sp.Speed)
				end
			end
		end
		for _, st in an.Stars do
			if st.Part.Parent then
				st.Part.Size = if reduced then st.Size else st.Size * (1 + 0.25 * math.sin(now * 3 + st.Phase))
			end
		end
		if an.Fire then
			local live = false
			for _, ar in an.Arrows do
				local t = (now - an.Fire - ar.Delay) / 0.5
				if ar.Part.Parent then
					if reduced or t >= 1 or t < 0 and ar.Flying == nil then
						if ar.Flying then
							ar.Flying = nil
							ar.Part.CFrame = ar.Rest
							ar.Part.LocalTransparencyModifier = 0
						end
					else
						live = true
						ar.Flying = true
						ar.Part.CFrame = ar.Fly + ar.Dir * (math.max(t, 0) * 7)
						ar.Part.LocalTransparencyModifier = if t > 0.75 then (t - 0.75) * 4 else 0
					end
				end
			end
			if not live and now - an.Fire > 1.5 then
				an.Fire = nil
			end
		end
		if an.Burst then
			local t = (now - an.Burst) / 0.45
			local k = if t >= 1 or reduced then 0 else math.sin(math.pi * t)
			for _, f in an.Flames do
				if f.Part.Parent then
					f.Part.Size = f.Size * Vector3.new(1 + k * 0.5, 1 + k * 1.2, 1 + k * 0.5)
				end
			end
			if t >= 1 then
				an.Burst = nil
			end
		end
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
	local view = { Plot = plot, Defenders = {}, Traps = {}, Anims = {}, Deco = {}, Marks = {}, Timer = 0, Dirty = true }
	views[plot] = view
	plot:GetAttributeChangedSignal("Route"):Connect(function()
		view.Dirty = true
	end)
	plot:GetAttributeChangedSignal("State"):Connect(function()
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
			if e.Burn and def and v and view.VisitorPos then
				-- Dragon breath: a flame cone from the head toward the visitor, jaw open for the swing.
				local head = def.Actor.Model:FindFirstChild("Head", true)
				local from = if head and head:IsA("BasePart") then head.Position else def.Actor.Model:GetPivot().Position + Vector3.new(0, 1.2, 0)
				breath(from, view.VisitorPos + Vector3.new(0, 1, 0), Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 80, 20))
			end
			if v and view.VisitorPos then
				floatText(view.VisitorPos + Vector3.new(0, 2.5, 0), "-" .. tostring(e.Damage or ""), Theme.Danger, nil, true)
			end
		else
			swing(v)
			if def and def.Actor then
				flash(def.Actor, Theme.Danger, 0.15)
				floatText(def.Actor.Model:GetPivot().Position + Vector3.new(0, 2.5, 0), "-" .. tostring(e.Damage or ""), Theme.Warning, nil, true)
			end
		end
		if e.By == "Defender" then
			local room = roomAt(view, index)
			for _, sound in RoomSounds.Attack(room and room:GetAttribute("RoomId")) do play(sound) end
		else
			play("Hit")
		end
	elseif kind == "Trap" then
		local trap = trapAt(view, index)
		if trap then
			trap.Strike = os.clock()
		end
		local room = roomAt(view, index)
		local an = room and view.Anims[room]
		if an and (an.Id == "ArrowGallery" or an.Id == "StormGallery") then
			an.Fire = os.clock()
		elseif an and an.Id == "FlameVent" then
			an.Burst = os.clock()
			puff(room:GetPivot().Position + Vector3.new(0, 1.2, 0), FIRE, 12, 4, 0.8)
		end
		if e.Hit then
			flash(v, if e.Burn then FIRE else Theme.Danger, 0.15)
		end
		play(RoomSounds.Trap(room and room:GetAttribute("RoomId")))
	elseif kind == "Slow" then
		flash(v, Theme.Success, 0.3)
	elseif kind == "Burn" then
		if v and view.VisitorPos then
			floatText(view.VisitorPos + Vector3.new(math.random() * 1.2 - 0.6, 2.2, 0), "-" .. tostring(e.Damage or ""), FIRE)
		end
	elseif kind == "Chill" then
		local room = roomAt(view, index)
		if room then
			pulseRoom(room, "Crystal", FROST, 5, 1.35)
			puff(room:GetPivot().Position + Vector3.new(0, 1.4, 0), FROST, 10, 3, 1)
		end
		flash(v, FROST, 0.3)
	elseif kind == "Unit" then
		local def = defenderAt(view, index)
		if def then
			def.UnitEvt = if type(e.Unit) == "number" then e.Unit else (def.UnitEvt or 1) + 1
			local a = def.Actors[math.clamp(def.UnitEvt, 1, #def.Actors)]
			puff(a.Model:GetPivot().Position + Vector3.new(0, 0.4, 0), Color3.fromRGB(190, 170, 130), 8, 3, 0.7)
			if def.Cfg.Summoned then
				flash(a, Color3.fromRGB(120, 255, 150), 0.5)
			end
		end
	elseif kind == "Summon" then
		local def = defenderAt(view, index)
		local sk = def and def.Cfg.Summoned and def.Actors[def.Cfg.Summoned]
		if sk then
			def.SummonAt = os.clock()
			sk.Down = 1
			sk.RiseUntil = os.clock() + 1.4
			flash(sk, Color3.fromRGB(120, 255, 150), 0.7)
			puff(sk.Model:GetPivot().Position + Vector3.new(0, 0.5, 0), Color3.fromRGB(120, 255, 150), 14, 3, 1)
			play("Rise")
		end
	elseif kind == "Ambush" then
		local def = defenderAt(view, index)
		if def and def.Actor then
			def.Actor.OpenUntil = os.clock() + 0.6
			swing(def.Actor)
			puff(def.Actor.Model:GetPivot().Position + Vector3.new(0, 1, 0), Theme.Gold, 12, 6, 0.6)
		end
		flash(v, Theme.Danger, 0.25)
		if v and view.VisitorPos then
			floatText(view.VisitorPos + Vector3.new(0, 3, 0), "AMBUSH -" .. tostring(e.Damage or ""), Theme.Danger, nil, true)
		end
		play("Hit")
	elseif kind == "Revive" then
		local def = defenderAt(view, index)
		if def then
			def.Forced = false
			for _, a in def.Actors do
				a.Down = math.max(a.Down, 1)
				a.RiseUntil = os.clock() + 1.2
			end
			flash(def.Actor, FIRE, 0.8)
			local pos = def.Actor.Model:GetPivot().Position + Vector3.new(0, 1, 0)
			puff(pos, FIRE, 26, 9, 1.1)
			puff(pos, Color3.fromRGB(255, 230, 120), 12, 5, 0.9)
			floatText(pos + Vector3.new(0, 2, 0), "Reborn!", FIRE)
		end
		local nest = if type(e.By) == "number" then roomAt(view, e.By) else nil
		if nest then
			pulseRoom(nest, "Egg", FIRE, 5, 1.4)
		end
		if nest then
			for _, sound in RoomSounds.Attack(nest:GetAttribute("RoomId")) do play(sound) end
		else
			play("Heal")
		end
	elseif kind == "Void" then
		local room = roomAt(view, index)
		if room then
			pulseRoom(room, "PortalRing", VOID, 5, 1.3)
			pulseRoom(room, "PortalCore", VOID, 5, 1.5)
		end
		if view.VisitorPos then
			puff(view.VisitorPos + Vector3.new(0, 1.2, 0), VOID, 22, 8, 0.9)
			floatText(view.VisitorPos + Vector3.new(0, 3, 0), "Sent back!", VOID)
		end
		flash(v, VOID, 0.4)
		view.SnapUntil = os.clock() + 1
	elseif kind == "DefenderDown" then
		local def = defenderAt(view, index)
		if def then
			def.Forced = true
		end
	elseif kind == "End" then
		local pos = view.VisitorPos
		if not pos then
			local entrance = Cells.World(view.Plot, Catalog.Current.Grid.EntranceKey)
			pos = if entrance then entrance.Position else view.Plot:GetPivot().Position
		end
		local amount = if type(e.Amount) == "number" then e.Amount else 0
		if e.Result == "Defeated" then
			floatText(pos + Vector3.new(0, 3, 0), "+" .. amount, Theme.Gold, "CoinFloat")
			coinBurst(pos, view.Plot:GetAttribute("OwnerUserId") or 0)
			play("VisitorDefeated")
			play("CoinGain")
		elseif e.Result == "Robbed" then
			floatText(pos + Vector3.new(0, 3, 0), "Robbed -" .. amount, Theme.Danger)
			local rooms = view.Plot:FindFirstChild("Rooms")
			for _, m in if rooms then rooms:GetChildren() else {} do
				local def = Catalog.Room(m:GetAttribute("RoomId"))
				if def and def.Kind == "Treasure" and m:GetAttribute("OnRoute") ~= false then
					openChest(m :: Model)
					puff(m:GetPivot().Position + Vector3.new(0, 1.5, 0), Theme.Gold, 14, 5, 0.9)
				end
			end
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
			if not d.Overflow then
				local def = d.RoomId and Catalog.Room(d.RoomId)
				local rarity = if def then def.Rarity else (if d.Type == "Rare" then "Rare" else "Common")
				local color = RARITY_COLOR[rarity] or Theme.Gold
				local icon = if d.Kind == "Blueprint" then "Blueprint" elseif d.Type == "Crystal" then "CrystalBox" elseif d.Type == "Rare" then "RareBox" else "Box"
				dropOrb(pos + Vector3.new(0, 0.8 + i * 0.5, 0), color, icon, if d.Kind == "Blueprint" then d.RoomId else nil, view.Plot:GetAttribute("OwnerUserId") or 0, (i - 1) * 0.2, d.Kind == "Blueprint")
			end
		end
		if type(e.Xp) == "number" and e.Xp > 0 then
			floatText(pos + Vector3.new(0, 4.6, 0), "+" .. e.Xp .. " XP", Color3.fromRGB(170, 160, 255), "XpFloat")
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
	Bus.RoomAwarded:Connect(function(result)
		local root = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and type(result) == "table" and type(result.RoomId) == "string" then
			local def = Catalog.Room(result.RoomId)
			if def then
				dropOrb(root.Position + root.CFrame.LookVector * 4, RARITY_COLOR[def.Rarity] or Theme.Gold, "Box", result.RoomId, Players.LocalPlayer.UserId, 0, false)
			end
		end
	end)

	Net.OnEvent("EncounterFx", function(e)
		if Catalog.Current then -- before the catalog arrives there is nothing to animate
			onFx(e)
		end
	end)

	task.spawn(function()
		Catalog.Wait()
		local folder = workspace:WaitForChild("Plots")
		for _, p in folder:GetChildren() do
			addPlot(p)
		end
		folder.ChildAdded:Connect(addPlot)
		folder.ChildRemoved:Connect(removePlot)
	end)

	RunService.Heartbeat:Connect(function(dt)
		if Catalog.Current == nil then
			return
		end
		if #shimmerBars > 0 and not Settings.Reduced() then
			local t = os.clock()
			for i, bar in shimmerBars do
				local c = Color3.fromHSV((t * 0.15 + i * 0.12) % 1, 0.45, 1)
				if bar:IsA("ImageLabel") then
					bar.ImageColor3 = c
				else
					bar.Color = c
				end
			end
		end
		for _, view in views do
			local ok, err = pcall(stepView, view, dt)
			if not ok then
				warn("[PlotView] " .. tostring(err))
			end
		end
	end)
end

return View
