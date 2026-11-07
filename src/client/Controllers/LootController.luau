-- Bag and Index panels. Display and requests only: the server owns boxes, rooms, XP and coins.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Core.Signal)

local Ui = script.Parent.Parent.Ui
local Bus = require(Ui.Bus)
local PanelsCollection = require(Ui.PanelsCollection)
local PanelsKit = require(Ui.PanelsKit)
local PanelsLoot = require(Ui.PanelsLoot)
local State = require(Ui.State)
local Scale = require(Ui.Scale)

local Controller = {}

local bagShell: any
local indexShell: any
local activeShell: any
local current = "Bag"
local dirty = false

local function render()
	local state = State.Current
	if not activeShell or not activeShell.Gui.Enabled or not state then
		return
	end
	for name, scroll in activeShell.Scrolls do
		scroll.Visible = name == current
		activeShell.Tabs[name].SetSelected(name == current)
	end
	local scroll = activeShell.Scrolls[current]
	if current == "Bag" then
		PanelsLoot.Build(scroll, state)
	elseif current == "Index" then
		PanelsCollection.BuildCollection(scroll, state)
	else
		PanelsCollection.BuildKeeper(scroll, state)
	end
end

local function open(name: any)
	if name == "Close" then
		if bagShell then bagShell.Gui.Enabled = false end
		if indexShell then indexShell.Gui.Enabled = false end
		return
	end
	if name == "Bag" or name == "Loot" or name == "Chests" then
		activeShell, current = bagShell, "Bag"
	elseif name == "Index" or name == "Collection" then
		activeShell, current = indexShell, "Index"
	elseif name == "Keeper" then
		activeShell, current = indexShell, "Keeper"
	else
		return
	end
	bagShell.Gui.Enabled = activeShell == bagShell
	indexShell.Gui.Enabled = activeShell == indexShell
	render()
end

function Controller.Init()
	Bus.OpenPanel = Bus.OpenPanel or Signal.new()
end

function Controller.Start()
	State.Start()
	bagShell = PanelsKit.Shell({ "Bag" }, open)
	indexShell = PanelsKit.Shell({ "Index", "Keeper" }, open)
	Bus.OpenPanel:Connect(open)
	Scale.Changed:Connect(render)
	-- State arrives often (every hit of an encounter): rebuild at most once per frame, only while visible.
	State.Changed:Connect(function()
		if activeShell and activeShell.Gui.Enabled and not dirty then
			dirty = true
			task.defer(function()
				dirty = false
				render()
			end)
		end
	end)
end

return Controller
