local M = {}
local evaluator = require("minecraft-dev.custom.evaluator")
local fabric_versions = require("minecraft-dev.custom.fabric_versions")
local forge_versions = require("minecraft-dev.custom.forge_versions")
local neoforge_versions = require("minecraft-dev.custom.neoforge_versions")
local parchment = require("minecraft-dev.custom.parchment")
local property_values = require("minecraft-dev.custom.property_values")
local notify = require("minecraft-dev.util.notify")

local function flatten(descriptors, output, inherited_visibility)
	for _, descriptor in ipairs(descriptors or {}) do
		if descriptor.groupProperties then
			local visibility = vim.deepcopy(inherited_visibility or {})
			if descriptor.visible ~= nil then table.insert(visibility, descriptor.visible) end
			flatten(descriptor.groupProperties, output, visibility)
		elseif descriptor.name then
			local property = vim.deepcopy(descriptor)
			property.group_visibility = vim.deepcopy(inherited_visibility or {})
			table.insert(output, property)
		end
	end
end

local function groups_visible(descriptor, properties)
	for _, group_visibility in ipairs(descriptor.group_visibility or {}) do
		if group_visibility == false then return false end
		if type(group_visibility) == "table" and group_visibility.condition
			and not evaluator.expression(properties, group_visibility.condition)
		then return false end
	end
	return true
end

local function visible(descriptor, properties)
	if not groups_visible(descriptor, properties) then return false end
	if descriptor.visible == false then return false end
	if type(descriptor.visible) == "table" and descriptor.visible.condition then
		return not not evaluator.expression(properties, descriptor.visible.condition)
	end
	return true
end

local function prompt(key, ...)
	---@type MinecraftDevConfig
	local config = require("minecraft-dev").config
	local value = config.prompts.custom[key]
	return select("#", ...) > 0 and string.format(value, ...) or value
end

local function ask_input(label, default, callback)
	vim.ui.input({ prompt = label, default = default == nil and nil or tostring(default) }, function(value)
		if value == nil then callback(nil, true) else callback(value, false) end
	end)
end

local function ask_coordinates(properties, callback)
	ask_input(prompt("group_id"), "com.example", function(group_id, cancelled)
		if cancelled then callback(true) return end
		ask_input(prompt("artifact_id"), properties.PROJECT_NAME or "example", function(artifact_id, artifact_cancelled)
			if artifact_cancelled then callback(true) return end
			ask_input(prompt("project_version"), "1.0.0", function(version, version_cancelled)
				if version_cancelled then callback(true) return end
				properties.BUILD_COORDS = { groupId = group_id, artifactId = artifact_id, version = version }
				callback(false)
			end)
		end)
	end)
end

local complex_types = {
	architectury_versions = true,
	fabric_versions = true,
	forge_versions = true,
	neoforge_versions = true,
	parchment = true,
}

local function forced_value(descriptor, properties)
	if type(descriptor.forceValue) ~= "table"
		or not evaluator.expression(properties, descriptor.forceValue.condition or "false")
	then
		return false, nil
	end
	return true, evaluator.expression(properties, tostring(descriptor.forceValue.value))
end

local function ask_version_property(descriptor, properties, callback, on_child, is_pending, transform)
	local operation, load_error = property_values.load(descriptor, function(values, err)
		if not is_pending() then return end
		if not values then callback(err and err.code == "cancelled", err) return end
		vim.ui.select(values, { prompt = prompt("property", descriptor.label or descriptor.name) }, function(value)
			if not is_pending() then return end
			if value == nil then callback(true) else properties[descriptor.name] = transform and transform(value) or value callback(false) end
		end)
	end)
	if operation and operation.status == "pending" then on_child(operation) end
	if load_error then callback(false, load_error) end
	return operation
end

