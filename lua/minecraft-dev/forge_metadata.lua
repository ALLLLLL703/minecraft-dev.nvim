local M = {}

local namespace = vim.api.nvim_create_namespace("minecraft-dev.metadata.forge")
local COMPLETEFUNC = "v:lua.MinecraftDevForgeManifestComplete"
local MANIFESTS = { ["mods.toml"] = true, ["neoforge.mods.toml"] = true }
local DISPLAY_TESTS = { MATCH_VERSION = true, IGNORE_SERVER_VERSION = true, IGNORE_ALL_VERSION = true, NONE = true }
local ORDERINGS = { NONE = true, BEFORE = true, AFTER = true }
local SIDES = { BOTH = true, CLIENT = true, SERVER = true }
local VALUE_COMPLETIONS = {
	modLoader = { "javafml" },
	version = { "${file.jarVersion}", "${global.mcVersion}", "${global.forgeVersion}" },
	displayTest = { "MATCH_VERSION", "IGNORE_SERVER_VERSION", "IGNORE_ALL_VERSION", "NONE" },
	ordering = { "NONE", "BEFORE", "AFTER" },
	side = { "BOTH", "CLIENT", "SERVER" },
	showAsResourcePack = { "true", "false" },
	logoBlur = { "true", "false" },
	mandatory = { "true", "false" },
	clientSideOnly = { "true", "false" },
}
local TOP_SCHEMA = {
	modLoader = "string",
	loaderVersion = "string",
	license = "string",
	showAsResourcePack = "boolean",
	issueTrackerURL = "string",
	clientSideOnly = "boolean",
}
local MOD_SCHEMA = {
	modId = "string",
	namespace = "string",
	version = "string",
	displayName = "string",
	updateJSONURL = "string",
	displayURL = "string",
	logoFile = "string",
	logoBlur = "boolean",
	credits = "string",
	authors = "string",
	displayTest = "string",
	description = "string",
}
local DEPENDENCY_SCHEMA = {
	modId = "string",
	mandatory = "boolean",
	versionRange = "string",
	ordering = "string",
	side = "string",
	referralUrl = "string",
}
local FIELD_DOCUMENTATION = {
	modLoader = "Language loader used to load this mod file; regular Java mods use javafml.",
	loaderVersion = "Accepted language-loader versions in Maven version range syntax.",
	license = "Mod license; an SPDX identifier is recommended.",
	showAsResourcePack = "Show the mod's resources as a selectable resource pack.",
	issueTrackerURL = "URL where users should report problems with the mod.",
	clientSideOnly = "Declare that the file has no multiplayer functionality on supported Forge versions.",
	modId = "Lowercase mod identifier: 2-64 characters using letters, digits, underscore, or hyphen.",
	namespace = "Optional resource namespace used by supported NeoForge versions.",
	version = "Displayed mod version; build-time substitutions such as ${file.jarVersion} are supported.",
	displayName = "Human-readable mod name shown in the mod list.",
	updateJSONURL = "URL of the Forge update-check JSON document.",
	displayURL = "Homepage shown in the mod list.",
	logoFile = "Image path relative to the root of the resources directory.",
	logoBlur = "Whether the mod-list logo should use blur filtering.",
	credits = "Credit text shown in the mod details.",
	authors = "Author text shown in the mod details.",
	displayTest = "Client/server display compatibility: MATCH_VERSION, IGNORE_SERVER_VERSION, IGNORE_ALL_VERSION, or NONE.",
	description = "Long-form mod description.",
	mandatory = "Whether the dependency must be present.",
	versionRange = "Accepted dependency versions in Maven version range syntax.",
	ordering = "Dependency ordering relationship: NONE, BEFORE, or AFTER.",
	side = "Physical side where the dependency applies: BOTH, CLIENT, or SERVER.",
	referralUrl = "Optional dependency download URL (currently unused by Forge).",
}

local function manifest_buffer(buffer)
	return MANIFESTS[vim.fs.basename(vim.api.nvim_buf_get_name(buffer))] == true
end

local function message(code, detail)
	return require("minecraft-dev.util.notify").message({ "metadata", code }, tostring(detail or ""))
