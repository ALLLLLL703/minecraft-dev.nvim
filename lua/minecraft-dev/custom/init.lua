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
		if type(version) ~= "string" or not version:match("^%d+%.%d+") then return derivation.default end
		if evaluator.expression({ VERSION = version }, "$VERSION.compareTo($mcver.MC1_21_11) > 0") then return 25 end
		if evaluator.expression({ VERSION = version }, "$VERSION.compareTo($mcver.MC1_20_4) > 0") then return 21 end
		if evaluator.expression({ VERSION = version }, "$VERSION.compareTo($mcver.MC1_17_1) > 0") then return 17 end
		if evaluator.expression({ VERSION = version }, "$VERSION.compareTo($mcver.MC1_16_5) > 0") then return 16 end
		return 8
	end
	if derivation.method == "extractVersionMajorMinor" or derivation.method == "extractPaperApiVersion" then
		local version = properties[(derivation.parents or {})[1]]
		if type(version) == "table" then version = version.minecraftVersion or version.minecraft or version.version end
		if derivation.method == "extractPaperApiVersion"
			and evaluator.expression({ VERSION = version }, "$VERSION.compareTo($mcver.MC1_20_5) >= 0")
		then
			return tostring(version or "")
		end
		return tostring(version or ""):match("^(%d+%.%d+)")
	end
	if derivation.method == "fetchPaperDependencyVersionForMcVersion" then
		local version = properties[(derivation.parents or {})[1]]
		if type(version) == "table" then version = version.minecraftVersion or version.minecraft or version.version end
		if evaluator.expression({ VERSION = version }, "$VERSION.compareTo($mcver.MC26_1) >= 0") then
			local build_system = properties[(derivation.parents or {})[2]]
			return build_system == "Maven" and "[" .. tostring(version) .. ".build,)" or tostring(version) .. ".build.+"
		end
		return tostring(version or "") .. "-R0.1-SNAPSHOT"
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
		if properties[property.name] == nil and property.default ~= nil then
			if property.options and type(property.default) == "number" then
				properties[property.name] = property.options[property.default + 1]
			elseif property.type ~= "jdk" and (type(property.default) ~= "string" or property.default:sub(1, 1) ~= "$") then
				properties[property.name] = property.default
			end
		end
	end
	for _ = 1, #flattened do
		local changed = false
		for _, property in ipairs(flattened) do
			if properties[property.name] == nil then
				local value
				if property.inheritFrom and properties[property.inheritFrom] ~= nil then value = properties[property.inheritFrom]
				elseif property.derives then value = derive_value(property, properties) end
				if value ~= nil then properties[property.name], changed = value, true end
			end
		end
		if not changed then break end
	end
	for _, property in ipairs(flattened) do
		if properties[property.name] == nil then
			if type(property.default) == "string" and property.default:sub(1, 1) == "$" then
				properties[property.name] = evaluator.expression(properties, property.default)
			elseif property.type == "jdk" and type(property.default) == "string" then
				properties[property.name] = properties[property.default]
			end
		end
		if type(property.forceValue) == "table"
			and evaluator.expression(properties, property.forceValue.condition or "false")
		then
			local forced = evaluator.expression(properties, tostring(property.forceValue.value))
			if property.type == "gradle_plugin" and type(properties[property.name]) == "table" then
				properties[property.name].enabled = not not forced
			else
				properties[property.name] = forced
			end
		end
		if property.type == "class_fqn" and properties[property.name] ~= nil then
			properties[property.name] = class_fqn(properties[property.name])
		elseif property.type == "inline_string_list" and type(properties[property.name]) == "string" then
			properties[property.name] = vim.split(properties[property.name], "%s*,%s*", { trimempty = true })
		elseif property.type == "license" and type(properties[property.name]) == "string" then
			properties[property.name] = { id = properties[property.name], name = properties[property.name], year = tonumber(os.date("%Y")) }
		elseif property.type == "gradle_plugin" and type(properties[property.name]) ~= "table" then
			properties[property.name] = { enabled = not not properties[property.name], version = property.parameters and property.parameters.version }
		end
		local empty_inline_list = property.type == "inline_string_list"
			and property.default == ""
			and type(properties[property.name]) == "table"
			and #properties[property.name] == 0
		if property.nullIfDefault and (empty_inline_list or vim.deep_equal(properties[property.name], property.default)) then
			properties[property.name] = nil
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
	local finalizers = vim.deepcopy(options.skip_finalizers and {} or descriptor.finalizers or {})
	if options.use_git then table.insert(finalizers, 1, { type = "git_init" }) end
	local finalizer_handle, finalizer_error = require("minecraft-dev.custom.finalizers").execute(
		destination_root,
		finalizers,
		properties,
		function(err)
			if options.finalizer_callback then pcall(options.finalizer_callback, err) end
		end
	)
	if finalizer_error then return nil, finalizer_error end
	result.finalizer_handle = finalizer_handle
	return result, nil
end

