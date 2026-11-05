--!strict
-- Which automatic visitor comes next (docs/GDD.md "Visitors"). Pure and
-- deterministic: the same profile numbers always give the same visitor, so the
-- server can announce it (plot attribute NextVisitorId) before it arrives.

local Balance = require(script.Parent.Parent.Definitions.Balance)

local VisitorRotation = {}

-- tutorialDone: Tutorial.Done. wins/encounters: profile.Stats.Wins/Encounters.
function VisitorRotation.Pick(tutorialDone: boolean, wins: number, encounters: number): string
	local r = Balance.Rotation
	if tutorialDone ~= true or type(wins) ~= "number" or wins < r.MixMinWins then
		return "Novice"
	end
	local n = if type(encounters) == "number" and encounters >= 0 then math.floor(encounters) else 0
	return r.Pattern[n % #r.Pattern + 1]
end

return VisitorRotation
