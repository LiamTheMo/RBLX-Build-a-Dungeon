-- The pure request guard behind Net: rate limit, argument check, ready check,
-- handler errors.

local RemoteGuard = require(game:GetService("ServerScriptService").Server.Infrastructure.RemoteGuard)

local function setup(ready)
	local clock = { now = 0 }
	local guard = RemoteGuard.new({
		clock = function()
			return clock.now
		end,
		ready = ready or function()
			return true
		end,
		warn = function() end,
	})
	return guard, clock
end

local isBool = function(on)
	return type(on) == "boolean"
end
local okHandler = function()
	return true, "done"
end

test("a valid request reaches the handler and returns its result", function()
	local guard = setup()
	local ok, data = guard:Call("p", "SetBuilding", isBool, okHandler, true)
	expect(ok, "ok")
	expectEq(data, "done", "data")
end)

test("rapid requests are rate limited at the burst and refill over time", function()
	local guard, clock = setup()
	local passed = 0
	for _ = 1, 40 do
		local ok, reason = guard:Call("p", "Bank", isBool, okHandler, true)
		if ok then
			passed += 1
		else
			expectEq(reason, "RateLimited", "reason")
		end
	end
	expectEq(passed, RemoteGuard.BURST, "only the burst passes")
	clock.now += 1
	local again = 0
	for _ = 1, 40 do
		if guard:Call("p", "Bank", isBool, okHandler, true) then
			again += 1
		end
	end
	expectEq(again, RemoteGuard.RATE, "refill of one second")
end)

test("limits are per player and per remote", function()
	local guard = setup()
	for _ = 1, 30 do
		guard:Call("p", "Bank", isBool, okHandler, true)
	end
	expect(guard:Call("q", "Bank", isBool, okHandler, true), "other player unaffected")
	expect(guard:Call("p", "Buy", isBool, okHandler, true), "other remote unaffected")
	guard:Forget("p")
	expect(guard:Call("p", "Bank", isBool, okHandler, true), "bucket reset after leaving")
end)

test("bad arguments are refused before the handler runs", function()
	local guard = setup()
	local ran = false
	local handler = function()
		ran = true
		return true
	end
	for _, args in { { "x" }, { nil }, {}, { 1, 2 }, { {} } } do
		local ok, reason = guard:Call("p", "SetBuilding", isBool, handler, table.unpack(args, 1, 2))
		expect(not ok and reason == "BadArgs", "refused: " .. tostring(reason))
	end
	local ok, reason = guard:Call("p", "X", function()
		error("boom")
	end, handler, 1)
	expect(not ok and reason == "BadArgs", "throwing check is refused")
	local tooMany = guard:Call("p", "Y", function()
		return true
	end, handler, 1, 2, 3, 4, 5, 6, 7, 8, 9)
	expect(not tooMany, "too many args refused")
	expect(not ran, "handler never ran")
end)

test("check must return exactly true", function()
	local guard = setup()
	local _, reason = guard:Call("p", "X", function()
		return 1
	end, okHandler)
	expectEq(reason, "BadArgs", "truthy but not true")
end)

test("requests are refused while the profile is not ready", function()
	local loaded = false
	local guard = setup(function()
		return loaded
	end)
	local ok, reason = guard:Call("p", "Bank", isBool, okHandler, true)
	expect(not ok and reason == "ProfileNotLoaded", "refused")
	loaded = true
	expect(guard:Call("p", "Bank", isBool, okHandler, true), "accepted once ready")
end)

test("guard order: rate limit before args, args before ready", function()
	local guard = setup(function()
		return false
	end)
	local _, reason = guard:Call("p", "Bank", isBool, okHandler, "bad")
	expectEq(reason, "BadArgs", "args before ready")
	for _ = 1, RemoteGuard.BURST do
		guard:Call("p", "Bank", isBool, okHandler, "bad")
	end
	local _, limited = guard:Call("p", "Bank", isBool, okHandler, "bad")
	expectEq(limited, "RateLimited", "rate limit first")
end)

test("a handler that errors yields Busy and does not break later calls", function()
	local guard = setup()
	local ok, reason = guard:Call("p", "Bank", isBool, function()
		error("oops")
	end, true)
	expect(not ok and reason == "Busy", "Busy")
	expect(guard:Call("p", "Bank", isBool, okHandler, true), "next call fine")
	local refused, why = guard:Call("p", "Bank", isBool, function()
		return false, "NotEnough"
	end, true)
	expect(not refused and why == "NotEnough", "handler refusal passes through")
end)
