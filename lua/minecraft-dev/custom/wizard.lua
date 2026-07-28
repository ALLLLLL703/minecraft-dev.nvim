local M = {}
local evaluator = require("minecraft-dev.custom.evaluator")
local notify = require("minecraft-dev.util.notify")

local function flatten(descriptors, output)
	for _, descriptor in ipairs(descriptors or {}) do
		if descriptor.groupProperties then flatten(descriptor.groupProperties, output)
		elseif descriptor.name then table.insert(output, descriptor) end
	end
end

local function visible(descriptor, properties)
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

local function ask_property(descriptor, properties, callback)
	if not visible(descriptor, properties) or descriptor.derives or descriptor.inheritFrom or descriptor.type == "jdk" then callback(false) return end
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
	if descriptor.type == "gradle_plugin" then
		vim.ui.select({ true, false }, { prompt = prompt("property", descriptor.label or descriptor.name), format_item = tostring }, function(enabled)
			if enabled == nil then callback(true) return end
			if not enabled then properties[descriptor.name] = { enabled = false } callback(false) return end
			ask_input(prompt("property", descriptor.name .. " version"), nil, function(version, cancelled)
				if cancelled then callback(true) else properties[descriptor.name] = { enabled = true, version = version } callback(false) end
			end)
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
	local function next_property(index)
		if index > #descriptors then callback(properties, false) return end
		ask_property(descriptors[index], properties, function(cancelled)
			if cancelled then callback(nil, true) else next_property(index + 1) end
		end)
	end
	next_property(1)
end

local function generate(template, directory, properties)
	require("minecraft-dev").generate_template({
		provider = "builtin",
		descriptor = template.descriptor,
		directory = directory,
		properties = properties,
		use_git = properties.USE_GIT,
		callback = function(result)
			if result.status ~= "generated" then notify.notify(vim.log.levels.ERROR, { "custom", "generation_failed" }, vim.inspect(result.error)) return end
			notify.notify(vim.log.levels.INFO, { "custom", "generated" }, directory)
		end,
	})
end

function M.run()
	require("minecraft-dev").list_templates({
		provider = "builtin",
		callback = function(templates, err)
			if not templates then notify.notify(vim.log.levels.ERROR, { "custom", "list_failed" }, vim.inspect(err)) return end
			vim.ui.select(templates, { prompt = prompt("select_template"), format_item = function(item) return string.format("[%s] %s", item.group, item.label) end }, function(template)
				if not template then return end
				ask_input(prompt("directory"), vim.fn.getcwd(), function(directory, directory_cancelled)
					if directory_cancelled then return end
					ask_input(prompt("project_name"), vim.fs.basename(directory), function(project_name, name_cancelled)
						if name_cancelled then return end
						local properties = { PROJECT_NAME = project_name, USE_GIT = false }
						collect(template.definition, properties, function(values, cancelled)
							if not cancelled then generate(template, directory, values) end
						end)
					end)
				end)
			end)
		end,
	})
end

return M
