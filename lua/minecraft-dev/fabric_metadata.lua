local jvm_index = require("minecraft-dev.jvm_index")

local M = {}
local namespace = vim.api.nvim_create_namespace("minecraft-dev.metadata.fabric")
local COMPLETEFUNC = "v:lua.MinecraftDevFabricManifestComplete"
local ENTRYPOINT_TYPES = {
	main = "net.fabricmc.api.ModInitializer",
	client = "net.fabricmc.api.ClientModInitializer",
	server = "net.fabricmc.api.DedicatedServerModInitializer",
	preLaunch = "net.fabricmc.loader.api.entrypoint.PreLaunchEntrypoint",
}
local ENVIRONMENTS = { ["*"] = true, client = true, server = true }

local function message(code, detail)
	return require("minecraft-dev.util.notify").message({ "metadata", code }, tostring(detail or ""))
end

local function diagnostic(code, node, detail, severity)
	node = node or { lnum = 0, col = 0, end_lnum = 0, end_col = 1 }
	return {
		lnum = node.lnum,
		col = node.col,
		end_lnum = node.end_lnum,
		end_col = math.max(node.end_col, node.col + 1),
		severity = severity or vim.diagnostic.severity.ERROR,
		message = message(code, detail),
		source = "minecraft-dev.nvim",
		code = code,
	}
end

local function first(object, key)
	return object and object.by_key and object.by_key[key] and object.by_key[key][1] or nil
end

local function scalar(entry, kind)
	if entry and entry.value and entry.value.kind == kind then
		return entry.value.value
	end
	return nil
end

local function add_duplicates(object, diagnostics)
	for key, entries in pairs(object.by_key) do
		for index = 2, #entries do
			table.insert(diagnostics, diagnostic("fabric_field_duplicate", entries[index].key_node, key))
		end
	end
end

local function require_field(object, key, kind, diagnostics)
	local entry = first(object, key)
	if entry == nil then
		table.insert(diagnostics, diagnostic("fabric_field_required", nil, key))
	elseif entry.value == nil or entry.value.kind ~= kind then
		table.insert(diagnostics, diagnostic("fabric_field_type_invalid", entry.value or entry, key .. ": " .. kind))
	elseif kind == "string" and vim.trim(entry.value.value) == "" then
		table.insert(diagnostics, diagnostic("fabric_field_empty", entry.value, key))
	end
	return entry
end

local function valid_mod_id(value)
	return value:match("^[a-z][a-z0-9_-]+$") ~= nil and #value <= 64
end

local function resource_root(buffer)
	return vim.fs.dirname(vim.api.nvim_buf_get_name(buffer))
end

local function resource_path(buffer, value)
	return vim.fs.normalize(resource_root(buffer) .. "/" .. value)
end

local function project_root(buffer)
	local path = vim.api.nvim_buf_get_name(buffer)
	return vim.fs.root(path, { ".git", "settings.gradle", "settings.gradle.kts", "build.gradle", "build.gradle.kts" })
		or resource_root(buffer)
end

local function resource_reference(buffer, value_node, kind, pattern, diagnostics, references)
	if value_node == nil or value_node.kind ~= "string" then
		table.insert(diagnostics, diagnostic("fabric_resource_type_invalid", value_node, kind))
		return
	end
	local value = value_node.value
	local matches_pattern = true
	if type(pattern) == "function" then
		matches_pattern = not not pattern(value)
	elseif type(pattern) == "string" then
		matches_pattern = value:match(pattern) ~= nil
	end
	if not matches_pattern then
		table.insert(diagnostics, diagnostic("fabric_resource_name_invalid", value_node, kind .. ": " .. value))
	end
	local path = resource_path(buffer, value)
	local reference = vim.tbl_extend("force", vim.deepcopy(value_node), { kind = kind, value = value, path = path })
	table.insert(references, reference)
	if vim.uv.fs_stat(path) == nil then
		table.insert(diagnostics, diagnostic("fabric_resource_unresolved", value_node, kind .. ": " .. value))
	end
end

