local version = require("minecraft-dev.version")
local version_data = require("minecraft-dev.generators.neoforge.version_data")

local M = {}

local function prompt(key)
	return require("minecraft-dev").config.prompts.neoforge[key]
end

---@param descriptor table
---@param callback fun(value: table?, err: table?)
---@param system? fun(command: string[], options: table, callback: fun(result: table)): table
---@return table?, table?
function M.select(descriptor, callback, system)
	if type(callback) ~= "function" then
		return nil, { code = "callback_required" }
	end
	local operation = { status = "pending", callbacks = {} }
	local child
	function operation.on_complete(completion_callback)
		if operation.result then
			completion_callback(operation.result)
		else
			table.insert(operation.callbacks, completion_callback)
		end
		return operation
	end
	local function finish(value, err)
		if operation.status ~= "pending" then
			return
		end
		operation.status = err and err.code == "cancelled" and "cancelled" or err and "failed" or "generated"
		operation.result = { status = operation.status, error = err }
		callback(value, err)
		for _, completion_callback in ipairs(operation.callbacks) do
			completion_callback(operation.result)
		end
		operation.callbacks = {}
	end
	function operation.cancel()
		if operation.status ~= "pending" then
			return
		end
		if child and child.status == "pending" and child.cancel then
			child.cancel()
		else
			finish(nil, { code = "cancelled" })
		end
	end
	local function choose(items, key, next_step)
		vim.ui.select(items, { prompt = prompt(key) }, function(value)
			if operation.status ~= "pending" then
				return
			end
			if value == nil then
				finish(nil, { code = "cancelled" })
			else
				next_step(value)
			end
		end)
	end
	local load_error
	child, load_error = version_data.load(function(catalog, err)
		if not catalog then
			finish(nil, err or { code = "property_response_empty", property_type = descriptor.type })
			return
		end
		choose(catalog.minecraft, "minecraft_version", function(minecraft)
			choose(catalog.neoforge[minecraft] or {}, "loader_version", function(neoforge)
				local plugin_versions = (version.compare(minecraft, "1.21") or -1) >= 0 and catalog.moddev
					or catalog.neogradle
				local key = (version.compare(minecraft, "1.21") or -1) >= 0 and "moddev_version" or "neogradle_version"
				choose(plugin_versions, key, function(plugin)
					local neogradle = key == "neogradle_version" and plugin or catalog.neogradle[1]
					local moddev = key == "moddev_version" and plugin or catalog.moddev[1]
					finish(version_data.derive(minecraft, neoforge, neogradle, moddev))
				end)
			end)
		end)
	end, system)
	if load_error then
		finish(nil, load_error)
	end
	return operation, nil
end

return M
