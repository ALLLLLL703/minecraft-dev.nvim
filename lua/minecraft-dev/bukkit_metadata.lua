local jvm_index = require("minecraft-dev.jvm_index")

local M = {}
local namespace = vim.api.nvim_create_namespace("minecraft-dev.metadata.bukkit")
local COMPLETEFUNC = "v:lua.MinecraftDevBukkitMainComplete"
local MANIFESTS = { ["plugin.yml"] = true, ["paper-plugin.yml"] = true }

local function manifest_buffer(buffer)
	return MANIFESTS[vim.fs.basename(vim.api.nvim_buf_get_name(buffer))] == true
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
		return { status = "skipped", error = { code = "not_bukkit_manifest" }, entries = {} }
	end
	local parsed = require("minecraft-dev.yaml_tree").parse_buffer({ buffer = buffer, language = options.language })
	if parsed.status ~= "parsed" then
		return vim.tbl_extend("force", parsed, { entries = {} })
	end
	if parsed.document.kind ~= "mapping" then
		return { status = "failed", error = { code = "invalid_yaml" }, entries = {} }
	end
	local entries = {}
	for _, entry in ipairs(parsed.document.by_key.main or {}) do
		local value = entry.value
		table.insert(entries, {
			value = value and value.kind == "scalar" and value.value or nil,
			lnum = value and value.lnum or entry.lnum,
			col = value and value.col or entry.col,
			end_lnum = value and value.end_lnum or entry.end_lnum,
			end_col = value and value.end_col or entry.end_col,
		})
	end
	return { status = "inspected", buffer = buffer, entries = entries, document = parsed.document }
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

local function find_classes(indexed, fqn)
	local matches = {}
	for _, entry in ipairs(indexed.entries) do
		if entry.fqn == fqn then
			table.insert(matches, entry)
		end
	end
	return matches
end

local function valid_fqn(value)
	if not value:match("^[%a_$][%w_.$]*$") or value:sub(-1) == "." or value:find("..", 1, true) then
		return false
	end
	for segment in value:gmatch("[^.]+") do
		if not segment:match("^[%a_$][%w_$]*$") then
			return false
		end
	end
	return true
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

local function entry_location(entry)
	return entry.value or entry.key_node or entry
end

local function scalar(entry)
	if entry and entry.value and entry.value.kind == "scalar" then
		return entry.value.value
	end
	return nil
end

