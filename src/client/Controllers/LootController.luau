-- Loot / Collection / Keeper panels. Opened by Bus.OpenPanel:Fire("Loot" | "Collection" | "Keeper"
-- | "Close"). Display and requests only: the server owns boxes, rooms, XP and coins.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Core.Signal)

local Ui = script.Parent.Parent.Ui
local Bus = require(Ui.Bus)
local PanelsCollection = require(Ui.PanelsCollection)
local PanelsKit = require(Ui.PanelsKit)
local PanelsLoot = require(Ui.PanelsLoot)
local State = require(Ui.State)

local Controller = {}

local TABS = { "Loot", "Collection", "Keeper" }
local TITLES = { Loot = "Loot", Collection = "Collection", Keeper = "Keeper" }

local shell: any
local current = "Loot"
local dirty = false

local function render()
	local state = State.Current
	if not shell or not shell.Gui.Enabled or not state then
		return
	end
	shell.Title.Text = TITLES[current]
	for name, scroll in shell.Scrolls do
		scroll.Visible = name == current
		shell.Tabs[name].SetSelected(name == current)
	end
	local scroll = shell.Scrolls[current]
	if current == "Loot" then
		PanelsLoot.Build(scroll, state)
	elseif current == "Collection" then
		PanelsCollection.BuildCollection(scroll, state)
	else
		PanelsCollection.BuildKeeper(scroll, state)
	end
end

local function open(name: any)
	if name == "Close" then
		if shell then
			shell.Gui.Enabled = false
		end
		return
	end
	if not table.find(TABS, name) then
		return
	end
	current = name
	shell.Gui.Enabled = true
	render()
end

function Controller.Init()
	Bus.OpenPanel = Bus.OpenPanel or Signal.new()
end

function Controller.Start()
	State.Start()
	shell = PanelsKit.Shell(TABS, open)
	Bus.OpenPanel:Connect(open)
	-- State arrives often (every hit of an encounter): rebuild at most once per frame, only while visible.
	State.Changed:Connect(function()
		if shell.Gui.Enabled and not dirty then
			dirty = true
			task.defer(function()
				dirty = false
				render()
			end)
		end
	end)
end

return Controller