end

local function diagnostic(code, entry, detail, severity)
	entry = entry or { lnum = 0, col = 0, end_lnum = 0, end_col = 1 }
	return {
		lnum = entry.lnum,
		col = entry.col,
		end_lnum = entry.end_lnum,
		end_col = math.max(entry.end_col, entry.col + 1),
		severity = severity or vim.diagnostic.severity.ERROR,
		message = message(code, detail),
		source = "minecraft-dev.nvim",
		code = code,
	}
end

local function first(mapping, key)
	return mapping.by_key[key] and mapping.by_key[key][1] or nil
end

local function string_value(entry)
	if entry and entry.value and entry.value.kind == "string" then
		return entry.value.value
	end
	return nil
end

local function is_placeholder(value)
	return value:match("^%${[%w_.-]+}$") ~= nil
end

local function valid_mod_id(value)
	return is_placeholder(value) or value:match("^[a-z][a-z0-9_-]+$") ~= nil and #value <= 64
end

local function valid_version_range(value)
	if value == "" then
		return false
	end
	if is_placeholder(value) then
		return true
	end
	local first_char = value:sub(1, 1)
	if first_char ~= "[" and first_char ~= "(" then
		return not value:find("[%[%]%(%) ,]")
	end
	local index = 1
	while index <= #value do
		local open = value:sub(index, index)
		if open ~= "[" and open ~= "(" then
			return false
		end
		local close_index = value:find("[])]", index + 1)
		if close_index == nil then
			return false
		end
		local body = value:sub(index + 1, close_index - 1)
		if not body:find(",", 1, true) and open == "(" then
			return false
		end
		index = close_index + 1
		if index <= #value then
			if value:sub(index, index) ~= "," then
				return false
			end
			index = index + 1
		end
	end
	return true
end

local function add_duplicates(mapping, diagnostics)
	for key, entries in pairs(mapping.by_key) do
		for index = 2, #entries do
			table.insert(diagnostics, diagnostic("toml_field_duplicate", entries[index].key_node, key))
		end
	end
end

local function validate_types(mapping, schema, diagnostics)
	for _, entry in ipairs(mapping.entries) do
		local expected = schema[entry.key]
		if expected and (entry.value == nil or entry.value.kind ~= expected) then
			table.insert(
				diagnostics,
				diagnostic("toml_field_type_invalid", entry.value or entry, entry.key .. ": " .. expected)
			)
		end
	end
end

local function require_string(mapping, key, diagnostics)
	local entry = first(mapping, key)
	if entry == nil then
		table.insert(diagnostics, diagnostic("toml_field_required", nil, key))
	else
		local value = string_value(entry)
		if type(value) ~= "string" or vim.trim(value) == "" then
			table.insert(diagnostics, diagnostic("toml_field_string_required", entry.value or entry, key))
		end
	end
	return entry
end

local function resource_root(path)
	local parent = vim.fs.dirname(path)
	if vim.fs.basename(parent) == "META-INF" then
		return vim.fs.dirname(parent)
	end
	return parent
end

local function validate_logo(path, entry, diagnostics)
	local value = string_value(entry)
	if value == nil or value == "" or is_placeholder(value) then
		return
	end
	local target = vim.fs.normalize(resource_root(path) .. "/" .. value)
	if vim.uv.fs_stat(target) == nil then
		table.insert(diagnostics, diagnostic("toml_logo_unresolved", entry.value, value))
	end
end

local function source_mod_locations(indexed, mod_id)
	local locations = {}
	for _, class in ipairs(indexed.entries) do
		for _, value in ipairs(class.forge_mod_ids or {}) do
			if value == mod_id then
				table.insert(locations, vim.deepcopy(class))
			end
		end
	end
	return locations
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

