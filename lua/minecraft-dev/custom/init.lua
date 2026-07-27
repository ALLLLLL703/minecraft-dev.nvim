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

local function collect_properties(descriptor, provided)
	local properties = vim.deepcopy(provided or {})
	local flattened = {}
	flatten_properties(descriptor.properties, flattened)
	for _, property in ipairs(flattened) do
		if properties[property.name] == nil then
			if property.inheritFrom then properties[property.name] = properties[property.inheritFrom]
			elseif property.default ~= nil then
				if property.options and type(property.default) == "number" then
					properties[property.name] = property.options[property.default + 1]
				else properties[property.name] = property.default end
			end
		end
		if property.validator and properties[property.name] ~= nil then
			local value = tostring(properties[property.name])
			if not value:match("^" .. property.validator .. "$") then
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
	return { files = generated, descriptor = descriptor, properties = properties }, nil
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