local function ask_property(descriptor, properties, callback, on_child, is_pending)
	if descriptor.derives or descriptor.inheritFrom or descriptor.type == "jdk" then callback(false) return end
	if not groups_visible(descriptor, properties) then callback(false) return end
	if descriptor.visible == false and descriptor.type == "maven_artifact_version" then
		return ask_version_property(descriptor, properties, callback, on_child, is_pending)
	end
	if descriptor.visible == false and descriptor.type == "gradle_plugin" then
		return ask_version_property(descriptor, properties, callback, on_child, is_pending, function(version)
			return { enabled = false, version = version }
		end)
	end
	if not visible(descriptor, properties) then callback(false) return end
	local has_forced_value, forced = forced_value(descriptor, properties)
	if has_forced_value and descriptor.type ~= "gradle_plugin" then properties[descriptor.name] = forced callback(false) return end
	if descriptor.type == "build_system_coordinates" then ask_coordinates(properties, callback) return end
	if descriptor.options then
		vim.ui.select(descriptor.options, { prompt = prompt("property", descriptor.label or descriptor.name) }, function(value)
			if value == nil then callback(true) else properties[descriptor.name] = value callback(false) end
		end)
		return
	end
	if descriptor.type == "boolean" then
		vim.ui.select({ true, false }, { prompt = prompt("property", descriptor.label or descriptor.name), format_item = tostring }, function(value)
			if value == nil then callback(true) else properties[descriptor.name] = value callback(false) end
		end)
		return
	end
	if descriptor.type == "paper_versions" then
		return ask_version_property(descriptor, properties, callback, on_child, is_pending)
	end
	if descriptor.type == "fabric_versions" then
		local operation, select_error = fabric_versions.select(descriptor, function(value, err, warnings)
			if not is_pending() then return end
			if not value then callback(err and err.code == "cancelled", err) return end
			properties[descriptor.name] = value
			callback(false, nil, warnings)
		end)
		if operation and operation.status == "pending" then on_child(operation) end
		if select_error then callback(false, select_error) end
		return operation
	end
	if descriptor.type == "forge_versions" then
		local operation, select_error = forge_versions.select(descriptor, function(value, err)
			if not is_pending() then return end
			if not value then callback(err and err.code == "cancelled", err) return end
			properties[descriptor.name] = value
			callback(false)
		end)
		if operation and operation.status == "pending" then on_child(operation) end
		if select_error then callback(false, select_error) end
		return operation
	end
	if descriptor.type == "neoforge_versions" then
		local operation, select_error = neoforge_versions.select(descriptor, function(value, err)
			if not is_pending() then return end
			if not value then callback(err and err.code == "cancelled", err) return end
			properties[descriptor.name] = value
			callback(false)
		end)
		if operation and operation.status == "pending" then on_child(operation) end
		if select_error then callback(false, select_error) end
		return operation
	end
	if descriptor.type == "parchment" then
		local operation, select_error = parchment.select(descriptor, properties, function(value, err)
			if not is_pending() then return end
			if not value then callback(err and err.code == "cancelled", err) return end
			properties[descriptor.name] = value
			callback(false)
		end)
		if operation and operation.status == "pending" then on_child(operation) end
		if select_error then callback(false, select_error) end
		return operation
	end
	if descriptor.type == "maven_artifact_version" then
		return ask_version_property(descriptor, properties, callback, on_child, is_pending)
	end
	if descriptor.type == "gradle_plugin" then
		local function select_version(enabled)
			if not is_pending() then return end
			if not enabled then properties[descriptor.name] = { enabled = false } callback(false) return end
			ask_version_property(descriptor, properties, callback, on_child, is_pending, function(version)
				return { enabled = true, version = version }
			end)
		end
		if has_forced_value then select_version(not not forced) return end
		vim.ui.select({ true, false }, { prompt = prompt("property", descriptor.label or descriptor.name), format_item = tostring }, function(enabled)
			if not is_pending() then return end
			if enabled == nil then callback(true) return end
			select_version(enabled)
		end)
		return
	end
	local label = descriptor.label or descriptor.name
	local is_json = complex_types[descriptor.type]
	ask_input(prompt(is_json and "property_json" or "property", label), descriptor.default, function(value, cancelled)
		if cancelled then callback(true) return end
		if is_json then
			local ok, decoded = pcall(vim.json.decode, value)
			if not ok then notify.notify(vim.log.levels.ERROR, { "custom", "invalid_json" }, descriptor.name) callback(true) return end
			properties[descriptor.name] = decoded
		elseif descriptor.type == "integer" then properties[descriptor.name] = tonumber(value)
		elseif descriptor.type == "inline_string_list" then properties[descriptor.name] = vim.split(value, "%s*,%s*", { trimempty = true })
		else properties[descriptor.name] = value end
		callback(false)
	end)
end

