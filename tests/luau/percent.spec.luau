local Ui = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Ui
local Percent = require(Ui.Percent)
test("rare drop chances stay visible when formatted", function()
	expectEq(Percent.Format(0), "0%", "zero")
	expectEq(Percent.Format(0.6), "60%", "whole percent")
	expectEq(Percent.Format(0.0002), "0.02%", "rare tier")
	expectEq(Percent.Format(0.000001), "0.0001%", "small drop")
	expect(Percent.Format(1e-12) ~= "0%", "positive chance never shown as zero")
end)
