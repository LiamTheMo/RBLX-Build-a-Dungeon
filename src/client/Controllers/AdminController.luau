-- Admin presentation only. Every request is independently checked on the server.
local Players = game:GetService("Players")
local Ui = script.Parent.Parent.Ui
local Kit = require(Ui.Kit)
local Modal = require(Ui.Modal)
local Net = require(Ui.Net)
local Theme = require(Ui.Theme)
local Toast = require(Ui.Toast)
local make = Kit.Make
local Controller = {}

function Controller.Start()
	task.spawn(function()
		local ok, allowed = Net.Invoke("AdminAccess")
		if not ok or type(allowed) ~= "table" or type(allowed.Events) ~= "table" then return end
		local gui = Kit.Screen("AdminPanel", 35)
		local button = Kit.Button(gui, { Text = "", Icon = "AdminShield", IconScale = 0.7, Style = "Secondary", Size = UDim2.fromOffset(56, 56), Tip = "Admin" })
		if button.Icon then button.Icon.Position = UDim2.fromScale(0.5, 0.5) end
		button.Instance.AnchorPoint = Vector2.new(1, 1)
		button.Instance.Position = UDim2.new(1, -12, 1, -12)
		local panel = Modal.New(gui, "Admin", "AdminShield", Vector2.new(580, 500), Vector2.new(560, 430))
		button.Instance.Activated:Connect(function() if panel.IsOpen then panel.Close() else panel.Open() end end)
		local function newScroll()
			local f = make("ScrollingFrame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 1, -54), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 8, BorderSizePixel = 0 }, panel.Body)
			make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, f)
			return f
		end
		local scroll, eventScroll = newScroll(), newScroll()
		eventScroll.Visible = false
		local playersTab = Kit.Button(panel.Body, { Text = "Players", Icon = "AdminPlayerData", IconLayout = "Row", Style = "Tab", Size = UDim2.new(0.5, -4, 0, 48) })
		local eventsTab = Kit.Button(panel.Body, { Text = "Events", Icon = "AdminEvents", IconLayout = "Row", Style = "Tab", Size = UDim2.new(0.5, -4, 0, 48) })
		eventsTab.Instance.Position = UDim2.new(0.5, 4, 0, 0)
		local function selectTab(events)
			scroll.Visible, eventScroll.Visible = not events, events
			playersTab.SetSelected(not events)
			eventsTab.SetSelected(events)
		end
		playersTab.Instance.Activated:Connect(function() selectTab(false) end)
		eventsTab.Instance.Activated:Connect(function() selectTab(true) end)
		selectTab(false)
		local maxMinutes = allowed.MaxEventMinutes or 240
		local active = Kit.Label(eventScroll, "", 18, Theme.Gold, true)
		active.Size, active.LayoutOrder = UDim2.new(1, -12, 0, 32), 1
		local function refreshActive()
			local id = workspace:GetAttribute("ActiveEvent")
			active.Text = if type(id) == "string" and id ~= "" then "Active: " .. string.gsub(id, "(%l)(%u)", "%1 %2") else "No active event"
		end
		workspace:GetAttributeChangedSignal("ActiveEvent"):Connect(refreshActive)
		refreshActive()
		local duration = make("TextBox", { BackgroundColor3 = Theme.BgDeep, TextColor3 = Theme.TextPrimary, PlaceholderColor3 = Theme.TextMuted, PlaceholderText = "Duration in minutes (1–" .. maxMinutes .. ")", Text = "10", ClearTextOnFocus = false, FontFace = Theme.BodyFont, TextSize = 20, Size = UDim2.new(1, -12, 0, 44), LayoutOrder = 2 }, eventScroll)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, duration)
		local scope = "Server"
		local scopeRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -12, 0, 48), LayoutOrder = 3 }, eventScroll)
		local serverScope = Kit.Button(scopeRow, { Text = "This server", Style = "Tab", Size = UDim2.new(0.5, -4, 1, 0) })
		local globalScope = Kit.Button(scopeRow, { Text = "Global", Style = "Tab", Size = UDim2.new(0.5, -4, 1, 0) })
		globalScope.Instance.Position = UDim2.new(0.5, 4, 0, 0)
		local function setScope(value)
			scope = value
			serverScope.SetSelected(value == "Server")
			globalScope.SetSelected(value == "Global")
		end
		serverScope.Instance.Activated:Connect(function() setScope("Server") end)
		globalScope.Instance.Activated:Connect(function() setScope("Global") end)
		setScope("Server")
		for i, id in allowed.Events do
			local name = string.gsub(id, "(%l)(%u)", "%1 %2")
			local action = Kit.Button(eventScroll, { Text = name, Icon = id, IconLayout = "Row", Style = "Secondary", Size = UDim2.new(1, -12, 0, 48), LayoutOrder = i + 3 })
			action.Instance.Activated:Connect(function()
				local minutes = tonumber(duration.Text)
				if not minutes or minutes ~= minutes or minutes % 1 ~= 0 or minutes < 1 or minutes > maxMinutes then Toast.Show("Enter 1–" .. maxMinutes .. " whole minutes.", "Bad"); return end
				local success, result = Net.Invoke("AdminAction", "EventStart", id, minutes, scope)
				Toast.Show(tostring(result), if success then "Good" else "Bad")
			end)
		end
		local stop = Kit.Button(eventScroll, { Text = "Stop event", Icon = "AdminStopEvent", IconLayout = "Row", Style = "Danger", Size = UDim2.new(1, -12, 0, 48), LayoutOrder = #allowed.Events + 4 })
		stop.Instance.Activated:Connect(function()
			local success, result = Net.Invoke("AdminAction", "EventStop", "Server", 0, scope)
			Toast.Show(tostring(result), if success then "Good" else "Bad")
		end)
		local function input(placeholder, default, order)
			local box = make("TextBox", { BackgroundColor3 = Theme.BgDeep, TextColor3 = Theme.TextPrimary, PlaceholderColor3 = Theme.TextMuted, PlaceholderText = placeholder, Text = default, ClearTextOnFocus = false, FontFace = Theme.BodyFont, TextSize = 20, Size = UDim2.new(1, -12, 0, 44), LayoutOrder = order }, scroll)
			make("UICorner", { CornerRadius = UDim.new(0, 8) }, box)
			return box
		end
		local target = input("Online player name", Players.LocalPlayer.Name, 1)
		local amount = input("Amount (0 to 1,000,000,000)", "0", 2)
		local confirm = input("Type RESET to reset the whole profile", "", 3)
		local actions = { {"Set coins", "SetCoins"}, {"Give coins", "GiveCoins"}, {"Give XP", "GiveXp"}, {"Give Dungeon Chest", "GiveDungeon"}, {"Give Royal Chest", "GiveRare"}, {"Unlock threats (session)", "UnlockThreat"}, {"Reset all player data", "ResetProfile"} }
		for i, entry in actions do
			local action = Kit.Button(scroll, { Text = entry[1], Icon = if entry[2] == "ResetProfile" then "AdminResetData" else nil, IconLayout = "Row", Style = if entry[2] == "ResetProfile" then "Danger" else "Secondary", Size = UDim2.new(1, -12, 0, 48), LayoutOrder = i + 3 })
			action.Instance.Activated:Connect(function()
				if entry[2] == "ResetProfile" and confirm.Text ~= "RESET" then Toast.Show("Type RESET to confirm a full profile reset.", "Bad"); return end
				local n = tonumber(amount.Text)
				if not n or n ~= n or n < 0 or n > 1e9 or n % 1 ~= 0 then Toast.Show("Enter a whole amount from 0 to 1,000,000,000.", "Bad"); return end
				local token = ""
				if entry[2] == "ResetProfile" then
					local issued, result = Net.Invoke("AdminResetToken", target.Text)
					if not issued then Toast.Show(tostring(result), "Bad"); return end
					token = result
				end
				local success, result = Net.Invoke("AdminAction", entry[2], target.Text, n, token)
				Toast.Show(tostring(result or (if success then "Done" else "Request failed")), if success then "Good" else "Bad")
				if entry[2] == "ResetProfile" then confirm.Text = "" end
			end)
		end
	end)
end
return Controller
