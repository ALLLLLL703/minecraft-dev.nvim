local notify = require("minecraft-dev.util.notify")
local version = require("minecraft-dev.version")
local version_data = require("minecraft-dev.generators.fabric.version_data")

local M = {}

local function prompt(key)
	return require("minecraft-dev").config.prompts.fabric[key]
end

---@param descriptor table
---@param callback fun(value: table?, err: table?)
---@param system? fun(command: string[], options: table, callback: fun(result: table)): table
---@return table?, table?
function M.select(descriptor, callback, system)
	if type(callback) ~= "function" then return nil, { code = "callback_required" } end
	local operation = { status = "pending", callbacks = {} }
	local child
	local warnings = {}
	function operation.on_complete(completion_callback)
		if operation.result then completion_callback(operation.result) else table.insert(operation.callbacks, completion_callback) end
		return operation
	end
	local function finish(value, err, cancelled)
		if operation.status ~= "pending" then return end
		operation.status = cancelled and "cancelled" or err and "failed" or "generated"
		operation.result = { status = operation.status, error = err, warnings = #warnings > 0 and warnings or nil }
		callback(value, err, #warnings > 0 and warnings or nil)
		for _, completion_callback in ipairs(operation.callbacks) do completion_callback(operation.result) end
		operation.callbacks = {}
	end
	function operation.cancel()
		if operation.status ~= "pending" then return end
		operation.cancel_requested = true
		if child and child.status == "pending" and child.cancel then child.cancel()
		else finish(nil, { code = "cancelled" }, true) end
	end

	local function choose(items, key, next_step, format_item)
		vim.ui.select(items, { prompt = prompt(key), format_item = format_item }, function(value)
			if operation.status ~= "pending" then return end
			if value == nil then finish(nil, { code = "cancelled" }, true) else next_step(value) end
		end)
	end

	local load_error
	child, load_error = version_data.load_catalog(function(catalog, catalog_warning)
		if operation.status ~= "pending" then return end
		if not catalog then
			local err = catalog_warning or { code = "property_response_empty", property_type = descriptor.type }
			finish(nil, err, err.code == "cancelled")
			return
		end
		if catalog_warning then table.insert(warnings, catalog_warning) end
		choose({ false, true }, "show_snapshots", function(show_snapshots)
			local minecraft_versions = version_data.minecraft_versions(catalog, show_snapshots)
			if #minecraft_versions == 0 then finish(nil, { code = "property_response_empty", property_type = descriptor.type }) return end
			choose(minecraft_versions, "minecraft_version", function(minecraft_version)
				choose(catalog.loom, "loom_version", function(loom)
					choose(catalog.loader, "loader_version", function(loader)
						local yarn_versions, yarn_exact = version_data.yarn_versions(catalog, minecraft_version)
						local api_versions, api_exact = version_data.fabric_api_versions(catalog, minecraft_version)
						if #yarn_versions == 0 or #api_versions == 0 then
							finish(nil, { code = "property_response_empty", property_type = descriptor.type })
							return
						end
						local function choose_mappings(use_official_mappings)
							local function choose_api(yarn)
								choose({ true, false }, "use_fabric_api", function(use_fabric_api)
									local function complete(fabric_api)
										finish({
											minecraftVersion = minecraft_version,
											loom = loom,
											loader = loader,
											yarn = yarn,
											useFabricApi = use_fabric_api,
											fabricApi = fabric_api,
											useOfficialMappings = use_official_mappings,
										})
									end
									if not use_fabric_api then complete(api_versions[1]) return end
									if not api_exact then notify.notify(vim.log.levels.WARN, { "fabric", "no_matching_api" }, minecraft_version) end
									choose(api_versions, "fabric_api_version", complete)
								end, tostring)
							end
							if use_official_mappings then choose_api(yarn_versions[1]) return end
							if not yarn_exact then notify.notify(vim.log.levels.WARN, { "fabric", "no_matching_yarn" }, minecraft_version) end
							choose(yarn_versions, "yarn_version", choose_api, function(item) return item.name end)
						end
						if version.at_least(minecraft_version, 26, 1) then choose_mappings(true)
						else choose({ true, false }, "use_official_mappings", choose_mappings, tostring) end
					end)
				end)
			end)
		end, tostring)
	end, system)
	if load_error then finish(nil, load_error) end
	return operation, nil
end

return M
