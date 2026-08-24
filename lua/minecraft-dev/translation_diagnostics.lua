local path_util = require("minecraft-dev.util.path")
local translations = require("minecraft-dev.translations")

local M = {}
local namespace = vim.api.nvim_create_namespace("minecraft-dev.translations")

local function buffer_content(buffer)
	local content = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
	if vim.bo[buffer].eol then
		content = content .. "\n"
	end
	return content
end

local function read_file(file_path)
	local handle = io.open(file_path, "r")
	if handle == nil then
		return nil
	end
	local content = handle:read("*a")
	handle:close()
	return content
end

local function format_signature(value)
	local signature, implicit_index, previous_index = {}, 1, nil
	local index = 1
	while index <= #value do
		if value:sub(index, index) ~= "%" then
			index = index + 1
		elseif value:sub(index + 1, index + 1) == "%" then
			index = index + 2
		else
			local cursor = index + 1
			local explicit = value:sub(cursor):match("^(%d+)%$")
			if explicit then
				cursor = cursor + #explicit + 1
			end
			local reuse_previous = value:sub(cursor):match("^[-#+ 0,(]*<") ~= nil
			while cursor <= #value and not value:sub(cursor, cursor):match("[bBhHsScCdoxXeEfgGaAtTn]") do
				cursor = cursor + 1
			end
			local conversion = value:sub(cursor, cursor):lower()
			if conversion ~= "" and conversion ~= "n" then
				local argument_index
				if explicit then
					argument_index = tonumber(explicit)
				elseif reuse_previous then
					argument_index = previous_index
				else
					argument_index = implicit_index
					implicit_index = implicit_index + 1
				end
				if argument_index then
					signature[argument_index] = conversion
					previous_index = argument_index
				end
			end
			index = math.max(cursor + 1, index + 1)
		end
	end
	local parts = {}
	for argument_index, conversion in pairs(signature) do
		table.insert(parts, argument_index .. ":" .. conversion)
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

function M.format_argument_count(value)
	local maximum = 0
	for argument_index in format_signature(value):gmatch("(%d+):") do
		maximum = math.max(maximum, tonumber(argument_index))
	end
	return maximum
end

local function message(code, detail)
	local keys = {
		duplicate_key = "duplicate_key",
		whitespace_key = "whitespace_key",
		invalid_lang = "invalid_lang",
		empty_key = "empty_key",
		invalid_json = "invalid_json",
		invalid_root = "invalid_root",
		invalid_value = "invalid_value",
		missing_default_key = "missing_default_key",
		format_mismatch = "format_mismatch",
	}
	return require("minecraft-dev.util.notify").message(
		{ "translations", keys[code] or "failed" },
		tostring(detail or "")
	)
end

local function diagnostic(code, entry, detail)
	local errors =
		{ invalid_lang = true, empty_key = true, invalid_json = true, invalid_root = true, invalid_value = true }
	return {
		lnum = entry.lnum or 0,
		col = entry.col or 0,
		end_lnum = entry.lnum or 0,
		end_col = math.max(entry.end_col or ((entry.col or 0) + 1), (entry.col or 0) + 1),
		severity = errors[code] and vim.diagnostic.severity.ERROR or vim.diagnostic.severity.WARN,
		message = message(code, detail or entry.key or entry.detail),
		source = "minecraft-dev.nvim",
		code = code,
	}
end

local function analyze(content, format, default_content, is_default)
	local inspected = translations.inspect_content(content, format)
	local diagnostics = {}
	for _, issue in ipairs(inspected.issues) do
		table.insert(diagnostics, diagnostic(issue.code, issue, issue.detail or issue.key or issue.lnum + 1))
	end
	if is_default or default_content == nil then
		return diagnostics
	end

	local defaults = translations.inspect_content(default_content, format)
	local fatal_default_issue = {
		duplicate_key = true,
		empty_key = true,
		invalid_lang = true,
		invalid_json = true,
		invalid_root = true,
		invalid_value = true,
	}
	for _, issue in ipairs(defaults.issues) do
		if fatal_default_issue[issue.code] then
			return diagnostics
		end
	end
	local default_by_key = {}
	for _, entry in ipairs(defaults.entries) do
		default_by_key[entry.key] = entry
	end
	for _, entry in ipairs(inspected.entries) do
		local default_entry = default_by_key[entry.key]
		if default_entry == nil then
			table.insert(diagnostics, diagnostic("missing_default_key", entry, entry.key))
		elseif format_signature(entry.value) ~= format_signature(default_entry.value) then
			table.insert(diagnostics, diagnostic("format_mismatch", entry, entry.key))
		end
	end
	return diagnostics
end

---@param options? { buffer?: integer, default_path?: string }
---@return table
function M.diagnose_buffer(options)
	options = options or {}
	local buffer = options.buffer or 0
	if not vim.api.nvim_buf_is_loaded(buffer) then
		return { status = "failed", error = { code = "buffer_unloaded" } }
	end
	local file_path = vim.api.nvim_buf_get_name(buffer)
	local format = translations.format_for_path(file_path)
	if format == nil then
		vim.diagnostic.reset(namespace, buffer)
		return { status = "skipped", buffer = buffer }
	end

	---@type MinecraftDevConfig
	local config = require("minecraft-dev").config
	local default_name = config.defaults.translations.default_locale .. "." .. format
	local is_default = vim.fs.basename(file_path):lower() == default_name:lower()
	local default_path = options.default_path or path_util.join(vim.fs.dirname(file_path), default_name)
	local default_content = is_default and buffer_content(buffer) or read_file(default_path)
	local diagnostics = analyze(buffer_content(buffer), format, default_content, is_default)
	vim.diagnostic.set(namespace, buffer, diagnostics)
	return { status = "diagnosed", buffer = buffer, diagnostics = diagnostics, path = file_path, format = format }
end

function M.setup()
	local group = vim.api.nvim_create_augroup("MinecraftDevTranslations", { clear = true })
	---@type MinecraftDevConfig
	local config = require("minecraft-dev").config
	if not config.defaults.translations.diagnostics then
		vim.diagnostic.reset(namespace)
		return
	end
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "TextChanged", "TextChangedI" }, {
		group = group,
		callback = function(event)
			require("minecraft-dev.translation_diagnostics").diagnose_buffer({ buffer = event.buf })
		end,
	})
end

function M.namespace()
	return namespace
end

M.analyze = analyze

return M
