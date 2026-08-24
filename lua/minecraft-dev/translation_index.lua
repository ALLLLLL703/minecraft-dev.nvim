local translations = require("minecraft-dev.translations")

local M = {}
local COMPLETEFUNC = "v:lua.MinecraftDevTranslationComplete"
local SKIP_DIRECTORIES = { [".git"] = true, [".gradle"] = true, build = true, target = true, node_modules = true }

local function read_file(file_path)
	local handle = io.open(file_path, "r")
	if handle == nil then
		return nil
	end
	local content = handle:read("*a")
	handle:close()
	return content
end

local function buffer_content(buffer)
	local content = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
	if vim.bo[buffer].eol then
		content = content .. "\n"
	end
	return content
end

local function resolve_root(buffer, explicit_root)
	if explicit_root then
		return vim.fs.normalize(explicit_root)
	end
	local file_path = vim.api.nvim_buf_get_name(buffer)
	if file_path ~= "" then
		local root = vim.fs.root(
			file_path,
			{ ".git", "settings.gradle", "settings.gradle.kts", "build.gradle", "build.gradle.kts", "pom.xml" }
		)
		if root then
			return root
		end
	end
	return vim.fn.getcwd()
end

local function collect_default_files(directory, default_basename, files)
	local ok, iterator = pcall(vim.fs.dir, directory)
	if not ok or iterator == nil then
		return
	end
	for name, kind in iterator do
		local child = vim.fs.normalize(directory .. "/" .. name)
		if kind == "directory" and not SKIP_DIRECTORIES[name] and name:sub(1, 1) ~= "." then
			collect_default_files(child, default_basename, files)
		elseif kind == "file" and (name == default_basename .. ".json" or name == default_basename .. ".lang") then
			if translations.format_for_path(child) then
				table.insert(files, child)
			end
		end
	end
end

local function unique_keys(entries, prefix)
	local seen, keys = {}, {}
	for _, entry in ipairs(entries) do
		if not seen[entry.key] and (prefix == nil or vim.startswith(entry.key, prefix)) then
			seen[entry.key] = true
			table.insert(keys, entry.key)
		end
	end
	table.sort(keys, translations.key_less)
	return keys
end

---@param options? { buffer?: integer, root?: string, prefix?: string }
---@return table
function M.list(options)
	options = options or {}
	local buffer = options.buffer or 0
	local root = resolve_root(buffer, options.root)
	---@type MinecraftDevConfig
	local config = require("minecraft-dev").config
	local files = {}
	collect_default_files(root, config.defaults.translations.default_locale, files)
	table.sort(files)
	local entries, warnings = {}, {}
	for _, file_path in ipairs(files) do
		local content = read_file(file_path)
		local format = translations.format_for_path(file_path)
		if content and format then
			local inspected = translations.inspect_content(content, format)
			local fatal = false
			local fatal_codes = {
				duplicate_key = true,
				empty_key = true,
				invalid_lang = true,
				invalid_json = true,
				invalid_root = true,
				invalid_value = true,
			}
			for _, issue in ipairs(inspected.issues) do
				if fatal_codes[issue.code] then
					fatal = true
				end
			end
			if #inspected.issues > 0 then
				table.insert(
					warnings,
					{ code = "invalid_translation_file", path = file_path, issues = inspected.issues }
				)
			end
			if not fatal then
				local normalized = file_path:gsub("\\", "/")
				local namespace = normalized:match("/assets/([^/]+)/lang/")
				for _, entry in ipairs(inspected.entries) do
					local indexed = vim.deepcopy(entry)
					indexed.path = file_path
					indexed.namespace = namespace
					indexed.locale = config.defaults.translations.default_locale
					table.insert(entries, indexed)
				end
			end
		end
	end
	return {
		status = "indexed",
		root = root,
		entries = entries,
		keys = unique_keys(entries, options.prefix),
		warnings = warnings,
	}
end

---@param options? { buffer?: integer, root?: string, prefix?: string }
---@return table
function M.complete(options)
	options = options or {}
	local buffer = options.buffer or 0
	local indexed = M.list(options)
	local existing = {}
	local file_path = vim.api.nvim_buf_get_name(buffer)
	local format = translations.format_for_path(file_path)
	if format then
		for _, entry in ipairs(translations.inspect_content(buffer_content(buffer), format).entries) do
			existing[entry.key] = true
		end
	end
	local first_by_key = {}
	for _, entry in ipairs(indexed.entries) do
		if first_by_key[entry.key] == nil then
			first_by_key[entry.key] = entry
		end
	end
	local items = {}
	for _, key in ipairs(indexed.keys) do
		if not existing[key] then
			local entry = first_by_key[key]
			table.insert(items, { word = key, abbr = key, menu = "[" .. entry.locale .. "]", info = entry.value })
		end
	end
	return { status = "completed", root = indexed.root, items = items, warnings = indexed.warnings }