local function validate_manifest_structure(document, manifest_name)
	local diagnostics = {}
	local function add(code, entry, detail)
		table.insert(diagnostics, diagnostic(code, entry and entry_location(entry) or nil, detail))
	end

	for key, entries in pairs(document.by_key) do
		if key ~= "main" and #entries > 1 then
			for index = 2, #entries do
				add("field_duplicate", entries[index], key)
			end
		end
	end
	for _, key in ipairs({ "name", "version" }) do
		local entry = document.by_key[key] and document.by_key[key][1]
		if entry == nil then
			add("field_required", nil, key)
		else
			local value = scalar(entry)
			if type(value) ~= "string" or vim.trim(value) == "" then
				add("field_scalar_required", entry, key)
			end
		end
	end

	local api_version = document.by_key["api-version"] and document.by_key["api-version"][1]
	if api_version then
		local value = scalar(api_version)
		if type(value) ~= "string" or not value:match("^%d+%.%d+$") then
			add("api_version_invalid", api_version, tostring(value or ""))
		end
	end
	for _, key in ipairs({ "commands", "permissions" }) do
		local entry = document.by_key[key] and document.by_key[key][1]
		if entry and (entry.value == nil or entry.value.kind ~= "mapping") then
			add("field_mapping_required", entry, key)
		end
	end

	local plugin_name_entry = document.by_key.name and document.by_key.name[1]
	local plugin_name = scalar(plugin_name_entry)
	for _, key in ipairs({ "depend", "softdepend", "loadbefore" }) do
		local entry = document.by_key[key] and document.by_key[key][1]
		if entry then
			if entry.value == nil or entry.value.kind ~= "sequence" then
				add("field_sequence_required", entry, key)
			else
				local seen = {}
				for _, item in ipairs(entry.value.items) do
					local value = item.kind == "scalar" and item.value or nil
					if type(value) ~= "string" or vim.trim(value) == "" then
						table.insert(diagnostics, diagnostic("dependency_name_invalid", item, key))
					elseif seen[value] then
						table.insert(diagnostics, diagnostic("dependency_duplicate", item, value))
					elseif type(plugin_name) == "string" and value == plugin_name then
						table.insert(diagnostics, diagnostic("dependency_self", item, value))
					end
					if type(value) == "string" then
						seen[value] = true
					end
				end
			end
		end
	end

	if manifest_name == "paper-plugin.yml" then
		local dependencies = document.by_key.dependencies and document.by_key.dependencies[1]
		if dependencies and (dependencies.value == nil or dependencies.value.kind ~= "mapping") then
			add("field_mapping_required", dependencies, "dependencies")
		elseif dependencies then
			for _, phase in ipairs({ "bootstrap", "server" }) do
				local phase_entry = dependencies.value.by_key[phase] and dependencies.value.by_key[phase][1]
				if phase_entry and (phase_entry.value == nil or phase_entry.value.kind ~= "mapping") then
					add("paper_dependency_phase_invalid", phase_entry, phase)
				elseif phase_entry then
					for _, dependency in ipairs(phase_entry.value.entries) do
						if type(plugin_name) == "string" and dependency.key == plugin_name then
							add("dependency_self", dependency, dependency.key)
						end
						if dependency.value == nil or dependency.value.kind ~= "mapping" then
							add("paper_dependency_invalid", dependency, dependency.key)
						else
							local load = dependency.value.by_key.load and dependency.value.by_key.load[1]
							local load_value = scalar(load)
							if
								load
								and (
									type(load_value) ~= "string"
									or not ({ BEFORE = true, AFTER = true, OMIT = true })[load_value]
								)
							then
								add("paper_dependency_load_invalid", load, tostring(load_value or ""))
							end
							for _, option in ipairs({ "required", "join-classpath" }) do
								local option_entry = dependency.value.by_key[option]
									and dependency.value.by_key[option][1]
								if option_entry and type(scalar(option_entry)) ~= "boolean" then
									add("paper_dependency_boolean_invalid", option_entry, option)
								end
							end
						end
					end
				end
			end
		end
	end
	return diagnostics
end

---@param options? { buffer?: integer, root?: string, language?: string, max_files?: integer }
---@return table
function M.diagnose_buffer(options)
	options = options or {}
	local buffer = options.buffer or 0
	local inspected = M.inspect({ buffer = buffer, language = options.language })
	if inspected.status ~= "inspected" then
		vim.diagnostic.reset(namespace, buffer)
		local diagnostics = {}
		if inspected.status == "failed" then
			table.insert(diagnostics, diagnostic(inspected.error.code))
		end
		if #diagnostics > 0 then
			vim.diagnostic.set(namespace, buffer, diagnostics)
		end
		return vim.tbl_extend("force", inspected, { buffer = buffer, diagnostics = diagnostics })
	end
	local diagnostics = {}
	if #inspected.entries == 0 then
		table.insert(diagnostics, diagnostic("main_required"))
	elseif #inspected.entries > 1 then
		for index = 2, #inspected.entries do
			table.insert(diagnostics, diagnostic("main_duplicate", inspected.entries[index]))
		end
	end
	local main = inspected.entries[1]
	local indexed = jvm_index.list({ buffer = buffer, root = options.root, max_files = options.max_files })
	if main then
		if type(main.value) ~= "string" or not valid_fqn(main.value) then
			table.insert(diagnostics, diagnostic("main_invalid", main, main.value))
		else
			local matches = find_classes(indexed, main.value)
			if #matches == 0 then
				if incomplete_index(indexed.warnings) then
					table.insert(
						diagnostics,
						diagnostic("main_resolution_incomplete", main, main.value, vim.diagnostic.severity.WARN)
					)
				else
					table.insert(diagnostics, diagnostic("main_unresolved", main, main.value))
				end
			else
				local class = matches[1]
				local status = jvm_index.is_bukkit_plugin(indexed, class)
				if class.abstract then
					table.insert(diagnostics, diagnostic("main_abstract", main, main.value))
				elseif status == false then
					table.insert(diagnostics, diagnostic("main_wrong_type", main, main.value))
				elseif status == nil then
					table.insert(
						diagnostics,
						diagnostic("main_type_unverified", main, main.value, vim.diagnostic.severity.WARN)
					)
				end
			end
		end
	end
	vim.list_extend(
		diagnostics,
		validate_manifest_structure(inspected.document, vim.fs.basename(vim.api.nvim_buf_get_name(buffer)))
	)
	vim.diagnostic.set(namespace, buffer, diagnostics)
	return {
		status = "diagnosed",
		buffer = buffer,
		main = main and main.value or nil,
		diagnostics = diagnostics,
		classes = indexed.entries,
		warnings = indexed.warnings,
		root = indexed.root,
	}
