-- Loot tab: boxes with real odds + pity, open reveal, blueprints, scrap.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Balance = require(Shared.Definitions.Balance)
local Rooms = require(Shared.Definitions.Rooms)
local Loot = require(Shared.Rules.Loot)
local ReasonText = require(Shared.UI.ReasonText)

local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)
local P = require(script.Parent.PanelsKit)
local Settings = require(script.Parent.Settings)
local Theme = require(script.Parent.Theme)
local Toast = require(script.Parent.Toast)

local make = Kit.Make
local L = {}

local busy = false
local confirming: { [string]: number } = {} -- instanceId -> expiry (os.clock)

local function roomName(id: string): string
	local def = Rooms.Get(id)
	return def and def.DisplayName or P.Spaced(id)
end

local function oddsText(odds: any): (string, string)
	local r, rooms = {}, {}
	for _, e in odds.Rarities do
		table.insert(r, P.Rich(e.Id, e.Id) .. " " .. P.Pct(e.Chance))
	end
	for _, e in odds.Rooms do
		if e.Chance > 0 then
			table.insert(rooms, roomName(e.Id) .. " " .. P.Pct(e.Chance))
		end
	end
	return "Rarity: " .. table.concat(r, ", "), "Rooms: " .. table.concat(rooms, ", ")
end

