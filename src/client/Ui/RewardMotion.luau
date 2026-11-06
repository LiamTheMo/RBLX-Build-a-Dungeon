-- Cosmetic path for a reward flying to the player's current position.
local RewardMotion = {}

function RewardMotion.Position(start: Vector3, target: Vector3, progress: number): Vector3
	local t = math.clamp(progress, 0, 1)
	local p = t * t
	local height = math.clamp((target - start).Magnitude * 0.22, 1.5, 5)
	return start + (target - start) * p + Vector3.new(0, 4 * height * p * (1 - p), 0)
end

return RewardMotion