local function collect(descriptor, properties, callback)
	local descriptors = {}
	flatten(descriptor.properties, descriptors)
	local operation = { status = "pending" }
	local active
	local warnings = {}
	local function append_warnings(values)
		for _, warning in ipairs(values or {}) do table.insert(warnings, warning) end
	end
	local function finish(values, cancelled, err)
		if operation.status ~= "pending" then return end
		operation.status = err and "failed" or cancelled and "cancelled" or "generated"
		callback(values, cancelled, err, #warnings > 0 and warnings or nil)
	end
	local function next_property(index)
		if operation.status ~= "pending" then return end
		if index > #descriptors then finish(properties, false) return end
		local previous_active = active
		local property_operation = ask_property(descriptors[index], properties, function(cancelled, err, property_warnings)
			active = nil
			append_warnings(property_warnings)
			if err and err.code ~= "cancelled" then finish(nil, false, err)
			elseif cancelled then finish(nil, true)
			else next_property(index + 1) end
		end, function(child) active = child end, function() return operation.status == "pending" end)
		if active == previous_active then active = property_operation end
	end
	function operation.cancel()
		if operation.status ~= "pending" then return end
		if active and active.status == "pending" and active.cancel then active.cancel() else finish(nil, true) end
	end
	next_property(1)
	return operation
end

local function generate(template, directory, properties, warnings, callback)
	return require("minecraft-dev").generate_template({
		provider = "builtin",
		descriptor = template.descriptor,
		directory = directory,
		properties = properties,
		use_git = properties.USE_GIT,
		callback = function(result)
			if warnings and result.status == "generated" then result.warnings = vim.deepcopy(warnings) end
			if result.status == "failed" then
				notify.notify(vim.log.levels.ERROR, { "custom", "generation_failed" }, vim.inspect(result.error))
			elseif result.status == "generated" then
				notify.notify(vim.log.levels.INFO, { "custom", "generated" }, directory)
			end
			callback(result)
		end,
	})
end

function M.run(callback)
	local operation = { status = "pending" }
	local child
	local function finish(result)
		if operation.status ~= "pending" then return end
		operation.status = result.status
		operation.result = result
		if callback then vim.schedule(function() callback(result) end) end
	end
	function operation.cancel()
		if operation.status ~= "pending" or operation.cancel_requested then return end
		operation.cancel_requested = true
		if child and child.on_complete then child.on_complete(function() finish({ status = "cancelled" }) end) end
		if child and child.cancel then child.cancel() else finish({ status = "cancelled" }) end
	end
	local list_error
	local previous_child = child
	local list_child
	list_child, list_error = require("minecraft-dev").list_templates({
		provider = "builtin",
		callback = function(templates, err)
			if operation.status ~= "pending" then return end
			if not templates then
				notify.notify(vim.log.levels.ERROR, { "custom", "list_failed" }, vim.inspect(err))
				finish({ status = "failed", error = err })
				return
			end
			vim.ui.select(templates, { prompt = prompt("select_template"), format_item = function(item) return string.format("[%s] %s", item.group, item.label) end }, function(template)
				if operation.status ~= "pending" then return end
				if not template then finish({ status = "cancelled" }); return end
				ask_input(prompt("directory"), vim.fn.getcwd(), function(directory, directory_cancelled)
					if operation.status ~= "pending" then return end
					if directory_cancelled then finish({ status = "cancelled" }); return end
					ask_input(prompt("project_name"), vim.fs.basename(directory), function(project_name, name_cancelled)
						if operation.status ~= "pending" then return end
						if name_cancelled then finish({ status = "cancelled" }); return end
						local properties = { PROJECT_NAME = project_name, USE_GIT = false }
						local previous_child = child
						local collection = collect(template.definition, properties, function(values, cancelled, collect_error, warnings)
							if operation.status ~= "pending" then return end
							if cancelled then finish({ status = "cancelled" }); return end
							if collect_error then
								notify.notify(vim.log.levels.ERROR, { "custom", "property_failed" }, vim.inspect(collect_error))
								finish({ status = "failed", error = collect_error })
								return
							end
							child = generate(template, directory, values, warnings, finish)
						end)
						if child == previous_child then child = collection end
					end)
				end)
			end)
		end,
	})
	if child == previous_child then child = list_child end
	if list_error then finish({ status = "failed", error = list_error }) end
	return operation
end

return M
