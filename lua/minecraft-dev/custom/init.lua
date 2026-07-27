local M = {}
local evaluator = require("minecraft-dev.custom.evaluator")
local fs = require("minecraft-dev.util.fs")
local path = require("minecraft-dev.util.path")

local function read_file(file_path)
	local handle = io.open(file_path, "r")
	if not handle then return nil end
	local content = handle:read("*a")
	handle:close()
	return content
end

local function inside(root, candidate)
	root = vim.fs.normalize(root)
	candidate = vim.fs.normalize(candidate)
	return candidate == root or candidate:sub(1, #root + 1) == root .. "/"
end

local function flatten_properties(descriptors, output)
	for _, descriptor in ipairs(descriptors or {}) do
		if descriptor.groupProperties then
			flatten_properties(descriptor.groupProperties, output)
		elseif descriptor.name then
			table.insert(output, descriptor)
		end
	end
end

local function class_fqn(value)
	if type(value) == "table" then return value end
	local package_name, class_name = tostring(value):match("^(.*)%.([^.]*)$")
	if not package_name then package_name, class_name = "", tostring(value) end
	return {
		packageName = package_name,
		packagePath = package_name:gsub("%.", "/"),
		className = class_name,
		path = (package_name == "" and class_name or package_name:gsub("%.", "/") .. "/" .. class_name),
		value = tostring(value),
	}
end

local function derive_replace(derivation, properties)
	local value = tostring(properties[(derivation.parents or {})[1]] or "")
	local parameters = derivation.parameters or {}
	if parameters.lowercase then value = value:lower() end
	if parameters.regex then value = value:gsub(parameters.regex, parameters.replacement or "") end
	if parameters.maxLength then value = value:sub(1, parameters.maxLength) end
	return value
end

local function derive_class_name(derivation, properties)
	local coordinates = properties[(derivation.parents or {})[1]] or {}
	local project_name = properties.PROJECT_NAME or properties[(derivation.parents or {})[2]] or coordinates.artifactId or "Main"
	local class_name = tostring(project_name):gsub("[^%w]+", " "):gsub("(%w)([%w]*)", function(first, rest)
		return first:upper() .. rest
	end):gsub("%s+", "")
	local package_name = coordinates.groupId or ""
	if coordinates.artifactId and coordinates.artifactId ~= "" then package_name = package_name .. "." .. coordinates.artifactId:gsub("[^%w_]", "") end
	return class_fqn(package_name .. "." .. class_name)
end

local function derive_value(property, properties)
	local derivation = property.derives
	if not derivation then return nil end
	for _, selection in ipairs(derivation.select or {}) do
		if evaluator.expression(properties, selection.condition) then return selection.value end
	end
	if derivation.method == "replace" then return derive_replace(derivation, properties) end
	if derivation.method == "suggestClassName" then return derive_class_name(derivation, properties) end
	if derivation.method == "recommendJavaVersionForMcVersion" then
		local version = properties[(derivation.parents or {})[1]]
		if type(version) == "table" then version = version.minecraftVersion or version.minecraft end
		if evaluator.expression({ VERSION = version }, "$VERSION.compareTo($mcver.MC1_20_5) >= 0") then return 21 end
		if evaluator.expression({ VERSION = version }, "$VERSION.compareTo($mcver.MC1_18) >= 0") then return 17 end
		return 8
	end
	return derivation.default
end

local function matches_validator(value, validator)
	local ok, matched = pcall(vim.fn.match, tostring(value), "\\v^(" .. validator .. ")$")
	return ok and matched == 0
end

local function collect_properties(descriptor, provided)
	local properties = vim.deepcopy(provided or {})
	local flattened = {}
	flatten_properties(descriptor.properties, flattened)
	for _, property in ipairs(flattened) do
		if properties[property.name] == nil then
			if property.inheritFrom then properties[property.name] = properties[property.inheritFrom]
			elseif property.derives then properties[property.name] = derive_value(property, properties)
			elseif property.default ~= nil then
				if property.options and type(property.default) == "number" then
					properties[property.name] = property.options[property.default + 1]
				else properties[property.name] = property.default end
			end
		end
		if property.type == "class_fqn" and properties[property.name] ~= nil then
			properties[property.name] = class_fqn(properties[property.name])
		elseif property.type == "inline_string_list" and type(properties[property.name]) == "string" then
			properties[property.name] = vim.split(properties[property.name], "%s*,%s*", { trimempty = true })
		elseif property.type == "license" and type(properties[property.name]) == "string" then
			properties[property.name] = { id = properties[property.name], name = properties[property.name], year = tonumber(os.date("%Y")) }
		end
		if property.validator and properties[property.name] ~= nil then
			local value = tostring(properties[property.name])
			if not matches_validator(value, property.validator) then
				return nil, { code = "validation_failed", property = property.name }
			end
		end
	end
	return properties
end

local function generate_from_root(options, root)
	root = vim.fs.normalize(root)
	local descriptor_path = options.descriptor and path.join(root, options.descriptor) or path.join(root, ".mcdev.template.json")
	if not inside(root, descriptor_path) then return nil, { code = "unsafe_descriptor_path" } end
	local descriptor_content = read_file(descriptor_path)
	if not descriptor_content then return nil, { code = "descriptor_missing" } end
	local ok, descriptor = pcall(vim.json.decode, descriptor_content)
	if not ok then return nil, { code = "descriptor_invalid" } end
	if descriptor.version ~= 1 and descriptor.version ~= 2 and descriptor.version ~= 3 then
		return nil, { code = "unsupported_descriptor_version" }
	end
	local properties, property_error = collect_properties(descriptor, options.properties)
	if not properties then return nil, property_error end
	properties.USE_GIT = options.use_git == true
	local destination_root = vim.fs.normalize(options.directory)
	local generated = {}
	for _, file in ipairs(descriptor.files or {}) do
		if not file.condition or evaluator.expression(properties, file.condition) then
			local template_relative = evaluator.interpolate(properties, file.template)
			local destination_relative = evaluator.interpolate(properties, file.destination)
			local template_path = vim.fs.normalize(path.join(vim.fs.dirname(descriptor_path), template_relative))
			local destination_path = vim.fs.normalize(path.join(destination_root, destination_relative))
			if not inside(root, template_path) then return nil, { code = "unsafe_template_path", path = template_relative } end
			if not inside(destination_root, destination_path) then return nil, { code = "unsafe_destination_path", path = destination_relative } end
			local template_content = read_file(template_path)
			if not template_content then return nil, { code = "template_missing", path = template_relative } end
			local file_properties = vim.tbl_extend("force", vim.deepcopy(properties), file.properties or {})
			fs.mkdir(vim.fs.dirname(destination_path))
			fs.write_file(destination_path, evaluator.render(file_properties, template_content))
			table.insert(generated, destination_path)
		end
	end
	local result = { files = generated, descriptor = descriptor, properties = properties }
	local finalizer_handle, finalizer_error = require("minecraft-dev.custom.finalizers").execute(
		destination_root,
		descriptor.finalizers or {},
		properties,
		function(err)
			if options.finalizer_callback then options.finalizer_callback(err) end
		end
	)
	if finalizer_error then return nil, finalizer_error end
	result.finalizer_handle = finalizer_handle
	return result, nil
end

---@param options table
---@return table?, table?
function M.generate(options)
	if type(options) ~= "table" then return nil, { code = "invalid_options" } end
	if options.provider == "local" then
		return generate_from_root(options, options.source)
	end
	if type(options.callback) ~= "function" then return nil, { code = "callback_required" } end
	return require("minecraft-dev.custom.providers").prepare(options, function(root, provider_error, cleanup)
		if provider_error then
			options.callback(nil, provider_error)
			return
		end
		local result, generation_error = generate_from_root(options, root)
		if cleanup then cleanup() end
		options.callback(result, generation_error)
	end)
end

return M
