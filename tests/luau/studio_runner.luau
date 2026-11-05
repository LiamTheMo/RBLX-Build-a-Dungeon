-- Runs every spec bundle in Studio (Edit mode, command bar or Studio MCP execute_luau).
-- Needs `python tests/luau/run.py --studio` and a local file server on build/specs:
--   cd build/specs && python -m http.server 8765 --bind 127.0.0.1   (not --directory: 501 on Python 3.15 here)
-- Bundles only run through loadstring; nothing in the place is changed.
-- Optional filter: set FILTER to a spec name prefix before running.

local FILTER = nil
local HttpService = game:GetService("HttpService")
local base = "http://127.0.0.1:8765/"
local lines, failedFiles = {}, 0
for name in HttpService:GetAsync(base .. "index.txt", true):gmatch("[^\r\n]+") do
	if FILTER == nil or name:sub(1, #FILTER) == FILTER then
		local out = {}
		local fn, err = loadstring(
			"local print = function(...) local t = table.pack(...) for i = 1, t.n do t[i] = tostring(t[i]) end table.insert(__OUT, table.concat(t, ' ')) end\n"
				.. HttpService:GetAsync(base .. name, true)
		)
		if not fn then
			table.insert(out, "COMPILE ERROR " .. name .. ": " .. tostring(err))
		else
			-- Own environment per bundle: each prelude replaces `game` and `require`.
			setfenv(fn, setmetatable({ __OUT = out }, { __index = getfenv(0) }))
			local ok, rerr = pcall(fn)
			if not ok then
				table.insert(out, "RUNTIME ERROR " .. name .. ": " .. tostring(rerr))
			end
		end
		local text = table.concat(out, "\n")
		if text:find("SPEC FAILED") or text:find("ERROR") then
			failedFiles += 1
			table.insert(lines, text) -- full detail only for failures
		else
			table.insert(lines, (text:match("[^\n]*passed$") or text:match("([^\n]*)$")))
		end
	end
end
table.insert(lines, failedFiles == 0 and "ALL SPEC FILES PASSED" or (failedFiles .. " SPEC FILE(S) FAILED"))
return table.concat(lines, "\n")
