local path_util = require("minecraft-dev.util.path")

local M = {}

local ORDERINGS = {
	ascending = true,
	descending = true,
	["like-default"] = true,
}

local function failure(code, detail)
	local err = { code = code }
	if detail ~= nil then
		err.detail = detail
	end
	return nil, err
end

local function skip_whitespace(content, index)
	while index <= #content and content:sub(index, index):match("%s") do
		index = index + 1
	end
	return index
end

local function scan_string(content, index)
	local start = index
	index = index + 1
	while index <= #content do
		local char = content:sub(index, index)
		if char == "\\" then
			index = index + 2
		elseif char == '"' then
			return content:sub(start, index), index + 1
		else
			index = index + 1
		end
	end
	return nil, index
end

local function parse_key_order(content)
	local keys = {}
	local seen = {}
	local index = skip_whitespace(content, 1) + 1
	index = skip_whitespace(content, index)
	if content:sub(index, index) == "}" then
		return keys
	end

	while index <= #content do
		local encoded_key
		encoded_key, index = scan_string(content, index)
		if encoded_key == nil then
			return failure("invalid_json")
		end
		local key = vim.json.decode(encoded_key)
		if seen[key] then
			return failure("duplicate_key", key)
		end
		seen[key] = true
		table.insert(keys, key)

		index = skip_whitespace(content, index)
		if content:sub(index, index) ~= ":" then
			return failure("invalid_json")
		end
		index = skip_whitespace(content, index + 1)
		local _, next_index = scan_string(content, index)
		if next_index == index then
			return failure("invalid_json")
		end
		index = skip_whitespace(content, next_index)
		local separator = content:sub(index, index)
		if separator == "}" then
			return keys
		end
		if separator ~= "," then
			return failure("invalid_json")
		end
		index = skip_whitespace(content, index + 1)
	end
	return failure("invalid_json")
end

local function parse_translations(content)
	local ok, decoded = pcall(vim.json.decode, content)
	if not ok then
		return failure("invalid_json", decoded)
	end
	if type(decoded) ~= "table" or vim.islist(decoded) then
		return failure("invalid_root")
	end

	for key, value in pairs(decoded) do
		if type(value) ~= "string" then
			return failure("invalid_value", key)
		end
	end

	local keys, key_error = parse_key_order(content)
	if keys == nil then
		return nil, key_error
	end
	return { values = decoded, keys = keys }
end

local function split_key(key)
	return vim.split(key, ".", { plain = true })
end

local function key_less(left, right)
	local left_parts = split_key(left)
	local right_parts = split_key(right)
	for index = 1, math.min(#left_parts, #right_parts) do
		if left_parts[index] ~= right_parts[index] then
			return left_parts[index] < right_parts[index]
		end
	end
	return #left_parts < #right_parts
end

local function sorted_keys(values, descending)
	local keys = vim.tbl_keys(values)
	table.sort(keys, function(left, right)
		if descending then
			return key_less(right, left)
		end
		return key_less(left, right)
	end)
	return keys
end

local function keys_like_default(values, default_keys)
	local keys = {}
	local included = {}
	for _, key in ipairs(default_keys) do
		if values[key] ~= nil and not included[key] then
			table.insert(keys, key)
			included[key] = true
		end
	end
	for _, key in ipairs(sorted_keys(values, false)) do
		if not included[key] then
			table.insert(keys, key)
		end
	end
	return keys
end

local function render(values, keys, indent, trailing_newline)
	if #keys == 0 then
		return "{}" .. (trailing_newline and "\n" or "")
	end
	local lines = { "{" }
	for index, key in ipairs(keys) do
		local suffix = index < #keys and "," or ""
		table.insert(lines, indent .. vim.json.encode(key) .. ": " .. vim.json.encode(values[key]) .. suffix)
	end
	table.insert(lines, "}")
	return table.concat(lines, "\n") .. (trailing_newline and "\n" or "")
end

---@param content string
---@param options? { order?: string, default_content?: string, indent?: string }
---@return string?, table?
function M.sort_content(content, options)
	options = options or {}
	local order = options.order or "ascending"
	if not ORDERINGS[order] then
		return failure("invalid_order", order)
	end

	local translations, parse_error = parse_translations(content)
	if translations == nil then
		return nil, parse_error
	end

	local keys
	if order == "like-default" then
		if options.default_content == nil then
			return failure("missing_default")
		end
		local defaults, default_error = parse_translations(options.default_content)
		if defaults == nil then
			return nil, default_error
		end
		keys = keys_like_default(translations.values, defaults.keys)
	else
		keys = sorted_keys(translations.values, order == "descending")
	end

	local indent = options.indent or content:match('\n([ \t]+)%"') or "  "
	return render(translations.values, keys, indent, content:sub(-1) == "\n")
end

local function is_translation_path(file_path)
	local normalized = file_path:gsub("\\", "/")
	return normalized:match("^assets/[^/]+/lang/[^/]+%.json$") ~= nil
		or normalized:match("/assets/[^/]+/lang/[^/]+%.json$") ~= nil
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

---@param options? { buffer?: integer, order?: string, default_path?: string }
---@return table
function M.sort_buffer(options)
	options = options or {}
	local buffer = options.buffer or 0
	if not vim.api.nvim_buf_is_loaded(buffer) then
		return { status = "failed", error = { code = "buffer_unloaded" } }
	end

	local file_path = vim.api.nvim_buf_get_name(buffer)
	if not is_translation_path(file_path) then
		return { status = "failed", error = { code = "not_translation_file", detail = file_path } }
	end

	local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
	local content = table.concat(lines, "\n")
	if vim.bo[buffer].eol then
		content = content .. "\n"
	end

	local config = require("minecraft-dev").config
	local translation_defaults = config.defaults.translations
	local order = options.order or translation_defaults.order
	local default_content
	if order == "like-default" then
		local default_name = translation_defaults.default_locale .. ".json"
		if vim.fs.basename(file_path):lower() == default_name:lower() then
			default_content = content
		else
			local default_path = options.default_path or path_util.join(vim.fs.dirname(file_path), default_name)
			default_content = read_file(default_path)
			if default_content == nil then
				return { status = "failed", error = { code = "missing_default", detail = default_path } }
			end
		end
	end

	local sorted, sort_error = M.sort_content(content, {
		order = order,
		default_content = default_content,
		indent = translation_defaults.indent,
	})
	if sorted == nil then
		return { status = "failed", error = sort_error }
	end

	local trailing_newline = sorted:sub(-1) == "\n"
	if trailing_newline then
		sorted = sorted:sub(1, -2)
	end
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.split(sorted, "\n", { plain = true }))
	vim.bo[buffer].eol = trailing_newline
	return { status = "sorted", buffer = buffer, order = order, path = file_path }
end

---@return string[]
function M.orderings()
	return { "ascending", "descending", "like-default" }
end

---@param order any
---@return boolean
function M.is_order(order)
	return ORDERINGS[order] == true
end

return M