---@param options? { buffer?: integer, language?: string }
---@return table
function M.inspect(options)
	options = options or {}
	local buffer = options.buffer or 0
	if not vim.api.nvim_buf_is_loaded(buffer) then
		return { status = "failed", error = { code = "buffer_unloaded" } }
	end
	if not manifest_buffer(buffer) then
		return { status = "skipped", error = { code = "not_forge_manifest" } }
	end
	return require("minecraft-dev.toml_tree").parse_buffer({ buffer = buffer, language = options.language })
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
	add_duplicates(document.top, diagnostics)
	validate_types(document.top, TOP_SCHEMA, diagnostics)
	require_string(document.top, "modLoader", diagnostics)
	local loader_version = require_string(document.top, "loaderVersion", diagnostics)
	require_string(document.top, "license", diagnostics)
	if loader_version and string_value(loader_version) and not valid_version_range(string_value(loader_version)) then
		table.insert(
			diagnostics,
			diagnostic("toml_version_range_invalid", loader_version.value, string_value(loader_version))
		)
	end

	local declared = {}
	local mod_tables = {}
	for _, item in ipairs(document.tables) do
		if item.kind == "array_table" and item.path[1] == "mods" and #item.path == 1 then
			table.insert(mod_tables, item)
			add_duplicates(item, diagnostics)
			validate_types(item, MOD_SCHEMA, diagnostics)
			local mod_id = require_string(item, "modId", diagnostics)
			local value = string_value(mod_id)
			if mod_id and mod_id.value and value then
				if not valid_mod_id(value) then
					table.insert(diagnostics, diagnostic("toml_mod_id_invalid", mod_id.value, value))
				elseif declared[value] then
					table.insert(diagnostics, diagnostic("toml_mod_id_duplicate", mod_id.value, value))
				else
					declared[value] = mod_id.value
				end
			end
			local display_test = first(item, "displayTest")
			local display_value = string_value(display_test)
			if display_test and display_test.value and display_value and not DISPLAY_TESTS[display_value] then
				table.insert(diagnostics, diagnostic("toml_display_test_invalid", display_test.value, display_value))
			end
			validate_logo(vim.api.nvim_buf_get_name(buffer), first(item, "logoFile"), diagnostics)
		end
	end
	if #mod_tables == 0 then
		table.insert(diagnostics, diagnostic("toml_mods_required"))
	end

	for _, item in ipairs(document.tables) do
		if item.kind == "array_table" and item.path[1] == "dependencies" then
			local owner = item.path[2]
			if owner == nil or declared[owner] == nil then
				table.insert(diagnostics, diagnostic("toml_dependency_owner_unresolved", item.header, owner or ""))
			end
			add_duplicates(item, diagnostics)
			validate_types(item, DEPENDENCY_SCHEMA, diagnostics)
			local dependency_id = first(item, "modId")
			local dependency_value = string_value(dependency_id)
			if dependency_id and dependency_id.value and dependency_value and not valid_mod_id(dependency_value) then
				table.insert(diagnostics, diagnostic("toml_mod_id_invalid", dependency_id.value, dependency_value))
			end
			local version_range = first(item, "versionRange")
			local version_value = string_value(version_range)
			if version_range and version_range.value and version_value and not valid_version_range(version_value) then
				table.insert(diagnostics, diagnostic("toml_version_range_invalid", version_range.value, version_value))
			end
			local ordering = first(item, "ordering")
			local ordering_value = string_value(ordering)
			if ordering and ordering.value and ordering_value and not ORDERINGS[ordering_value] then
				table.insert(diagnostics, diagnostic("toml_ordering_invalid", ordering.value, ordering_value))
			end
			local side = first(item, "side")
			local side_value = string_value(side)
			if side and side.value and side_value and not SIDES[side_value] then
				table.insert(diagnostics, diagnostic("toml_side_invalid", side.value, side_value))
			end
		end
	end
	local indexed = require("minecraft-dev.jvm_index").list({
		buffer = buffer,
		root = options.root,
		max_files = options.max_files,
	})
	for mod_id, entry in pairs(declared) do
		if not is_placeholder(mod_id) and #source_mod_locations(indexed, mod_id) == 0 then
			local code = incomplete_index(indexed.warnings) and "toml_mod_source_unverified"
				or "toml_mod_source_unresolved"
			local severity = incomplete_index(indexed.warnings) and vim.diagnostic.severity.WARN or nil
			table.insert(diagnostics, diagnostic(code, entry, mod_id, severity))
		end
	end

	vim.diagnostic.set(namespace, buffer, diagnostics)
	return {
		status = "diagnosed",
		buffer = buffer,
		diagnostics = diagnostics,
		document = document,
		declared = declared,
		classes = indexed.entries,
		warnings = indexed.warnings,
		root = indexed.root,
	}