local function discover(root)
	root = vim.fs.normalize(root)
	local templates = {}
	local function walk(directory, relative_directory)
		for name, entry_type in vim.fs.dir(directory) do
			local relative = relative_directory == "" and name or relative_directory .. "/" .. name
			if entry_type == "directory" and name ~= ".git" then
				walk(vim.fs.joinpath(directory, name), relative)
			elseif entry_type == "file" and name:match("%.mcdev%.template%.json$") then
				local content = read_file(vim.fs.joinpath(directory, name))
				local ok, descriptor = pcall(vim.json.decode, content or "")
				if ok and (descriptor.version == 1 or descriptor.version == 2 or descriptor.version == 3) and descriptor.hidden ~= true then
					table.insert(templates, {
						descriptor = relative,
						label = descriptor.label or (name == ".mcdev.template.json" and vim.fs.basename(directory) or name:gsub("%.mcdev%.template%.json$", "")),
						group = descriptor.group or "default",
						version = descriptor.version,
						definition = descriptor,
					})
				end
			end
		end
	end
	walk(root, "")
	table.sort(templates, function(left, right) return left.descriptor < right.descriptor end)
	return templates
end

---@param options table
---@return table?, table?
function M.list(options)
	if type(options) ~= "table" then return nil, { code = "invalid_options" } end
	if options.provider == "local" then return discover(options.source), nil end
	if type(options.callback) ~= "function" then return nil, { code = "callback_required" } end
	return require("minecraft-dev.custom.providers").prepare(options, function(root, provider_error, cleanup)
		if provider_error then options.callback(nil, provider_error) return end
		local templates = discover(root)
		if cleanup then cleanup() end
		options.callback(templates, nil)
	end)
end

