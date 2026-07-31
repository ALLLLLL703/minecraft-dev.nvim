local version_data = require("minecraft-dev.generators.neoforge.version_data")

local M = {}

local function prompt(key)
	return require("minecraft-dev").config.prompts.neoforge[key]
end

---@param descriptor table
---@param properties table
---@param callback fun(value: table?, err: table?)
---@param system? fun(command: string[], options: table, callback: fun(result: table)): table
---@return table?, table?
function M.select(descriptor, properties, callback, system)
	if type(callback) ~= "function" then
		return nil, { code = "callback_required" }
	end
	local property_name = descriptor.parameters and descriptor.parameters.minecraftVersionProperty
	local selected = property_name and properties[property_name]
	local minecraft = type(selected) == "table" and (selected.minecraft or selected.minecraftVersion) or selected
	if type(minecraft) ~= "string" then
		return nil, { code = "missing_field", field = property_name or "minecraft_version" }
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
	vim.ui.select({ true, false }, { prompt = prompt("use_parchment"), format_item = tostring }, function(enabled)
		if operation.status ~= "pending" then
			return
		end
		if enabled == nil then
			finish(nil, { code = "cancelled" })
			return
		end
		if not enabled then
			finish({ use = false, minecraftVersion = minecraft })
			return
		end
		local load_error
		child, load_error = version_data.load_parchment(minecraft, function(values, err)
			if not values then
				finish(nil, err)
				return
			end
			vim.ui.select(values, { prompt = prompt("parchment_version") }, function(value)
				if operation.status ~= "pending" then
					return
				end
				if value == nil then
					finish(nil, { code = "cancelled" })
				else
					finish({ use = true, version = value, minecraftVersion = minecraft })
				end
			end)
		end, system)
		if load_error then
			finish(nil, load_error)
		end
	end)
	return operation, nil
end

return M
