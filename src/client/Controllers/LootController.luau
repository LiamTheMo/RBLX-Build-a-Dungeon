-- Bag and Index panels. Display and requests only: the server owns boxes, rooms, XP and coins.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Core.Signal)

local Ui = script.Parent.Parent.Ui
local Bus = require(Ui.Bus)
local Catalog = require(Ui.Catalog)
local PanelsCollection = require(Ui.PanelsCollection)
local PanelsKit = require(Ui.PanelsKit)
local PanelsLoot = require(Ui.PanelsLoot)
local PanelsThreat = require(Ui.PanelsThreat)
local State = require(Ui.State)
local Scale = require(Ui.Scale)

local Controller = {}

local bagShell: any
local indexShell: any
local upgradeShell: any
local activeShell: any
local threatPanel: any
local current = "Bag"
local dirty = false

local function render()
	local state = State.Current
	if not activeShell or not activeShell.Gui.Enabled or not state then
		return
	end
	activeShell.Title.Text = if current == "Bag" then "Inventory" elseif current == "Keeper" or current == "Threat" then "Upgrades" else "Index"
	for name, scroll in activeShell.Scrolls do
		scroll.Visible = name == current
		activeShell.Tabs[name].SetSelected(name == current)
	end
	local scroll = activeShell.Scrolls[current]
	if current == "Bag" then
		PanelsLoot.Build(scroll, state)
	elseif current == "Index" then
		PanelsCollection.BuildCollection(scroll, state)
	elseif current == "Threat" then
		threatPanel.Layout()
		threatPanel.Refresh()
	else
		PanelsCollection.BuildKeeper(scroll, state)
	end
end

local function open(name: any)
	if name == "Close" then
		if bagShell then bagShell.Gui.Enabled = false end
		if indexShell then indexShell.Gui.Enabled = false end
		if upgradeShell then upgradeShell.Gui.Enabled = false end
		return
	end
	if name == "Bag" or name == "Loot" or name == "Chests" then
		activeShell, current = bagShell, "Bag"
	elseif name == "Index" or name == "Collection" then
		activeShell, current = indexShell, "Index"
	elseif name == "Keeper" or name == "Threat" then
		activeShell, current = upgradeShell, name
	else
		return
	end
	bagShell.Gui.Enabled = activeShell == bagShell
	indexShell.Gui.Enabled = activeShell == indexShell
	upgradeShell.Gui.Enabled = activeShell == upgradeShell
	render()
end

function Controller.Init()
	Bus.OpenPanel = Bus.OpenPanel or Signal.new()
end

function Controller.Start()
	State.Start()
	Catalog.Wait()
	bagShell = PanelsKit.Shell({ "Bag" }, open, true)
	indexShell = PanelsKit.Shell({ "Index" }, open)
	upgradeShell = PanelsKit.Shell({ "Keeper", "Threat" }, open)
	bagShell.Gui:SetAttribute("Panel", "Bag")
	indexShell.Gui:SetAttribute("Panel", "Index")
	upgradeShell.Gui:SetAttribute("Panel", "Keeper")
	threatPanel = PanelsThreat.Build(upgradeShell.Scrolls.Threat)
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
