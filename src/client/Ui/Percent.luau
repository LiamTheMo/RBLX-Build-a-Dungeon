-- Format probabilities without rounding a non-zero drop chance down to zero.
local Percent = {}
function Percent.Format(f: number): string
	local value = math.max(0, f * 100)
	if value == 0 then return "0%" end
	if value < 1e-8 then return string.format("%.2g%%", value) end
	local digits = if value >= 1 then 1 else math.clamp(math.ceil(-math.log(value) / math.log(10)) + 1, 2, 8)
	local text = string.format("%." .. digits .. "f", value)
	text = string.gsub(string.gsub(text, "(%..-)0+$", "%1"), "%.$", "")
	return text .. "%"
end
return table.freeze(Percent)
