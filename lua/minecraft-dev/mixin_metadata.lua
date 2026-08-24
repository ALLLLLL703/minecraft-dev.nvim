local jvm_index = require("minecraft-dev.jvm_index")

local M = {}
local namespace = vim.api.nvim_create_namespace("minecraft-dev.metadata.mixin")
local COMPLETEFUNC = "v:lua.MinecraftDevMixinConfigComplete"
local MIXIN_PLUGIN = "org.spongepowered.asm.mixin.extensibility.IMixinConfigPlugin"
local LISTS = { "mixins", "client", "server" }
local SCHEMA = {
	required = "boolean",
	minVersion = "string",
	package = "string",
	plugin = "string",
	compatibilityLevel = "string",
	refmap = "string",
	mixins = "array",
	client = "array",
	server = "array",
	setSourceFile = "boolean",
	verbose = "boolean",
	injectors = "object",
	overwrite = "object",
}

local function config_file(buffer)
	local name = vim.fs.basename(vim.api.nvim_buf_get_name(buffer))
	if not name:match("%.json5?$") then
		return false
	end
	local stem = name:gsub("%.json5?$", "")
	for segment in stem:gmatch("[^.]+") do
		if segment == "mixin" or segment == "mixins" then
			return true
		end
	end
	return false
end

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
	return object.by_key[key] and object.by_key[key][1] or nil
end

local function string_value(entry)
	if entry and entry.value and entry.value.kind == "string" then
		return entry.value.value
	end
	return nil
end

local function add_duplicates(object, diagnostics)
	for key, entries in pairs(object.by_key) do
		for index = 2, #entries do
			table.insert(diagnostics, diagnostic("mixin_field_duplicate", entries[index].key_node, key))
		end
	end
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

local function find_classes(indexed, fqn)
	local matches = {}
	for _, class in ipairs(indexed.entries) do
		if class.fqn == fqn then
			table.insert(matches, class)
		end
	end
	return matches
end

local function is_mixin(class)
	return class.annotations and class.annotations.Mixin == true
end

local function qualified(package_name, name)
	if package_name == "" or vim.startswith(name, package_name .. ".") then
		return name
	end
	return package_name .. "." .. name
end

local function collect_mixins(document, package_name, diagnostics)
	local mixins = {}
	local seen = {}
	for _, list_name in ipairs(LISTS) do
		local list = first(document, list_name)
		if list then
			if list.value == nil or list.value.kind ~= "array" then
				table.insert(
					diagnostics,
					diagnostic("mixin_field_type_invalid", list.value or list, list_name .. ": array")
				)
			else
				for _, item in ipairs(list.value.items) do
					if item.kind ~= "string" or item.value == "" then
						table.insert(diagnostics, diagnostic("mixin_class_invalid", item, list_name))
					else
						local fqn = qualified(package_name, item.value)
						if seen[fqn] then
							table.insert(diagnostics, diagnostic("mixin_class_duplicate", item, fqn))
						end
						seen[fqn] = true
						table.insert(mixins, { list = list_name, value = item.value, fqn = fqn, node = item })
					end
				end
			end
		end
	end
	return mixins
end

