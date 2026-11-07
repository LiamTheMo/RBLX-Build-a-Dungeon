-- Tap an owned placed room to identify it and inspect server-supplied base stats.
-- This only reads the replicated layout and requests the normal vault UI.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Ui = script.Parent.Parent.Ui
local Bus = require(Ui.Bus)
local Catalog = require(Ui.Catalog)
local Cells = require(Ui.Cells)
local Kit = require(Ui.Kit)
local Modal = require(Ui.Modal)
local P = require(Ui.PanelsKit)
local Plots = require(Ui.Plots)
local State = require(Ui.State)
local Theme = require(Ui.Theme)
local make = Kit.Make
local Controller = {}

function Controller.Start()
	task.spawn(function()
		Catalog.Wait()
		local plot = Plots.WaitOwn()
		local gui = Kit.Screen("RoomInspector", 24)
		local modal = Modal.New(gui, "Room", "Defender", Vector2.new(540, 340), Vector2.new(510, 290))
		local selected: string? = nil
		local function fill()
			for _, child in modal.Body:GetChildren() do child:Destroy() end
			local state = State.Current
			local instanceId = selected and state and state.Layout and state.Layout[selected]
			local room = instanceId and state.Rooms and state.Rooms[instanceId]
			local def = room and Catalog.Room(room.Id)
			if not def then modal.Close(); return end
			modal.Title.Text = def.DisplayName
			local root = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, modal.Body)
			local image = P.RoomImage(root, room.Id, 84, def.Kind)
			image.Position = UDim2.fromOffset(4, 4)
			local info = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(100, 4), Size = UDim2.new(1, -100, 0, 86) }, root)
			make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, info)
			P.IconLine(info, P.KindIcon[def.Kind] or "Defender", string.format("%s  •  Lv %d", def.Kind, room.Level or 1), 1, Theme.Gold)
			local flow = P.ChipFlow(info, 2)
			P.RoomStats(flow, def)
			local ability = Kit.Label(root, def.Ability or "", Theme.TextSize.Body, Theme.TextMuted, false)
			ability.Position, ability.Size, ability.TextXAlignment = UDim2.fromOffset(4, 98), UDim2.new(1, -8, 0, 48), Enum.TextXAlignment.Left
			local roomModel = plot:FindFirstChild("Rooms") and plot.Rooms:FindFirstChild(selected)
			if roomModel and roomModel:GetAttribute("OnRoute") == false then
				ability.Text = "Idle: off the route. " .. ability.Text
			end
			if def.Kind == "Treasure" then
				local button = Kit.Button(root, { Text = "Vault", Icon = "Vault", IconLayout = "Row", Style = "Primary", Size = UDim2.fromOffset(150, 48) })
				button.Instance.AnchorPoint, button.Instance.Position = Vector2.new(1, 1), UDim2.fromScale(1, 1)
				button.Instance.Activated:Connect(function() modal.Close(); Bus.VaultRequested:Fire() end)
			end
		end
		modal.OnOpen = fill
		local starts = {}
		UserInputService.InputBegan:Connect(function(input, processed)
			if not processed and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
				starts[input] = Vector2.new(input.Position.X, input.Position.Y)
			end
		end)
		UserInputService.InputEnded:Connect(function(input, processed)
			local start = starts[input]
			starts[input] = nil
			if processed or not start or (Vector2.new(input.Position.X, input.Position.Y) - start).Magnitude > 12 then return end
			if plot:GetAttribute("State") == "Building" or (State.Current and State.Current.Building) then return end
			for _, m in Modal.All do if m.IsOpen then return end end
			local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
			if playerGui then
				for _, panels in playerGui:GetChildren() do
					if panels.Name == "Panels" and panels:IsA("ScreenGui") and panels.Enabled then return end
				end
			end
			local key = Cells.KeyAt(plot, start)
			local state = State.Current
			if key and state and state.Layout and state.Layout[key] then
				selected = key
				Bus.OpenPanel:Fire("Close")
				modal.Open()
			end
		end)
		State.Changed:Connect(function(snapshot)
			-- Snapshots may arrive frequently during play: do not replace a button
			-- while the player is pressing it.
			if modal.IsOpen and (not selected or not snapshot.Layout or not snapshot.Layout[selected]) then modal.Close() end
		end)
	end)
end
return Controller
