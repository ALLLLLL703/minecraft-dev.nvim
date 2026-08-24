local jvm_index = require("minecraft-dev.jvm_index")

local M = {}
local namespace = vim.api.nvim_create_namespace("minecraft-dev.metadata.bukkit")
local COMPLETEFUNC = "v:lua.MinecraftDevBukkitMainComplete"
local MANIFESTS = { ["plugin.yml"] = true, ["paper-plugin.yml"] = true }

local function buffer_content(buffer)
	local content = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
	if vim.bo[buffer].eol then
		content = content .. "\n"
	end
	return content
end

local function manifest_buffer(buffer)
	return MANIFESTS[vim.fs.basename(vim.api.nvim_buf_get_name(buffer))] == true
end

local function decode_scalar(text)
	text = vim.trim(text)
	if text:sub(1, 1) == '"' and text:sub(-1) == '"' then
		local ok, decoded = pcall(vim.json.decode, text)
		return ok and decoded or nil
	end
	if text:sub(1, 1) == "'" and text:sub(-1) == "'" then
		return text:sub(2, -2):gsub("''", "'")
	end
	return vim.trim((text:gsub("%s+#.*$", "")))
end

local function collect_main_pairs(node, buffer, output)
	if node:type() == "block_mapping_pair" then
		local row, col = node:range()
		if col == 0 then
			local children = {}
			for child in node:iter_children() do
				if child:named() then
					table.insert(children, child)
				end
			end
			if children[1] and vim.trim(vim.treesitter.get_node_text(children[1], buffer)) == "main" then
				local value_node = children[2]
				local value = value_node and decode_scalar(vim.treesitter.get_node_text(value_node, buffer)) or nil
				local start_row, start_col, end_row, end_col
				if value_node then
					start_row, start_col, end_row, end_col = value_node:range()
				else
					start_row, start_col, end_row, end_col = node:range()
				end
				table.insert(output, {
					value = value,
					lnum = start_row or row,
					col = start_col or col,
					end_lnum = end_row or row,
					end_col = end_col or (col + 4),
				})
			end
		end
	end
	for child in node:iter_children() do
		if child:named() then
			collect_main_pairs(child, buffer, output)
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
	if not manifest_buffer(buffer) then
		return { status = "skipped", error = { code = "not_bukkit_manifest" }, entries = {} }
	end
	local language = options.language or "yaml"
	local ok, parser = pcall(vim.treesitter.get_parser, buffer, language)
	if not ok or parser == nil then
		return { status = "skipped", error = { code = "parser_unavailable", detail = language }, entries = {} }
	end
	local parsed, trees = pcall(function()
		return parser:parse()
	end)
	if not parsed or trees == nil or trees[1] == nil then
		return { status = "skipped", error = { code = "parser_unavailable", detail = language }, entries = {} }
	end
	local root = trees[1]:root()
	if root:has_error() then
		return { status = "failed", error = { code = "invalid_yaml" }, entries = {} }
	end
	local entries = {}
	collect_main_pairs(root, buffer, entries)
	return { status = "inspected", buffer = buffer, entries = entries, content = buffer_content(buffer) }
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
