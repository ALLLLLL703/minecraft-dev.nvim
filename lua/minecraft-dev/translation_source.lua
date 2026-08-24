local M = {}
local namespace = vim.api.nvim_create_namespace("minecraft-dev.translation-source")
local CALL_TYPES = { method_invocation = true, call_expression = true }
local ARGUMENT_TYPES = { argument_list = true, value_arguments = true }
local SKIP_DIRECTORIES = { [".git"] = true, [".gradle"] = true, build = true, target = true, node_modules = true }

local function node_text(node, buffer)
	return vim.treesitter.get_node_text(node, buffer)
end

local function find_descendant(node, accepted)
	if accepted[node:type()] then
		return node
	end
	for child in node:iter_children() do
		if child:named() then
			local found = find_descendant(child, accepted)
			if found then
				return found
			end
		end
	end
	return nil
end

local function contains_interpolation(node)
	if node:type():lower():find("interpol", 1, true) then
		return true
	end
	for child in node:iter_children() do
		if child:named() and contains_interpolation(child) then
			return true
		end
	end
	return false
end

local function decode_literal(node, buffer)
	if contains_interpolation(node) then
		return nil
	end
	local text = node_text(node, buffer)
	if text:sub(1, 1) ~= '"' or text:sub(-1) ~= '"' or text:sub(1, 3) == '"""' then
		return nil
	end
	local ok, value = pcall(vim.json.decode, text)
	if ok and type(value) == "string" then
		return value
	end
	return nil
end

local function supported_call(full_name, descriptors)
	for _, descriptor in ipairs(descriptors) do
		if full_name == descriptor or full_name:sub(-#descriptor - 1) == "." .. descriptor then
			return true
		end
	end
	return false
end

local function reference_from_call(node, buffer, descriptors)
	local call_text = node_text(node, buffer)
	local full_name = call_text:match("^%s*([%w_.$]+)%s*%(")
	if not full_name or not supported_call(full_name, descriptors) then
		return nil
	end
	local arguments = find_descendant(node, ARGUMENT_TYPES)
	if arguments == nil or arguments:named_child_count() == 0 then
		return nil
	end
	local first_argument = arguments:named_child(0)
	local literal = find_descendant(first_argument, { string_literal = true })
	if literal == nil then
		return nil
	end
	local key = decode_literal(literal, buffer)
	if key == nil then
		return nil
	end
	local start_row, start_col, end_row, end_col = literal:range()
	return {
		key = key,
		argument_count = math.max(arguments:named_child_count() - 1, 0),
		lnum = start_row,
		col = start_col,
		end_lnum = end_row,
		end_col = end_col,
		call = full_name,
	}
end

local function collect_references(node, buffer, descriptors, output)
	if CALL_TYPES[node:type()] then
		local reference = reference_from_call(node, buffer, descriptors)
		if reference then
			table.insert(output, reference)
		end
	end
	for child in node:iter_children() do
		if child:named() then
			collect_references(child, buffer, descriptors, output)
		end
	end
end

local function parse_references(buffer, language, descriptors)
	local ok, parser = pcall(vim.treesitter.get_parser, buffer, language)
	if not ok or parser == nil then
		return nil, { code = "parser_unavailable", detail = language }
	end
	local parsed, trees = pcall(function()
		return parser:parse()
	end)
	if not parsed or trees == nil or trees[1] == nil then
		return nil, { code = "parser_unavailable", detail = language }
	end
	local references = {}
	collect_references(trees[1]:root(), buffer, descriptors, references)
	return references
end

---@param options? { buffer?: integer, language?: string }
---@return table[]?, table?
function M.references_in_buffer(options)
	options = options or {}
	local buffer = options.buffer or 0
	local language = options.language or vim.bo[buffer].filetype
	if language ~= "java" and language ~= "kotlin" then
		return nil, { code = "unsupported_filetype" }
	end
	---@type MinecraftDevConfig
	local config = require("minecraft-dev").config
	return parse_references(buffer, language, config.defaults.translations.source_calls)
end

---@param file_path string
---@param language "java"|"kotlin"
---@return table[]?, table?
function M.references_in_file(file_path, language)
	local existing = vim.fn.bufnr(file_path)
	local buffer = existing
	local created = existing == -1
	if created then
		local handle = io.open(file_path, "r")
		if handle == nil then
			return nil, { code = "source_open_failed", detail = file_path }
		end
		local content = handle:read("*a")
		handle:close()
		buffer = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(buffer, file_path)
		vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.split(content, "\n", { plain = true }))
		vim.bo[buffer].filetype = language
	elseif not vim.api.nvim_buf_is_loaded(buffer) then
		vim.fn.bufload(buffer)
	end
	local references, err = M.references_in_buffer({ buffer = buffer, language = language })
	if created and vim.api.nvim_buf_is_valid(buffer) then
		vim.api.nvim_buf_delete(buffer, { force = true })
	end
	if references then
		for _, reference in ipairs(references) do
			reference.path = file_path
		end
	end
	return references, err
end

local function find_deprecated_file(directory)
	local ok, iterator = pcall(vim.fs.dir, directory)
	if not ok or iterator == nil then
		return nil
	end
	for name, kind in iterator do
		local child = vim.fs.normalize(directory .. "/" .. name)
		if kind == "directory" and not SKIP_DIRECTORIES[name] and name:sub(1, 1) ~= "." then
			local found = find_deprecated_file(child)
			if found then
				return found
			end
		elseif kind == "file" and name == "deprecated.json" then
			local normalized = child:gsub("\\", "/")
			if normalized:match("/assets/minecraft/lang/deprecated%.json$") then
				return child
			end
		end
	end
	return nil