local function validate_mixins(mixins, indexed, diagnostics)
	for _, mixin in ipairs(mixins) do
		local matches = find_classes(indexed, mixin.fqn)
		if #matches == 0 then
			local code = incomplete_index(indexed.warnings) and "mixin_class_unverified" or "mixin_class_unresolved"
			local severity = incomplete_index(indexed.warnings) and vim.diagnostic.severity.WARN or nil
			table.insert(diagnostics, diagnostic(code, mixin.node, mixin.fqn, severity))
		elseif #matches > 1 then
			table.insert(diagnostics, diagnostic("mixin_class_ambiguous", mixin.node, mixin.fqn))
		elseif not is_mixin(matches[1]) then
			table.insert(diagnostics, diagnostic("mixin_class_wrong_type", mixin.node, mixin.fqn))
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
	if not config_file(buffer) then
		return { status = "skipped", error = { code = "not_mixin_config" } }
	end
	local language = options.language
	if language == nil then
		language = vim.api.nvim_buf_get_name(buffer):match("%.json5$") and "json5" or "json"
	end
	local parsed = require("minecraft-dev.json_tree").parse_buffer({ buffer = buffer, language = language })
	if parsed.status == "parsed" and parsed.document.kind ~= "object" then
		return { status = "failed", error = { code = "mixin_root_invalid" } }
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
	for _, entry in ipairs(document.entries) do
		local expected = SCHEMA[entry.key]
		if expected and (entry.value == nil or entry.value.kind ~= expected) then
			table.insert(
				diagnostics,
				diagnostic("mixin_field_type_invalid", entry.value or entry, entry.key .. ": " .. expected)
			)
		end
	end
	local package_entry = first(document, "package")
	local package_name = string_value(package_entry)
	if package_name == nil or package_name == "" then
		table.insert(diagnostics, diagnostic("mixin_package_required", package_entry and package_entry.value or nil))
		package_name = ""
	elseif package_entry and package_entry.value and not package_name:match("^[%a_$][%w_.$]*$") then
		table.insert(diagnostics, diagnostic("mixin_package_invalid", package_entry.value, package_name))
	end
	local compatibility = first(document, "compatibilityLevel")
	local compatibility_value = string_value(compatibility)
	if compatibility and (compatibility_value == nil or not compatibility_value:match("^JAVA_%d+$")) then
		table.insert(
			diagnostics,
			diagnostic(
				"mixin_compatibility_invalid",
				compatibility.value or compatibility,
				tostring(compatibility_value or "")
			)
		)
	end
	local indexed = jvm_index.list({ buffer = buffer, root = options.root, max_files = options.max_files })
	local mixins = collect_mixins(document, package_name, diagnostics)
	validate_mixins(mixins, indexed, diagnostics)
	if package_name ~= "" then
		local package_found = false
		for _, class in ipairs(indexed.entries) do
			if
				is_mixin(class)
				and (class.package == package_name or vim.startswith(class.package, package_name .. "."))
			then
				package_found = true
				break
			end
		end
		if not package_found and package_entry and package_entry.value then
			local code = incomplete_index(indexed.warnings) and "mixin_package_unverified" or "mixin_package_unresolved"
			local severity = incomplete_index(indexed.warnings) and vim.diagnostic.severity.WARN or nil
			table.insert(diagnostics, diagnostic(code, package_entry.value, package_name, severity))
		end
	end
	local plugin = first(document, "plugin")
	local plugin_name = string_value(plugin)
	if plugin then
		if plugin_name == nil or plugin_name == "" then
			table.insert(diagnostics, diagnostic("mixin_plugin_invalid", plugin.value or plugin))
		else
			local matches = find_classes(indexed, plugin_name)
			if #matches == 0 then
				table.insert(diagnostics, diagnostic("mixin_plugin_unresolved", plugin.value, plugin_name))
			elseif #matches > 1 then
				table.insert(diagnostics, diagnostic("mixin_plugin_ambiguous", plugin.value, plugin_name))
			elseif matches[1].abstract or jvm_index.inherits(indexed, matches[1], MIXIN_PLUGIN) ~= true then
				table.insert(diagnostics, diagnostic("mixin_plugin_wrong_type", plugin.value, plugin_name))
			end
		end
	end
	vim.diagnostic.set(namespace, buffer, diagnostics)
	return {
		status = "diagnosed",
		buffer = buffer,
		diagnostics = diagnostics,
		document = document,
		package = package_name,
		mixins = mixins,
		plugin = plugin_name,
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

---@param options? { buffer?: integer, root?: string, value?: string, kind?: "mixin"|"plugin", open?: boolean, max_files?: integer }
---@return table
function M.goto_reference(options)
	options = options or {}
	local diagnosed = M.diagnose_buffer(options)
	if diagnosed.status ~= "diagnosed" then
		return vim.tbl_extend("force", diagnosed, { locations = {} })
	end
	local cursor = vim.api.nvim_win_get_cursor(0)
	local value, kind = options.value, options.kind
	if value == nil then
		for _, mixin in ipairs(diagnosed.mixins) do
			if cursor_contains(mixin.node, cursor[1] - 1, cursor[2]) then
				value, kind = mixin.fqn, "mixin"
				break
			end
		end
	end
	if value == nil and diagnosed.plugin then
		local plugin = first(diagnosed.document, "plugin")
		if plugin and plugin.value and cursor_contains(plugin.value, cursor[1] - 1, cursor[2]) then
			value, kind = diagnosed.plugin, "plugin"
		end
	end
	if type(value) ~= "string" or value == "" then
		return { status = "failed", error = { code = "mixin_reference_required" }, locations = {} }
	end
	if kind ~= "plugin" then
		value = qualified(diagnosed.package, value)
	end
	local locations = find_classes({ entries = diagnosed.classes }, value)
	if #locations == 0 then
		return { status = "failed", error = { code = "mixin_reference_unresolved", detail = value }, locations = {} }
	end
	if options.open ~= false then
		vim.cmd.edit(vim.fn.fnameescape(locations[1].path))
		vim.api.nvim_win_set_cursor(0, { locations[1].lnum + 1, locations[1].col })
	end
	return {
		status = "found",
		kind = kind or "mixin",
		value = value,
		locations = locations,
		warnings = diagnosed.warnings,
		root = diagnosed.root,
	}
end

---@param options? { buffer?: integer, root?: string, prefix?: string, kind?: "mixin"|"plugin"|"package"|"compatibilityLevel", max_files?: integer }
---@return table
function M.complete(options)
	options = options or {}
	if options.kind == "compatibilityLevel" then
		local items = {}
		for version = 6, 30 do
			local word = "JAVA_" .. version
			if options.prefix == nil or vim.startswith(word, options.prefix) then
				table.insert(items, { word = word, abbr = word, menu = "[Mixin compatibility]" })
			end
		end
		return { status = "completed", items = items }
	end
	local buffer = options.buffer or 0
	local inspected = M.inspect({ buffer = buffer })
	local package_name = inspected.status == "parsed" and string_value(first(inspected.document, "package")) or ""
	local indexed = jvm_index.list({ buffer = buffer, root = options.root, max_files = options.max_files })
	local words = {}
	for _, class in ipairs(indexed.entries) do
		local word
		if
			options.kind == "plugin"
			and not class.abstract
			and jvm_index.inherits(indexed, class, MIXIN_PLUGIN) == true
		then
			word = class.fqn
		elseif options.kind == "package" and is_mixin(class) then
			word = class.package
		elseif (options.kind == nil or options.kind == "mixin") and is_mixin(class) then
			word = package_name ~= ""
					and vim.startswith(class.fqn, package_name .. ".")
					and class.fqn:sub(#package_name + 2)
				or class.fqn
		end
		if word and (options.prefix == nil or vim.startswith(word, options.prefix)) then
			words[word] = class
		end
	end
	local items = {}
	for word, class in pairs(words) do
		table.insert(items, { word = word, abbr = word, menu = "[" .. class.language .. "]", filename = class.path })
	end
	table.sort(items, function(left, right)
		return left.word < right.word
	end)
	return { status = "completed", items = items, warnings = indexed.warnings, root = indexed.root }
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
	return M.complete({ buffer = 0, prefix = base }).items
end

function M.setup()
	_G.MinecraftDevMixinConfigComplete = completefunc
	local group = vim.api.nvim_create_augroup("MinecraftDevMixinMetadata", { clear = true })
	---@type MinecraftDevConfig
	local config = require("minecraft-dev").config
	if not config.defaults.metadata.diagnostics then
		vim.diagnostic.reset(namespace)
		return
	end
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "TextChanged", "TextChangedI" }, {
		group = group,
		pattern = { "*.json", "*.json5" },
		callback = function(event)
			if not config_file(event.buf) then
				return
			end
			if vim.bo[event.buf].completefunc == "" then
				vim.bo[event.buf].completefunc = COMPLETEFUNC
			end
			require("minecraft-dev.mixin_metadata").diagnose_buffer({ buffer = event.buf })
		end,
	})
end

function M.namespace()
	return namespace
end

return M
