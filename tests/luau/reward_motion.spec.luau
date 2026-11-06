local Ui = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Ui
local RewardMotion = require(Ui.RewardMotion)

test("reward flight arcs to the current target and clamps its endpoints", function()
	local start, target = Vector3.new(0, 0, 0), Vector3.new(12, 0, 0)
	expectEq(RewardMotion.Position(start, target, -1), start, "starts at the reward")
	expectEq(RewardMotion.Position(start, target, 1), target, "lands at the target")
	expectEq(RewardMotion.Position(start, target, 2), target, "clamps after arrival")
	local halfway = RewardMotion.Position(start, target, 0.5)
	expect(halfway.Y > 0 and halfway.X > 0 and halfway.X < target.X, "curves above the path")
	local moved = Vector3.new(20, 3, -4)
	expectEq(RewardMotion.Position(start, moved, 1), moved, "lands at the moved target")
end)
