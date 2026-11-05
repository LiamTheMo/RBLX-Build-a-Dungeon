--!nocheck
-- Minimal stand-ins for the Roblox environment, just enough for pure-logic
-- modules under src/shared and src/server to load and run in the standalone
-- Luau CLI. See run.py for how this is bundled with the modules and a spec.

-- Datatypes ------------------------------------------------------------------

local Vector3Meta = {}
Vector3Meta.__index = function(v, key)
	if key == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	end
	return Vector3Meta[key]
end
Vector3 = {}
function Vector3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3Meta)
end
Vector3.zero = Vector3.new(0, 0, 0)
Vector3Meta.__add = function(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
Vector3Meta.__sub = function(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
Vector3Meta.__mul = function(a, b)
	if type(a) == "number" then
		a, b = b, a
	end
	return Vector3.new(a.X * b, a.Y * b, a.Z * b)
end
Vector3Meta.__div = function(a, b)
	return Vector3.new(a.X / b, a.Y / b, a.Z / b)
end
function Vector3Meta:Dot(other)
	return self.X * other.X + self.Y * other.Y + self.Z * other.Z
end
Vector3Meta.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end

local Color3Meta = {}
Color3Meta.__index = Color3Meta
Color3 = {}
function Color3.new(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3Meta)
end
function Color3.fromRGB(r, g, b)
	return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
function Color3Meta:Lerp(other, t)
	return Color3.new(self.R + (other.R - self.R) * t, self.G + (other.G - self.G) * t, self.B + (other.B - self.B) * t)
end

-- Enum.KeyCode.F -> "KeyCode.F": distinct, comparable values are all specs need.
Enum = setmetatable({}, {
	__index = function(_, enumName)
		return setmetatable({}, {
			__index = function(_, itemName)
				return enumName .. "." .. itemName
			end,
		})
	end,
})

-- Deterministic Random (xorshift32) so distribution specs are reproducible.
local RandomMeta = {}
RandomMeta.__index = RandomMeta
Random = {}
function Random.new(seed)
	local state = math.floor(seed or 1) % 4294967296
	if state == 0 then
		state = 2463534242
	end
	return setmetatable({ _state = state }, RandomMeta)
end
function RandomMeta:_next()
	local x = self._state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self._state = x
	return x
end
function RandomMeta:NextNumber(min, max)
	local unit = self:_next() / 4294967296
	if min == nil then
		return unit
	end
	return min + (max - min) * unit
end
function RandomMeta:NextInteger(min, max)
	return min + (self:_next() % (max - min + 1))
end

-- Instance tree + require -------------------------------------------------------

local loaders = {}
local cache = {}

local function makeNode(path)
	return setmetatable({ __path = path }, {
		__index = function(self, name)
			if name == "Parent" then
				local parent = table.clone(path)
				table.remove(parent)
				return makeNode(parent)
			end
			local child = table.clone(path)
			table.insert(child, name)
			return makeNode(child)
		end,
	})
end

function __defineModule(path, loader)
	loaders[table.concat(path, "/")] = { path = path, loader = loader }
end

local builtinRequire = require
function require(node)
	if type(node) ~= "table" or node.__path == nil then
		return builtinRequire(node)
	end
	local key = table.concat(node.__path, "/")
	if cache[key] == nil then
		local entry = loaders[key]
		assert(entry, "no module at " .. key)
		cache[key] = entry.loader(makeNode(entry.path))
	end
	return cache[key]
end

game = {
	GetService = function(_, name)
		return makeNode({ name })
	end,
}

-- Spec runner -------------------------------------------------------------------

local currentFailures = 0

function expect(condition, message)
	if not condition then
		currentFailures += 1
		print("    FAIL: " .. tostring(message))
	end
end

function expectEq(actual, expected, message)
	expect(
		actual == expected,
		tostring(message) .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")"
	)
end

function expectNear(actual, expected, tolerance, message)
	expect(
		math.abs(actual - expected) <= tolerance,
		tostring(message) .. " (expected ~" .. tostring(expected) .. ", got " .. tostring(actual) .. ")"
	)
end

local cases = {}
function test(name, fn)
	table.insert(cases, { name = name, fn = fn })
end

function __runSpec(specName, body)
	body()
	local failedCases = 0
	for _, case in cases do
		currentFailures = 0
		local ok, err = pcall(case.fn)
		if not ok then
			currentFailures += 1
			print("    ERROR: " .. tostring(err))
		end
		if currentFailures > 0 then
			failedCases += 1
			print("  x " .. case.name)
		else
			print("  ok " .. case.name)
		end
	end
	print(("%s: %d/%d passed"):format(specName, #cases - failedCases, #cases))
	if failedCases > 0 then
		print("SPEC FAILED: " .. specName)
	end
end