end

local function load_deprecations(root)
	local path = find_deprecated_file(root)
	if path == nil then
		return { removed = {}, renamed = {} }
	end
	local handle = io.open(path, "r")
	if handle == nil then
		return { removed = {}, renamed = {} }
	end
	local content = handle:read("*a")
	handle:close()
	local ok, decoded = pcall(vim.json.decode, content)
	if not ok or type(decoded) ~= "table" or vim.islist(decoded) then
		return { removed = {}, renamed = {} }
	end
	local removed, renamed = {}, {}
	if type(decoded.removed) == "table" and vim.islist(decoded.removed) then
		for _, key in ipairs(decoded.removed) do
			if type(key) == "string" then
				removed[key] = true
			end
		end
	end
	if type(decoded.renamed) == "table" and not vim.islist(decoded.renamed) then
		for key, replacement in pairs(decoded.renamed) do
			if type(key) == "string" and type(replacement) == "string" then
				renamed[key] = replacement
			end
		end
	end
	return { removed = removed, renamed = renamed }
end

local function message(code, detail)
	return require("minecraft-dev.util.notify").message({ "translations", code }, tostring(detail or ""))
end

local function diagnostic(code, reference, detail)
	return {
		lnum = reference.lnum,
		col = reference.col,
		end_lnum = reference.end_lnum,
		end_col = reference.end_col,
		severity = vim.diagnostic.severity.WARN,
		message = message(code, detail or reference.key),
		source = "minecraft-dev.nvim",
		code = code,
	}
end

local function language_for_buffer(buffer, override)
	if override then
		return override
	end
	local filetype = vim.bo[buffer].filetype
	if filetype == "java" or filetype == "kotlin" then
		return filetype
	end
	return nil
end

---@param options? { buffer?: integer, root?: string, language?: string }
---@return table
function M.diagnose_buffer(options)
	options = options or {}
	local buffer = options.buffer or 0
	local language = language_for_buffer(buffer, options.language)
	if language == nil then
		vim.diagnostic.reset(namespace, buffer)
		return { status = "skipped", error = { code = "unsupported_filetype" }, diagnostics = {}, references = {} }
	end
	---@type MinecraftDevConfig
	local config = require("minecraft-dev").config
	local references, parse_error = parse_references(buffer, language, config.defaults.translations.source_calls)
	if references == nil then
		vim.diagnostic.reset(namespace, buffer)
		return { status = "skipped", error = parse_error, diagnostics = {}, references = {} }
	end

	local indexed = require("minecraft-dev.translation_index").list({ buffer = buffer, root = options.root })
	local default_by_key = {}
	for _, entry in ipairs(indexed.entries) do
		if default_by_key[entry.key] == nil then
			default_by_key[entry.key] = entry
		end
	end
	local deprecations = load_deprecations(indexed.root)
	local diagnostics = {}
	for _, reference in ipairs(references) do
		if deprecations.removed[reference.key] then
			table.insert(diagnostics, diagnostic("translation_deprecated_removed", reference, reference.key))
		elseif deprecations.renamed[reference.key] then
			table.insert(
				diagnostics,
				diagnostic(
					"translation_deprecated_renamed",
					reference,
					reference.key .. " -> " .. deprecations.renamed[reference.key]
				)
			)
		else
			local default = default_by_key[reference.key]
			if default == nil then
				table.insert(diagnostics, diagnostic("translation_missing", reference, reference.key))
			else
				local required = require("minecraft-dev.translation_diagnostics").format_argument_count(default.value)
				if reference.argument_count < required then
					table.insert(diagnostics, diagnostic("translation_format_missing", reference, reference.key))
				elseif reference.argument_count > required then
					table.insert(diagnostics, diagnostic("translation_format_superfluous", reference, reference.key))
				end
			end
		end
	end
	vim.diagnostic.set(namespace, buffer, diagnostics)
	return {
		status = "diagnosed",
		buffer = buffer,
		language = language,
		references = references,
		diagnostics = diagnostics,
		warnings = indexed.warnings,
	}
end

function M.key_at_cursor(buffer)
	---@type MinecraftDevConfig
	local config = require("minecraft-dev").config
	local language = language_for_buffer(buffer)
	if language == nil then
		return nil
	end
	local references = parse_references(buffer, language, config.defaults.translations.source_calls)
	if references == nil then
		return nil
	end
	local cursor = buffer == vim.api.nvim_get_current_buf() and vim.api.nvim_win_get_cursor(0)
		or vim.api.nvim_buf_get_mark(buffer, ".")
	local row, col = cursor[1] - 1, cursor[2]
	for _, reference in ipairs(references) do
		if
			row >= reference.lnum
			and row <= reference.end_lnum
			and (row > reference.lnum or col >= reference.col)
			and (row < reference.end_lnum or col <= reference.end_col)
		then
			return reference.key
		end
	end
	return nil
end

function M.setup()
	local group = vim.api.nvim_create_augroup("MinecraftDevTranslationSource", { clear = true })
	---@type MinecraftDevConfig
	local config = require("minecraft-dev").config
	if not config.defaults.translations.source_diagnostics then
		vim.diagnostic.reset(namespace)
		return
	end
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
		group = group,
		pattern = { "*.java", "*.kt", "*.kts" },
		callback = function(event)
			require("minecraft-dev.translation_source").diagnose_buffer({ buffer = event.buf })
		end,
	})
end

function M.namespace()
	return namespace
end

return M
