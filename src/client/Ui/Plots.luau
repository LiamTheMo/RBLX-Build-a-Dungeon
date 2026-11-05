-- Finds the local player's plot (server-built, Workspace.Plots.Plot<n>).
local Players = game:GetService("Players")

local Plots = {}

local cached: Model? = nil

-- Yields until a plot with OwnerUserId == LocalPlayer.UserId exists.
function Plots.WaitOwn(): Model
	local userId = Players.LocalPlayer.UserId
	while true do
		if cached and cached.Parent and cached:GetAttribute("OwnerUserId") == userId then
			return cached
		end
		local folder = workspace:FindFirstChild("Plots")
		if folder then
			for _, plot in folder:GetChildren() do
				if plot:IsA("Model") and plot:GetAttribute("OwnerUserId") == userId then
					cached = plot
					return plot
				end
			end
		end
		task.wait(0.5)
	end
end

function Plots.RouteCells(plot: Instance): { string }
	local route = plot:GetAttribute("Route")
	if type(route) ~= "string" or route == "" then
		return {}
	end
	return string.split(route, "|")
end

return Plots