-- Reveal: shake a closed box (~0.8 s), then show room, rarity and perks. Instant when motion is reduced.
local function reveal(overlay: Instance, box: string, result: any)
	local gui = make("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, Size = UDim2.fromScale(1, 1), ZIndex = 10, Active = true }, overlay)
	local card = Kit.Panel(gui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(340, 300), ZIndex = 11 })
	local stroke = card:FindFirstChildOfClass("UIStroke")
	local scale = make("UIScale", {}, card)
	local reduced = Settings.Reduced()
	local color = P.RarityColor[result.Rarity] or Theme.TextPrimary

	local function label(text: string, size: number, c: Color3, y: number, h: number, heading: boolean)
		local l = Kit.Label(card, text, size, c, heading)
		l.Position = UDim2.fromOffset(12, y)
		l.Size = UDim2.new(1, -24, 0, h)
		l.ZIndex = 12
		return l
	end

	local function show()
		stroke.Color, stroke.Thickness = color, 5
		label(string.upper(tostring(result.Rarity)), Theme.TextSize.Heading, color, 16, 32, true)
		label(roomName(result.RoomId), Theme.TextSize.Title, Theme.TextPrimary, 54, 44, true)
		local perks = P.PerkText(result.Perks)
		label(if perks ~= "" then perks else "No perks", Theme.TextSize.Body, if perks ~= "" then Theme.Success else Theme.TextMuted, 106, 56, false)
		label("Added to your unplaced rooms.", Theme.TextSize.Caption, Theme.TextMuted, 170, 24, false)
		local done = Kit.Button(card, { Text = "Nice!", Style = "Primary", Size = UDim2.fromOffset(200, 56), OnClick = function()
			gui:Destroy()
		end })
		done.Instance.AnchorPoint = Vector2.new(0.5, 1)
		done.Instance.Position = UDim2.new(0.5, 0, 1, -16)
		done.Instance.ZIndex = 12
		if not reduced then
			scale.Scale = 0.7
			Settings.Tween(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		end
	end

	if reduced then
		show()
		return
	end
	local q = label("?", 96, Theme.Gold, 70, 120, true)
	label(box .. " Box", Theme.TextSize.Heading, Theme.TextPrimary, 20, 32, true)
	local t = Settings.Tween(q, TweenInfo.new(0.1, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, 4, true), { Rotation = 12 })
	task.delay(0.85, function()
		if t then
			t:Cancel()
		end
		if gui.Parent then
			for _, c in card:GetChildren() do
				if c:IsA("TextLabel") then
					c:Destroy()
				end
			end
			show()
		end
	end)
end

local function run(remote: string, arg: string, onOk: (any) -> ())
	if busy then
		return
	end
	busy = true
	local ok, res = Net.Invoke(remote, arg)
	busy = false
	if ok then
		onOk(res)
	else
		Toast.Show(ReasonText.Get(res), "Bad")
	end
end

function L.Build(scroll: ScrollingFrame, state: any, overlay: Instance)
	local pos = P.Reset(scroll)
	local order = 0
	local function nxt(): number
		order += 1
		return order
	end

	P.Section(scroll, "Boxes", nxt())
	for _, boxType in Loot.BoxTypes do
		local count = (state.Boxes or {})[boxType] or 0
		local card = P.Card(scroll, nxt())
		local _, _, open = P.Row(card, string.format("%s Box x%d", boxType, count), { Text = "Open", Style = "Primary", Width = 120, OnClick = function()
			run("OpenBox", boxType, function(res)
				if type(res) == "table" then
					reveal(overlay, boxType, res)
				end
			end)
		end })
		open.SetEnabled(count > 0, if count > 0 then nil else "None")
		local odds = Loot.Odds(boxType, state.BoxPity or 0, state.Level or 1)
		if odds then
			local rText, roomText = oddsText(odds)
			P.Text(card, rText, Theme.TextSize.Body, Theme.TextPrimary, false, 2)
			P.Text(card, roomText, Theme.TextSize.Caption, Theme.TextMuted, false, 3)
			local top = odds.PityAfter + 1
			local pity = math.clamp(state.BoxPity or 0, 0, top)
			local bar = Kit.Bar(card, UDim2.new(1, 0, 0, 24))
			bar.Instance.LayoutOrder = 4
			bar.Set(pity / top, string.format("Pity %d / %d", pity, top))
			P.Text(card, string.format("Your %dth box in a row without %s or better is at least %s.", top, odds.PityRarity, odds.PityRarity), Theme.TextSize.Caption, Theme.TextMuted, false, 5)
		end
	end

	P.Section(scroll, "Blueprints", nxt())
	local cost = Balance.Loot.CraftCost
	P.Text(scroll, string.format("%d blueprints of one room craft it at Common rarity.", cost), Theme.TextSize.Body, Theme.TextMuted, false, nxt())
	for _, id in Rooms.Order do
		if Loot.Craftable(id) then
			local n = (state.Blueprints or {})[id] or 0
			local card = P.Card(scroll, nxt())
			local _, _, craft = P.Row(card, string.format("%s  %d/%d", roomName(id), math.min(n, cost), cost), { Text = "Craft", Style = "Primary", Width = 120, OnClick = function()
				run("CraftBlueprint", id, function()
					Toast.Show(roomName(id) .. " crafted.", "Good")
				end)
			end })
			craft.SetEnabled(n >= cost, if n >= cost then nil else "Need " .. (cost - n))
		end
	end

	P.Section(scroll, "Unplaced rooms", nxt())
	local placed = {}
	for _, instanceId in state.Layout or {} do
		placed[instanceId] = true
	end
	local list = {}
	for instanceId, room in state.Rooms or {} do
		if not placed[instanceId] and Loot.Craftable(room.Id) then
			table.insert(list, { InstanceId = instanceId, Room = room })
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = Loot.RarityRank(a.Room.Rarity) or 0, Loot.RarityRank(b.Room.Rarity) or 0
		if ra ~= rb then
			return ra > rb
		end
		if a.Room.Id ~= b.Room.Id then
			return a.Room.Id < b.Room.Id
		end
		return a.InstanceId < b.InstanceId
	end)
	if #list == 0 then
		P.Text(scroll, "No spare rooms. Rooms you are not using appear here.", Theme.TextSize.Body, Theme.TextMuted, false, nxt())
	else
		P.Text(scroll, string.format("Scrapping a spare room gives %d blueprints of its type.", Balance.Loot.ScrapReturn), Theme.TextSize.Body, Theme.TextMuted, false, nxt())
	end
	for _, e in list do
		local room = e.Room
		local perks = P.PerkText(room.Perks)
		local text = string.format("%s %s  Lv %d%s", roomName(room.Id), P.Rich("[" .. tostring(room.Rarity) .. "]", room.Rarity), room.Level or 1, if perks ~= "" then "\n" .. perks else "")
		local card = P.Card(scroll, nxt())
		local btn
		_, _, btn = P.Row(card, text, { Text = "Scrap", Style = "Danger", Width = 130, OnClick = function()
			if (confirming[e.InstanceId] or 0) < os.clock() then
				confirming[e.InstanceId] = os.clock() + 3
				btn.SetText("Tap again")
				task.delay(3.1, function()
					if btn.Instance.Parent then
						btn.SetText("Scrap")
					end
				end)
				return
			end
			confirming[e.InstanceId] = nil
			run("ScrapRoom", e.InstanceId, function()
				Toast.Show(string.format("Scrapped: +%d blueprints.", Balance.Loot.ScrapReturn), "Good")
			end)
		end })
		if (confirming[e.InstanceId] or 0) > os.clock() then
			btn.SetText("Tap again")
		end
	end
	task.defer(function()
		scroll.CanvasPosition = pos
	end)
end

return L