end

---@param options? table
---@return table
function M.complete(options)
	options = options or {}
	local indexed = jvm_index.list(options)
	local items = {}
	for _, entry in ipairs(indexed.entries) do
		if
			not entry.abstract
			and jvm_index.is_bukkit_plugin(indexed, entry) == true
			and (not options.prefix or vim.startswith(entry.fqn, options.prefix))
		then
			table.insert(
				items,
				{ word = entry.fqn, abbr = entry.fqn, menu = "[" .. entry.language .. "]", filename = entry.path }
			)
		end
	end
	return { status = "completed", root = indexed.root, items = items, warnings = indexed.warnings }
end

local function open_location(location)
	vim.cmd.edit(vim.fn.fnameescape(location.path))
	vim.api.nvim_win_set_cursor(0, { location.lnum + 1, location.col })
end

---@param options? table
---@return table
function M.goto_main(options)
	options = options or {}
	local buffer = options.buffer or 0
	local main = options.main
	if main == nil then
		local inspected = M.inspect({ buffer = buffer })
		main = inspected.entries and inspected.entries[1] and inspected.entries[1].value or nil
	end
	if type(main) ~= "string" or main == "" then
		return { status = "failed", error = { code = "main_required" }, locations = {} }
	end
	local indexed = jvm_index.list({ buffer = buffer, root = options.root, max_files = options.max_files })
	local locations = find_classes(indexed, main)
	if #locations == 0 then
		return {
			status = "failed",
			error = { code = "main_unresolved", detail = main },
			main = main,
			locations = {},
			warnings = indexed.warnings,
		}
	end
	if options.open ~= false then
		open_location(locations[1])
	end
	return { status = "found", main = main, locations = locations, warnings = indexed.warnings, root = indexed.root }
end

local function completefunc(find_start, base)
	if find_start == 1 then
		local line = vim.api.nvim_get_current_line()
		local cursor = vim.api.nvim_win_get_cursor(0)[2]
		local start = cursor
		while start > 0 and line:sub(start, start):match("[%w_.$]") do
			start = start - 1
		end
		return start
	end
	return M.complete({ buffer = 0, prefix = base }).items
end

function M.setup()
	_G.MinecraftDevBukkitMainComplete = completefunc
	local group = vim.api.nvim_create_augroup("MinecraftDevBukkitMetadata", { clear = true })
	---@type MinecraftDevConfig
	local config = require("minecraft-dev").config
	if not config.defaults.metadata.diagnostics then
		vim.diagnostic.reset(namespace)
		return
	end
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "TextChanged", "TextChangedI" }, {
		group = group,
		pattern = { "plugin.yml", "paper-plugin.yml" },
		callback = function(event)
			local buffer = event.buf
			if vim.bo[buffer].completefunc == "" then
				vim.bo[buffer].completefunc = COMPLETEFUNC
			end
			require("minecraft-dev.bukkit_metadata").diagnose_buffer({ buffer = buffer })
		end,
	})
end

function M.namespace()
	return namespace
end

return M