---@param options table
---@return table
function M.generate(options)
	local operation = { status = "pending" }
	local staging_path
	local lock_path
	local generation_lock
	local child
	local callback = type(options) == "table" and options.callback or nil
	local function finish(result)
		if operation.status ~= "pending" then return end
		operation.status = result.status
		operation.result = result
		if staging_path and result.status ~= "generated" then vim.fn.delete(staging_path, "rf") end
		if generation_lock then
			local released, release_err = generation_lock.release()
			generation_lock = nil
			if not released then result.cleanup_error = { code = "lock_cleanup_failed", detail = release_err } end
		end
		if callback then vim.schedule(function() callback(result) end) end
	end
	function operation.cancel()
		if operation.status ~= "pending" or operation.cancel_requested then return end
		operation.cancel_requested = true
		if child and child.on_complete then child.on_complete(function() finish({ status = "cancelled" }) end) end
		if child and child.cancel then child.cancel() else finish({ status = "cancelled" }) end
	end
	if type(options) ~= "table" then finish({ status = "failed", error = { code = "invalid_options" } }); return operation end
	if type(options.directory) ~= "string" or options.directory == "" then
		finish({ status = "failed", error = { code = "directory_required" } })
		return operation
	end
	if options.provider == "local" and (type(options.source) ~= "string" or options.source == "") then
		finish({ status = "failed", error = { code = "source_missing" } })
		return operation
	end

	local target = vim.fs.normalize(options.directory)
	local target_lstat = vim.uv.fs_lstat(target)
	if target_lstat and target_lstat.type == "link" then
		finish({ status = "failed", error = { code = "destination_symlink" } })
		return operation
	end
	if target_lstat and target_lstat.type ~= "directory" then
		finish({ status = "failed", error = { code = "destination_not_directory" } })
		return operation
	end
	local prepared, prepare_err = pcall(vim.fn.mkdir, vim.fs.dirname(target), "p")
	if not prepared then
		finish({ status = "failed", error = { code = "destination_prepare_failed", detail = prepare_err } })
		return operation
	end
	local real_parent = vim.uv.fs_realpath(vim.fs.dirname(target))
	if not real_parent then
		finish({ status = "failed", error = { code = "destination_prepare_failed" } })
		return operation
	end
	target = vim.fs.joinpath(real_parent, vim.fs.basename(target))
	local target_stat = vim.uv.fs_stat(target)
	local target_existed = target_stat ~= nil
	if target_stat and target_stat.type ~= "directory" then
		finish({ status = "failed", error = { code = "destination_not_directory" } })
		return operation
	end
	local scan = target_existed and vim.uv.fs_scandir(target) or nil
	if scan and vim.uv.fs_scandir_next(scan) ~= nil then
		finish({ status = "failed", error = { code = "destination_not_empty" } })
		return operation
	end
	lock_path = target .. ".minecraft-dev.lock"
	local lock_error
	generation_lock, lock_error = require("minecraft-dev.util.lock").acquire(lock_path)
	if not generation_lock then
		finish({ status = "failed", error = lock_error })
		return operation
	end
	staging_path = target .. ".minecraft-dev-" .. tostring(vim.uv.hrtime())
	prepared, prepare_err = pcall(vim.fn.mkdir, staging_path, "p")
	if not prepared then
		finish({ status = "failed", error = { code = "destination_prepare_failed", detail = prepare_err } })
		return operation
	end

	local function commit(generated)
		if operation.status ~= "pending" or operation.cancel_requested then return end
		local target_lstat_now = vim.uv.fs_lstat(target)
		local target_stat_now = vim.uv.fs_stat(target)
		local target_exists_now = target_stat_now ~= nil
		local identity_changed = target_existed and target_stat_now and target_stat
			and ((target_stat.dev and target_stat_now.dev and target_stat.dev ~= target_stat_now.dev)
				or (target_stat.ino and target_stat_now.ino and target_stat.ino ~= target_stat_now.ino))
		if (target_lstat_now and target_lstat_now.type == "link")
			or (target_stat_now and target_stat_now.type ~= "directory")
			or identity_changed
		then
			finish({ status = "failed", error = { code = "destination_changed" } })
			return
		end
		local target_scan = target_exists_now and vim.uv.fs_scandir(target) or nil
		if target_exists_now ~= target_existed or (target_scan and vim.uv.fs_scandir_next(target_scan) ~= nil) then
			finish({ status = "failed", error = { code = "destination_changed" } })
			return
		end
		local backup_path
		if target_exists_now then
			backup_path = staging_path .. ".previous"
			local moved, backup_err = vim.uv.fs_rename(target, backup_path)
			if not moved then finish({ status = "failed", error = { code = "destination_commit_failed", detail = backup_err } }); return end
			local backup_scan = vim.uv.fs_scandir(backup_path)
			if backup_scan and vim.uv.fs_scandir_next(backup_scan) ~= nil then
				local restored, restore_err = vim.uv.fs_rename(backup_path, target)
				if not restored then finish({ status = "failed", error = { code = "destination_rollback_failed", detail = restore_err } }); return end
				finish({ status = "failed", error = { code = "destination_changed" } })
				return
			end
		end
		local committed, commit_err = vim.uv.fs_rename(staging_path, target)
		if not committed then
			if backup_path then
				local restored, restore_err = vim.uv.fs_rename(backup_path, target)
				if not restored then finish({ status = "failed", error = { code = "destination_rollback_failed", detail = { commit = commit_err, rollback = restore_err } } }); return end
			end
			finish({ status = "failed", error = { code = "destination_commit_failed", detail = commit_err } })
			return
		end
		local imported, import_err = pcall(
			require("minecraft-dev.custom.finalizers").emit_imports,
			target,
			generated.descriptor.finalizers,
			generated.properties
		)
		if not imported then
			local displaced = vim.uv.fs_rename(target, staging_path)
			local restored = not backup_path or vim.uv.fs_rename(backup_path, target)
			if not displaced or not restored then
				finish({ status = "failed", error = { code = "destination_rollback_failed", detail = import_err } })
				return
			end
			finish({ status = "failed", error = { code = "finalizer_failed", type = "import_project", detail = import_err } })
			return
		end
		if backup_path and vim.fn.delete(backup_path, "rf") ~= 0 then
			local displaced = vim.uv.fs_rename(target, staging_path)
			local restored, restore_err = vim.uv.fs_rename(backup_path, target)
			if not displaced or not restored then finish({ status = "failed", error = { code = "destination_rollback_failed", detail = restore_err } }); return end
			finish({ status = "failed", error = { code = "destination_backup_cleanup_failed" } })
			return
		end
		staging_path = nil
		local files = vim.tbl_map(function(file) return target .. file:sub(#generated.staging_root + 1) end, generated.files)
		finish({ status = "generated", path = target, files = files, descriptor = generated.descriptor, properties = generated.properties })
	end

	local function render(root, cleanup)
		local generation_options = vim.tbl_extend("force", {}, options, { directory = staging_path })
		local ok, generated, generation_error = pcall(generate_from_root, generation_options, root)
		if cleanup then
			local cleaned, cleanup_err = pcall(cleanup)
			if not cleaned then finish({ status = "failed", error = { code = "provider_cleanup_failed", detail = cleanup_err } }); return end
		end
		if not ok then finish({ status = "failed", error = { code = "generation_failed", detail = generated } }); return end
		if not generated then finish({ status = "failed", error = generation_error }); return end
		generated.staging_root = staging_path
		child = generated.finalizer_handle
		if type(child) == "table" and child.on_complete then
			child.on_complete(function(result)
				if result.status == "generated" then commit(generated) else finish(result) end
			end)
		else
			commit(generated)
		end
	end

	if options.provider == "local" then
		render(options.source)
		return operation
	end
	local provider_started, provider_operation, provider_error = pcall(require("minecraft-dev.custom.providers").prepare, options, function(root, err, cleanup)
		if err then finish({ status = "failed", error = err }); return end
		render(root, cleanup)
	end)
	if not provider_started then
		finish({ status = "failed", error = { code = "provider_start_failed", detail = provider_operation } })
		return operation
	end
	if provider_error then finish({ status = "failed", error = provider_error }); return operation end
	if not child then child = provider_operation end
	return operation
end

return M