end

local function key_at_cursor(buffer)
	local format = translations.format_for_path(vim.api.nvim_buf_get_name(buffer))
	if not format then
		return require("minecraft-dev.translation_source").key_at_cursor(buffer)
	end
	local cursor = buffer == vim.api.nvim_get_current_buf() and vim.api.nvim_win_get_cursor(0)
		or vim.api.nvim_buf_get_mark(buffer, ".")
	for _, entry in ipairs(translations.inspect_content(buffer_content(buffer), format).entries) do
		if entry.lnum == cursor[1] - 1 and cursor[2] >= entry.col and cursor[2] <= entry.end_col then
			return entry.key
		end
	end
	return nil
end

M.key_at_cursor = key_at_cursor

local function open_location(location)
	vim.cmd.edit(vim.fn.fnameescape(location.path))
	vim.api.nvim_win_set_cursor(0, { location.lnum + 1, location.col })
end

---@param options? { buffer?: integer, root?: string, key?: string, open?: boolean }
---@return table
function M.goto_translation(options)
	options = options or {}
	local buffer = options.buffer or 0
	local key = options.key or key_at_cursor(buffer)
	if key == nil or key == "" then
		return { status = "failed", error = { code = "translation_key_required" } }
	end
	local indexed = M.list({ buffer = buffer, root = options.root })
	local locations = {}
	for _, entry in ipairs(indexed.entries) do
		if entry.key == key then
			table.insert(locations, entry)
		end
	end
	table.sort(locations, function(left, right)
		if left.path ~= right.path then
			return left.path < right.path
		end
		return left.lnum < right.lnum
	end)
	if #locations == 0 then
		return { status = "failed", key = key, error = { code = "translation_not_found", detail = key } }
	end
	local result = { status = "found", key = key, locations = locations, warnings = indexed.warnings }
	if options.open == false then
		return result
	end
	if #locations == 1 then
		open_location(locations[1])
		result.opened = locations[1]
		return result
	end
	result.status = "selection_pending"
	---@type MinecraftDevConfig
	local config = require("minecraft-dev").config
	vim.ui.select(locations, {
		prompt = config.prompts.translations.select_translation,
		format_item = function(location)
			return (location.namespace or "?") .. " — " .. location.path
		end,
	}, function(location)
		if location then
			open_location(location)
		end
	end)
	return result
end

function M.configure_buffer(buffer)
	local file_path = vim.api.nvim_buf_get_name(buffer)
	local format = translations.format_for_path(file_path)
	if not format then
		if vim.bo[buffer].completefunc == COMPLETEFUNC then
			vim.bo[buffer].completefunc = ""
		end
		return
	end
	---@type MinecraftDevConfig
	local config = require("minecraft-dev").config
	local default_name = config.defaults.translations.default_locale .. "." .. format
	if vim.fs.basename(file_path):lower() ~= default_name:lower() and vim.bo[buffer].completefunc == "" then
		vim.bo[buffer].completefunc = COMPLETEFUNC
	end
end

function M.completefunc(find_start, base)
	if find_start == 1 then
		local cursor = vim.api.nvim_win_get_cursor(0)
		local before = vim.api.nvim_get_current_line():sub(1, cursor[2])
		local fragment = before:match("[%w_.%-]*$") or ""
		return cursor[2] - #fragment
	end
	return M.complete({ buffer = 0, prefix = base }).items
end

function M.setup()
	_G.MinecraftDevTranslationComplete = function(find_start, base)
		return M.completefunc(find_start, base)
	end
	local group = vim.api.nvim_create_augroup("MinecraftDevTranslationIndex", { clear = true })
	vim.api.nvim_create_autocmd({ "BufEnter", "BufFilePost" }, {
		group = group,
		callback = function(event)
			require("minecraft-dev.translation_index").configure_buffer(event.buf)
		end,
	})
	for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buffer) then
			M.configure_buffer(buffer)
		end
	end
end

return M