local function collect_resources(document, buffer, diagnostics)
	local references = {}
	local mixins = first(document, "mixins")
	if mixins then
		if mixins.value == nil or mixins.value.kind ~= "array" then
			table.insert(diagnostics, diagnostic("fabric_field_type_invalid", mixins.value or mixins, "mixins: array"))
		else
			for _, item in ipairs(mixins.value.items) do
				local value_node = item
				if item.kind == "object" then
					local config = first(item, "config")
					value_node = config and config.value or nil
					local environment = scalar(first(item, "environment"), "string")
					if environment and not ENVIRONMENTS[environment] then
						table.insert(
							diagnostics,
							diagnostic("fabric_environment_invalid", first(item, "environment").value, environment)
						)
					end
				end
				resource_reference(buffer, value_node, "mixin", "%.mixins%.json$", diagnostics, references)
			end
		end
	end
	local access_widener = first(document, "accessWidener")
	if access_widener then
		resource_reference(buffer, access_widener.value, "accessWidener", function(value)
			return value:match("%.accesswidener$")
				or value:match("%.aw$")
				or value:match("%.classtweaker$")
				or value:match("%.ct$")
		end, diagnostics, references)
	end
	local icon = first(document, "icon")
	if icon then
		if icon.value and icon.value.kind == "string" then
			resource_reference(buffer, icon.value, "icon", nil, diagnostics, references)
		elseif icon.value and icon.value.kind == "object" then
			for _, entry in ipairs(icon.value.entries) do
				resource_reference(buffer, entry.value, "icon", nil, diagnostics, references)
			end
		else
			table.insert(
				diagnostics,
				diagnostic("fabric_field_type_invalid", icon.value or icon, "icon: string|object")
			)
		end
	end
	local license = first(document, "license")
	if license then
		local nodes = license.value and license.value.kind == "array" and license.value.items or { license.value }
		local root = project_root(buffer)
		local path = vim.uv.fs_stat(root .. "/LICENSE") and (root .. "/LICENSE")
			or vim.uv.fs_stat(root .. "/LICENSE.txt") and (root .. "/LICENSE.txt")
			or nil
		for _, node in ipairs(nodes) do
			if node and node.kind == "string" then
				table.insert(
					references,
					vim.tbl_extend("force", vim.deepcopy(node), { kind = "license", value = node.value, path = path })
				)
			end
		end
	end
	return references
end

local function entrypoint_value(item)
	if item.kind == "string" then
		return item.value, item
	end
	if item.kind == "object" then
		local entry = first(item, "value")
		return scalar(entry, "string"), entry and entry.value or item
	end
	return nil, item
end

local function collect_entrypoints(document, diagnostics)
	local result = {}
	local entrypoints = first(document, "entrypoints")
	if entrypoints == nil then
		return result
	end
	if entrypoints.value == nil or entrypoints.value.kind ~= "object" then
		table.insert(
			diagnostics,
			diagnostic("fabric_field_type_invalid", entrypoints.value or entrypoints, "entrypoints: object")
		)
		return result
	end
	add_duplicates(entrypoints.value, diagnostics)
	for _, group in ipairs(entrypoints.value.entries) do
		if group.value == nil or group.value.kind ~= "array" then
			table.insert(
				diagnostics,
				diagnostic("fabric_field_type_invalid", group.value or group, "entrypoints." .. group.key .. ": array")
			)
		else
			for _, item in ipairs(group.value.items) do
				local value, node = entrypoint_value(item)
				if type(value) ~= "string" or value == "" then
					table.insert(diagnostics, diagnostic("fabric_entrypoint_invalid", node, group.key))
				else
					table.insert(result, { type = group.key, value = value, node = node })
				end
			end
		end
	end
	return result
end

local function incomplete_index(warnings)
	for _, warning in ipairs(warnings) do
		if
			warning.code == "source_scan_limit"
			or warning.code == "parser_unavailable"
			or warning.code == "source_open_failed"
		then
			return true
		end
	end
	return false
end

local function class_for_entrypoint(indexed, value)
	local class_name = value:match("^(.-)::") or value
	local matches = {}
	for _, class in ipairs(indexed.entries) do
		if class.fqn == class_name then
			table.insert(matches, class)
		end
	end
	return matches
end