end

local function table_at_row(document, row)
	local selected
	for _, item in ipairs(document.tables) do
		if item.lnum <= row and (selected == nil or item.lnum > selected.lnum) then
			selected = item
		end
	end
	return selected
end

local function keys_for_table(item)
	if item == nil then
		return vim.tbl_keys(TOP_SCHEMA)
	end
	if item.path[1] == "mods" then
		return vim.tbl_keys(MOD_SCHEMA)
	end
	if item.path[1] == "dependencies" then
		return vim.tbl_keys(DEPENDENCY_SCHEMA)
	end
	return {}
end

---@param options? { buffer?: integer, prefix?: string, row?: integer, col?: integer, line?: string }
---@return table
function M.complete(options)
	options = options or {}
	local buffer = options.buffer or 0
	local inspected = M.inspect({ buffer = buffer })
	if inspected.status ~= "parsed" then
		return vim.tbl_extend("force", inspected, { items = {} })
	end
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = options.row or cursor[1] - 1
	local line = options.line or vim.api.nvim_buf_get_lines(buffer, row, row + 1, false)[1] or ""
	local before = line:sub(1, options.col or cursor[2])
	local value_key = before:match("^%s*([%w_-]+)%s*=%s*[^=]*$")
	local words = value_key and VALUE_COMPLETIONS[value_key] or nil
	if value_key == "modId" then
		words = { "minecraft" }
		local indexed = require("minecraft-dev.jvm_index").list({ buffer = buffer })
		for _, class in ipairs(indexed.entries) do
			for _, mod_id in ipairs(class.forge_mod_ids or {}) do
				table.insert(words, mod_id)
			end
		end
	end
	if words == nil then
		local dependency_prefix = before:match("^%s*%[%[dependencies%.([%w_${}_.-]*)$")
		if dependency_prefix ~= nil then
			words = {}
			for _, item in ipairs(inspected.document.tables) do
				if item.path[1] == "mods" then
					local value = string_value(first(item, "modId"))
					if value then
						table.insert(words, value)
					end
				end
			end
		else
			words = keys_for_table(table_at_row(inspected.document, row))
		end
	end
	local prefix = options.prefix or ""
	local items = {}
	for _, word in ipairs(words) do
		if prefix == "" or vim.startswith(word, prefix) then
			table.insert(items, {
				word = word,
				abbr = word,
				menu = "[Minecraft metadata]",
				info = FIELD_DOCUMENTATION[value_key or word],
			})
		end
	end
	table.sort(items, function(left, right)
		return left.word < right.word
	end)
	return { status = "completed", items = items }
end

local function cursor_contains(node, row, col)
	return row >= node.lnum
		and row <= node.end_lnum
		and (row > node.lnum or col >= node.col)
		and (row < node.end_lnum or col <= node.end_col)
end

local function mod_id_at_cursor(document, row, col)
	for _, item in ipairs(document.tables) do
		if item.path[1] == "dependencies" and item.path[2] and cursor_contains(item.header, row, col) then
			return item.path[2], "manifest"
		end
		local entry = first(item, "modId")
		if entry and entry.value and cursor_contains(entry.value, row, col) then
			return string_value(entry), "source"
		end
	end
	return nil
end

