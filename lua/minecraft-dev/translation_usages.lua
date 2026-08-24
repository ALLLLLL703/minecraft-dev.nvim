local translations = require("minecraft-dev.translations")

local M = {}
local SKIP_DIRECTORIES = { [".git"] = true, [".gradle"] = true, build = true, target = true, node_modules = true }
local SOURCE_EXTENSIONS = { java = "java", kt = "kotlin", kts = "kotlin" }
local FATAL_TRANSLATION_ISSUES = {
	duplicate_key = true,
	empty_key = true,
	invalid_lang = true,
	invalid_json = true,
	invalid_root = true,
	invalid_value = true,
}

local function content_for_path(file_path)
	local buffer = vim.fn.bufnr(file_path)
	if buffer ~= -1 and vim.api.nvim_buf_is_loaded(buffer) then
		local content = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
		if vim.bo[buffer].eol then
			content = content .. "\n"
		end
		return content
	end
	local handle = io.open(file_path, "r")
	if handle == nil then
		return nil
	end
	local content = handle:read("*a")
	handle:close()
	return content
end

local function collect_files(directory, translation_files, source_files)
	local ok, iterator = pcall(vim.fs.dir, directory)
	if not ok or iterator == nil then
		return
	end
	for name, kind in iterator do
		local child = vim.fs.normalize(directory .. "/" .. name)
		if kind == "directory" and not SKIP_DIRECTORIES[name] and name:sub(1, 1) ~= "." then
			collect_files(child, translation_files, source_files)
		elseif kind == "file" then
			if name ~= "deprecated.json" and translations.format_for_path(child) then
				table.insert(translation_files, child)
			else
				local extension = name:match("%.([^.]*)$")
				local language = extension and SOURCE_EXTENSIONS[extension]
				if language then
					table.insert(source_files, { path = child, language = language })
				end
			end
		end
	end
end

local function collect_loaded_sources(root, source_files)
	local seen = {}
	for _, source in ipairs(source_files) do
		seen[source.path] = true
	end
	local prefix = vim.fs.normalize(root) .. "/"
	for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buffer) then
			local path = vim.fs.normalize(vim.api.nvim_buf_get_name(buffer))
			local extension = path:match("%.([^./]*)$")
			local language = extension and SOURCE_EXTENSIONS[extension]
			if language and vim.startswith(path, prefix) and not seen[path] then
				table.insert(source_files, { path = path, language = language })
				seen[path] = true
			end
		end
	end
end

local function translation_locations(files, key, locations, warnings)
	for _, file_path in ipairs(files) do
		local content = content_for_path(file_path)
		local format = translations.format_for_path(file_path)
		if content == nil then
			table.insert(warnings, { code = "translation_open_failed", path = file_path })
		else
			local inspected = translations.inspect_content(content, format)
			local fatal = false
			for _, issue in ipairs(inspected.issues) do
				if FATAL_TRANSLATION_ISSUES[issue.code] then
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
				for _, entry in ipairs(inspected.entries) do
					if entry.key == key then
						table.insert(locations, {
							path = file_path,
							lnum = entry.lnum,
							col = entry.col,
							end_lnum = entry.lnum,
							end_col = entry.end_col,
							kind = "translation",
							key = key,
						})
					end
				end
			end
		end
	end
end

local function source_locations(files, key, max_files, locations, warnings)
	if #files > max_files then
		table.insert(warnings, { code = "source_scan_limit", limit = max_files, total = #files })
	end
	for index = 1, math.min(#files, max_files) do
		local source = files[index]
		local references, err =
			require("minecraft-dev.translation_source").references_in_file(source.path, source.language)
		if references == nil then
			table.insert(
				warnings,
				vim.tbl_extend("force", { path = source.path }, err or { code = "parser_unavailable" })
			)
		else
			for _, reference in ipairs(references) do
				if reference.key == key then
					table.insert(locations, vim.tbl_extend("force", reference, { kind = "source", key = key }))
				end
			end
		end
	end
end

local function location_less(left, right)
	if left.path ~= right.path then
		return left.path < right.path
	end
	if left.lnum ~= right.lnum then
		return left.lnum < right.lnum
	end
	return left.col < right.col
end

local function open_quickfix(key, locations)
	---@type MinecraftDevConfig
	local config = require("minecraft-dev").config
	local items = {}
	for _, location in ipairs(locations) do
		table.insert(items, {
			filename = location.path,
			lnum = location.lnum + 1,
			col = location.col + 1,
			end_lnum = location.end_lnum + 1,
			end_col = location.end_col + 1,
			text = string.format("%s [%s]", key, location.kind),
		})
	end
	vim.fn.setqflist({}, " ", { title = config.prompts.translations.usages_title, items = items })
	vim.cmd.copen()
end

---@param options? { buffer?: integer, root?: string, key?: string, open?: boolean, max_files?: integer }
---@return table
function M.find(options)
	options = options or {}
	local buffer = options.buffer or 0
	local indexed = require("minecraft-dev.translation_index").list({ buffer = buffer, root = options.root })
	local key = options.key or require("minecraft-dev.translation_index").key_at_cursor(buffer)
	if type(key) ~= "string" or key == "" then
		return { status = "failed", error = { code = "translation_key_required" }, locations = {}, warnings = {} }
	end
	---@type MinecraftDevConfig
	local config = require("minecraft-dev").config
	local max_files = options.max_files or config.defaults.translations.source_scan_max_files
	if type(max_files) ~= "number" or max_files < 1 or max_files % 1 ~= 0 then
		max_files = config.defaults.translations.source_scan_max_files
	end
	local translation_files, source_files = {}, {}
	collect_files(indexed.root, translation_files, source_files)
	collect_loaded_sources(indexed.root, source_files)
	table.sort(translation_files)
	table.sort(source_files, function(left, right)
		return left.path < right.path
	end)
	local locations, warnings = {}, {}
	source_locations(source_files, key, max_files, locations, warnings)
	translation_locations(translation_files, key, locations, warnings)
	table.sort(locations, location_less)
	if #locations == 0 then
		return {
			status = "failed",
			root = indexed.root,
			key = key,
			error = { code = "translation_usages_not_found", detail = key },
			locations = locations,
			warnings = warnings,
		}
	end
	if options.open ~= false then
		open_quickfix(key, locations)
	end
	return { status = "found", root = indexed.root, key = key, locations = locations, warnings = warnings }
end

return M