local function source_lines(class)
	local buffer = vim.fn.bufnr(class.path)
	local lines
	if buffer ~= -1 and vim.api.nvim_buf_is_loaded(buffer) then
		lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
	else
		lines = vim.fn.readfile(class.path)
	end
	local first_line = (class.declaration_lnum or 0) + 1
	local last_line = math.min((class.declaration_end_lnum or (#lines - 1)) + 1, #lines)
	return vim.list_slice(lines, first_line, last_line), first_line - 1
end

local function has_empty_constructor(class)
	local lines = source_lines(class)
	local text = table.concat(lines, "\n")
	local name = vim.pesc(class.name)
	local constructors = {}
	for parameters in text:gmatch(name .. "%s*%(([^)]*)%)%s*[{:]?") do
		table.insert(constructors, vim.trim(parameters))
	end
	if class.language == "kotlin" then
		for parameters in text:gmatch("constructor%s*%(([^)]*)%)") do
			table.insert(constructors, vim.trim(parameters))
		end
	end
	if #constructors == 0 then
		return true
	end
	for _, parameters in ipairs(constructors) do
		if parameters == "" then
			return true
		end
	end
	return false
end

local function member_public(language, line)
	if language ~= "kotlin" then
		return line:match("%f[%w]public%f[%W]") ~= nil
	end
	return line:match("%f[%w]private%f[%W]") == nil
		and line:match("%f[%w]protected%f[%W]") == nil
		and line:match("%f[%w]internal%f[%W]") == nil
end

local function member_candidates(class, member)
	local lines, offset = source_lines(class)
	local escaped = vim.pesc(member)
	local candidates = {}
	for index, line in ipairs(lines) do
		local parameters = line:match("%f[%w_]" .. escaped .. "%s*%(([^)]*)%)")
		if parameters ~= nil and member ~= class.name then
			table.insert(candidates, {
				kind = "method",
				parameters = vim.trim(parameters),
				public = member_public(class.language, line),
				static = line:match("%f[%w]static%f[%W]") ~= nil or line:match("@JvmStatic") ~= nil,
				lnum = offset + index - 1,
				col = math.max((line:find(member, 1, true) or 1) - 1, 0),
				end_lnum = offset + index - 1,
				end_col = math.max((line:find(member, 1, true) or 1) - 1, 0) + #member,
			})
		elseif line:match("%f[%w_]" .. escaped .. "%s*[=:;]") then
			local declared_type = line:match("([%w_.$]+)%s+" .. escaped .. "%s*[=:;]")
			table.insert(candidates, {
				kind = "field",
				declared_type = declared_type,
				public = member_public(class.language, line),
				static = line:match("%f[%w]static%f[%W]") ~= nil or line:match("@JvmField") ~= nil,
				lnum = offset + index - 1,
				col = math.max((line:find(member, 1, true) or 1) - 1, 0),
				end_lnum = offset + index - 1,
				end_col = math.max((line:find(member, 1, true) or 1) - 1, 0) + #member,
			})
		end
	end
	return candidates
end

local function field_type_matches(indexed, declared_type, expected)
	if declared_type == nil then
		return nil
	end
	if declared_type == expected or declared_type == expected:match("([%w_$]+)$") then
		return true
	end
	for _, class in ipairs(indexed.entries) do
		if class.fqn == declared_type or class.name == declared_type then
			return jvm_index.inherits(indexed, class, expected)
		end
	end
	return nil
end

local function validate_member(entrypoint, class, indexed, diagnostics)
	local member = entrypoint.value:match("::(.+)$")
	if member == nil then
		if not has_empty_constructor(class) then
			table.insert(
				diagnostics,
				diagnostic("fabric_entrypoint_constructor_invalid", entrypoint.node, entrypoint.value)
			)
		end
		return
	end
	local candidates = member_candidates(class, member)
	if #candidates == 0 then
		table.insert(diagnostics, diagnostic("fabric_entrypoint_member_unresolved", entrypoint.node, entrypoint.value))
		return
	end
	if #candidates > 1 then
		table.insert(diagnostics, diagnostic("fabric_entrypoint_ambiguous", entrypoint.node, entrypoint.value))
		return
	end
	local candidate = candidates[1]
	if not candidate.public then
		table.insert(diagnostics, diagnostic("fabric_entrypoint_member_private", entrypoint.node, entrypoint.value))
	end
	if candidate.kind == "method" then
		if candidate.parameters ~= "" then
			table.insert(
				diagnostics,
				diagnostic("fabric_entrypoint_method_parameters", entrypoint.node, entrypoint.value)
			)
		end
		if not candidate.static and not has_empty_constructor(class) then
			table.insert(
				diagnostics,
				diagnostic("fabric_entrypoint_constructor_invalid", entrypoint.node, entrypoint.value)
			)
		end
	else
		if not candidate.static then
			table.insert(diagnostics, diagnostic("fabric_entrypoint_field_static", entrypoint.node, entrypoint.value))
		end
		local expected = ENTRYPOINT_TYPES[entrypoint.type]
		local status = expected and field_type_matches(indexed, candidate.declared_type, expected) or true
		if status == false then
			table.insert(
				diagnostics,
				diagnostic("fabric_entrypoint_wrong_type", entrypoint.node, entrypoint.type .. ": " .. expected)
			)
		elseif status == nil then
			table.insert(
				diagnostics,
				diagnostic(
					"fabric_entrypoint_type_unverified",
					entrypoint.node,
					entrypoint.value,
					vim.diagnostic.severity.WARN
				)
			)
		end
	end
end

local function validate_entrypoints(entrypoints, indexed, diagnostics)
	for _, entrypoint in ipairs(entrypoints) do
		local matches = class_for_entrypoint(indexed, entrypoint.value)
		if #matches == 0 then
			local code = incomplete_index(indexed.warnings) and "fabric_entrypoint_unverified"
				or "fabric_entrypoint_unresolved"
			local severity = incomplete_index(indexed.warnings) and vim.diagnostic.severity.WARN or nil
			table.insert(diagnostics, diagnostic(code, entrypoint.node, entrypoint.value, severity))
		elseif #matches > 1 then
			table.insert(diagnostics, diagnostic("fabric_entrypoint_ambiguous", entrypoint.node, entrypoint.value))
		else
			local expected = ENTRYPOINT_TYPES[entrypoint.type]
			if expected and not entrypoint.value:find("::", 1, true) then
				local status = jvm_index.inherits(indexed, matches[1], expected)
				if status == false then
					table.insert(
						diagnostics,
						diagnostic("fabric_entrypoint_wrong_type", entrypoint.node, entrypoint.type .. ": " .. expected)
					)
				elseif status == nil then
					table.insert(
						diagnostics,
						diagnostic(
							"fabric_entrypoint_type_unverified",
							entrypoint.node,
							entrypoint.value,
							vim.diagnostic.severity.WARN
						)
					)
				end
			end
			validate_member(entrypoint, matches[1], indexed, diagnostics)
		end
	end
end

local function validate_dependencies(document, diagnostics)
	for _, key in ipairs({ "depends", "recommends", "suggests", "conflicts", "breaks" }) do
		local field = first(document, key)
		if field then
			if field.value == nil or field.value.kind ~= "object" then
				table.insert(
					diagnostics,
					diagnostic("fabric_field_type_invalid", field.value or field, key .. ": object")
				)
			else
				add_duplicates(field.value, diagnostics)
				for _, dependency in ipairs(field.value.entries) do
					local value = dependency.value
					if value == nil or value.kind ~= "string" and value.kind ~= "array" then
						table.insert(
							diagnostics,
							diagnostic("fabric_dependency_invalid", value or dependency, dependency.key)
						)
					elseif value.kind == "array" then
						for _, item in ipairs(value.items) do
							if item.kind ~= "string" or item.value == "" then
								table.insert(diagnostics, diagnostic("fabric_dependency_invalid", item, dependency.key))
							end
						end
					end
				end
			end
		end
	end
end

---@param options? { buffer?: integer, language?: string }
---@return table
function M.inspect(options)
	options = options or {}
	local buffer = options.buffer or 0
	if not vim.api.nvim_buf_is_loaded(buffer) then
		return { status = "failed", error = { code = "buffer_unloaded" } }
	end
	if vim.fs.basename(vim.api.nvim_buf_get_name(buffer)) ~= "fabric.mod.json" then
		return { status = "skipped", error = { code = "not_fabric_manifest" } }
	end
	local parsed = require("minecraft-dev.json_tree").parse_buffer({ buffer = buffer, language = options.language })
	if parsed.status == "parsed" and parsed.document.kind ~= "object" then
		return { status = "failed", error = { code = "fabric_root_invalid" } }
	end
	return parsed
end

---@param options? { buffer?: integer, root?: string, language?: string, max_files?: integer }
---@return table
function M.diagnose_buffer(options)
	options = options or {}
	local buffer = options.buffer or 0
	local inspected = M.inspect({ buffer = buffer, language = options.language })
	if inspected.status ~= "parsed" then
		vim.diagnostic.reset(namespace, buffer)
		local diagnostics = {}
		if inspected.status == "failed" then
			table.insert(diagnostics, diagnostic(inspected.error.code))
			vim.diagnostic.set(namespace, buffer, diagnostics)
		end
		return vim.tbl_extend("force", inspected, { buffer = buffer, diagnostics = diagnostics })
	end
	local document = inspected.document
	local diagnostics = {}
	add_duplicates(document, diagnostics)
	local schema = require_field(document, "schemaVersion", "number", diagnostics)
	local id = require_field(document, "id", "string", diagnostics)
	require_field(document, "version", "string", diagnostics)
	if document.entries[1] and document.entries[1].key ~= "schemaVersion" then
		table.insert(diagnostics, diagnostic("fabric_schema_first", schema and schema.key_node or nil))
	end
	if schema and schema.value and schema.value.kind == "number" and schema.value.value ~= 1 then
		table.insert(diagnostics, diagnostic("fabric_schema_invalid", schema.value, tostring(schema.value.value)))
	end
	local mod_id = scalar(id, "string")
	if mod_id and not valid_mod_id(mod_id) then
		table.insert(diagnostics, diagnostic("fabric_mod_id_invalid", id.value, mod_id))
	end
	local environment = first(document, "environment")
	local environment_value = scalar(environment, "string")
	if environment and (environment_value == nil or not ENVIRONMENTS[environment_value]) then
		table.insert(
			diagnostics,
			diagnostic(
				"fabric_environment_invalid",
				environment.value or environment,
				tostring(environment_value or "")
			)
		)
	end
	validate_dependencies(document, diagnostics)
	local resources = collect_resources(document, buffer, diagnostics)
	local entrypoints = collect_entrypoints(document, diagnostics)
	local indexed = jvm_index.list({ buffer = buffer, root = options.root, max_files = options.max_files })
	validate_entrypoints(entrypoints, indexed, diagnostics)
	vim.diagnostic.set(namespace, buffer, diagnostics)
	return {
		status = "diagnosed",
		buffer = buffer,
		diagnostics = diagnostics,
		document = document,
		entrypoints = entrypoints,
		resources = resources,
		classes = indexed.entries,
		warnings = indexed.warnings,
		root = indexed.root,
	}
end

local function cursor_contains(node, row, col)
	return row >= node.lnum
		and row <= node.end_lnum
		and (row > node.lnum or col >= node.col)
		and (row < node.end_lnum or col <= node.end_col)
end

---@param options? { buffer?: integer, root?: string, value?: string, open?: boolean, max_files?: integer }
---@return table
function M.goto_entrypoint(options)
	options = options or {}
	local diagnosed = M.diagnose_buffer(options)
	if diagnosed.status ~= "diagnosed" then
		return vim.tbl_extend("force", diagnosed, { locations = {} })
	end
	local cursor = vim.api.nvim_win_get_cursor(0)
	local value = options.value
	if value == nil then
		for _, entrypoint in ipairs(diagnosed.entrypoints) do
			if cursor_contains(entrypoint.node, cursor[1] - 1, cursor[2]) then
				value = entrypoint.value
				break
			end
		end
	end
	if type(value) ~= "string" or value == "" then
		return { status = "failed", error = { code = "fabric_entrypoint_required" }, locations = {} }
	end
	local locations = class_for_entrypoint({ entries = diagnosed.classes }, value)
	if #locations == 0 then
		return { status = "failed", error = { code = "fabric_entrypoint_unresolved", detail = value }, locations = {} }
	end
	if options.open ~= false then
		vim.cmd.edit(vim.fn.fnameescape(locations[1].path))
		vim.api.nvim_win_set_cursor(0, { locations[1].lnum + 1, locations[1].col })
	end
	return {
		status = "found",
		value = value,
		locations = locations,
		warnings = diagnosed.warnings,
		root = diagnosed.root,
	}
end

---@param options? { buffer?: integer, open?: boolean }
---@return table
function M.goto_resource(options)
	options = options or {}
	local buffer = options.buffer or 0
	local diagnosed = M.diagnose_buffer({ buffer = buffer })
	if diagnosed.status ~= "diagnosed" then
		return vim.tbl_extend("force", diagnosed, { locations = {} })
	end
	local cursor = vim.api.nvim_win_get_cursor(0)
	for _, resource in ipairs(diagnosed.resources) do
		if cursor_contains(resource, cursor[1] - 1, cursor[2]) then
			if resource.path == nil or vim.uv.fs_stat(resource.path) == nil then
				return {
					status = "failed",
					error = { code = "fabric_resource_unresolved", detail = resource.value },
					locations = {},
				}
			end
			local location = { path = resource.path, lnum = 0, col = 0, end_lnum = 0, end_col = 1 }
			if options.open ~= false then
				vim.cmd.edit(vim.fn.fnameescape(resource.path))
			end
			return { status = "found", resource = resource, locations = { location } }
		end
	end
	return { status = "failed", error = { code = "fabric_resource_required" }, locations = {} }
end

---@param options? { buffer?: integer, root?: string, prefix?: string, entrypoint_type?: string, max_files?: integer }
---@return table
function M.complete_entrypoints(options)
	options = options or {}
	local indexed = jvm_index.list(options)
	local expected = options.entrypoint_type and ENTRYPOINT_TYPES[options.entrypoint_type] or nil
	local items = {}
	for _, class in ipairs(indexed.entries) do
		if not class.abstract and (expected == nil or jvm_index.inherits(indexed, class, expected) == true) then
			if options.prefix == nil or vim.startswith(class.fqn, options.prefix) then
				table.insert(
					items,
					{ word = class.fqn, abbr = class.fqn, menu = "[" .. class.language .. "]", filename = class.path }
				)
			end
		end
	end
	return { status = "completed", items = items, warnings = indexed.warnings, root = indexed.root }
end

local function collect_resource_files(directory, relative, output)
	local ok, iterator = pcall(vim.fs.dir, directory)
	if not ok or iterator == nil then
		return
	end
	for name, kind in iterator do
		local child_relative = relative == "" and name or (relative .. "/" .. name)
		local child = vim.fs.normalize(directory .. "/" .. name)
		if kind == "directory" then
			collect_resource_files(child, child_relative, output)
		elseif kind == "file" and name ~= "fabric.mod.json" then
			table.insert(output, child_relative)
		end
	end
end

---@param options? { buffer?: integer, prefix?: string, kind?: "mixin"|"accessWidener"|"icon" }
---@return table
function M.complete_resources(options)
	options = options or {}
	local buffer = options.buffer or 0
	local files = {}
	collect_resource_files(resource_root(buffer), "", files)
	local items = {}
	for _, path in ipairs(files) do
		local matches = options.kind == nil
			or options.kind == "mixin" and path:match("%.mixins%.json$") ~= nil
			or options.kind == "accessWidener" and (path:match("%.accesswidener$") or path:match("%.aw$") or path:match(
				"%.classtweaker$"
			) or path:match("%.ct$"))
			or options.kind == "icon"
				and (path:match("%.png$") or path:match("%.jpg$") or path:match("%.jpeg$") or path:match("%.webp$"))
		if matches and (options.prefix == nil or vim.startswith(path, options.prefix)) then
			table.insert(items, { word = path, abbr = path, menu = "[Fabric resource]" })
		end
	end
	table.sort(items, function(left, right)
		return left.word < right.word
	end)
	return { status = "completed", items = items, root = resource_root(buffer) }
end

local function completefunc(findstart, base)
	if findstart == 1 then
		local line = vim.api.nvim_get_current_line()
		local start = vim.fn.col(".") - 1
		while start > 0 and line:sub(start, start):match("[%w_.$-]") do
			start = start - 1
		end
		return start
	end
	return M.complete_entrypoints({ buffer = 0, prefix = base }).items
end

function M.setup()
	_G.MinecraftDevFabricManifestComplete = completefunc
	local group = vim.api.nvim_create_augroup("MinecraftDevFabricMetadata", { clear = true })
	---@type MinecraftDevConfig
	local config = require("minecraft-dev").config
	if not config.defaults.metadata.diagnostics then
		vim.diagnostic.reset(namespace)
		return
	end
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "TextChanged", "TextChangedI" }, {
		group = group,
		pattern = "fabric.mod.json",
		callback = function(event)
			if vim.bo[event.buf].completefunc == "" then
				vim.bo[event.buf].completefunc = COMPLETEFUNC
			end
			require("minecraft-dev.fabric_metadata").diagnose_buffer({ buffer = event.buf })
		end,
	})
end

function M.namespace()
	return namespace
end

M.valid_mod_id = valid_mod_id

return M
