-- Loads every ModuleScript under a container as a Service/Controller and
-- drives its optional Init()/Start() lifecycle. Adding a new Service or
-- Controller is just adding a file under the relevant folder -- nothing
-- else has to change.

export type Module = {
	Init: (() -> ())?,
	Start: (() -> ())?,
	[any]: any,
}

local Loader = {}

function Loader.LoadChildren(container: Instance): { Module }
	local children = container:GetChildren()
	table.sort(children, function(a, b)
		return a.Name < b.Name
	end)

	local modules = {}
	for _, child in children do
		if child:IsA("ModuleScript") then
			local module = require(child) :: Module
			module._loaderName = child.Name
			table.insert(modules, module)
		end
	end

	return modules
end

-- Each module's Init/Start runs in its own pcall so one broken
-- Service/Controller can't silently stop the rest from loading.
function Loader.Init(modules: { Module })
	for _, module in modules do
		if module.Init then
			local ok, err = pcall(module.Init)
			if not ok then
				warn(("[Loader] %s.Init failed: %s"):format(module._loaderName or "?", tostring(err)))
			end
		end
	end
end

function Loader.Start(modules: { Module })
	for _, module in modules do
		if module.Start then
			local ok, err = pcall(module.Start)
			if not ok then
				warn(("[Loader] %s.Start failed: %s"):format(module._loaderName or "?", tostring(err)))
			end
		end
	end
end

return Loader