---@param options? { buffer?: integer, root?: string, mod_id?: string, target?: "manifest"|"source", open?: boolean, max_files?: integer }
---@return table
function M.goto_mod(options)
	options = options or {}
	local buffer = options.buffer or 0
	local inspected = M.inspect({ buffer = buffer })
	if inspected.status ~= "parsed" then
		return vim.tbl_extend("force", inspected, { locations = {} })
	end
	local cursor = vim.api.nvim_win_get_cursor(0)
	local cursor_mod_id, cursor_target = mod_id_at_cursor(inspected.document, cursor[1] - 1, cursor[2])
	local mod_id = options.mod_id or cursor_mod_id
	local target = options.target or cursor_target or "source"
	if type(mod_id) ~= "string" or mod_id == "" then
		return { status = "failed", error = { code = "toml_mod_id_required" }, locations = {} }
	end
	local locations, warnings, root = {}, {}, nil
	if target == "manifest" then
		for _, item in ipairs(inspected.document.tables) do
			if item.path[1] == "mods" then
				local entry = first(item, "modId")
				if entry and entry.value and string_value(entry) == mod_id then
					table.insert(
						locations,
						vim.tbl_extend("force", entry.value, { path = vim.api.nvim_buf_get_name(buffer) })
					)
				end
			end
		end
	else
		local indexed = require("minecraft-dev.jvm_index").list({
			buffer = buffer,
			root = options.root,
			max_files = options.max_files,
		})
		locations = source_mod_locations(indexed, mod_id)
		warnings = indexed.warnings
		root = indexed.root
	end
	if #locations == 0 then
		return {
			status = "failed",
			error = { code = "toml_mod_id_unresolved", detail = mod_id },
			locations = {},
			warnings = warnings,
		}
	end
	if options.open ~= false then
		vim.cmd.edit(vim.fn.fnameescape(locations[1].path))
		vim.api.nvim_win_set_cursor(0, { locations[1].lnum + 1, locations[1].col })
	end
	return {
		status = "found",
		mod_id = mod_id,
		target = target,
		locations = locations,
		warnings = warnings,
		root = root,
	}
end

---@param options? { buffer?: integer, open?: boolean }
---@return table
function M.goto_logo(options)
	options = options or {}
	local buffer = options.buffer or 0
	local inspected = M.inspect({ buffer = buffer })
	if inspected.status ~= "parsed" then
		return vim.tbl_extend("force", inspected, { locations = {} })
	end
	local cursor = vim.api.nvim_win_get_cursor(0)
	for _, item in ipairs(inspected.document.tables) do
		local logo = first(item, "logoFile")
		if logo and logo.value and cursor_contains(logo.value, cursor[1] - 1, cursor[2]) then
			local value = string_value(logo)
			local path = value and vim.fs.normalize(resource_root(vim.api.nvim_buf_get_name(buffer)) .. "/" .. value)
			if path and vim.uv.fs_stat(path) then
				local location = { path = path, lnum = 0, col = 0, end_lnum = 0, end_col = 1 }
				if options.open ~= false then
					vim.cmd.edit(vim.fn.fnameescape(path))
				end
				return { status = "found", locations = { location } }
			end
			return { status = "failed", error = { code = "toml_logo_unresolved", detail = value }, locations = {} }
		end
	end
	return { status = "failed", error = { code = "toml_logo_required" }, locations = {} }
end

local function completefunc(findstart, base)
	if findstart == 1 then
		local line = vim.api.nvim_get_current_line()
		local col = vim.fn.col(".") - 1
		local start = col
		while start > 0 and line:sub(start, start):match("[%w_${}_.-]") do
			start = start - 1
		end
		return start
	end
	return M.complete({ buffer = 0, prefix = base }).items
end

function M.setup()
	_G.MinecraftDevForgeManifestComplete = completefunc
	local group = vim.api.nvim_create_augroup("MinecraftDevForgeMetadata", { clear = true })
	---@type MinecraftDevConfig
	local config = require("minecraft-dev").config
	if not config.defaults.metadata.diagnostics then
		vim.diagnostic.reset(namespace)
		return
	end
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "TextChanged", "TextChangedI" }, {
		group = group,
		pattern = { "mods.toml", "neoforge.mods.toml" },
		callback = function(event)
			if vim.bo[event.buf].completefunc == "" then
				vim.bo[event.buf].completefunc = COMPLETEFUNC
			end
			require("minecraft-dev.forge_metadata").diagnose_buffer({ buffer = event.buf })
		end,
	})
end

function M.namespace()
	return namespace
end

M.valid_mod_id = valid_mod_id
M.valid_version_range = valid_version_range

return M
