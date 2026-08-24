local path_util = require("minecraft-dev.util.path")

local M = {}

local ORDERINGS = {
	ascending = true,
	descending = true,
	["like-default"] = true,
	template = true,
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
	local keys, seen = {}, {}
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

local function parse_json(content)
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
	return { format = "json", values = decoded, keys = keys }
end

local function split_pending(lines)
	local first_comment = #lines + 1
	while first_comment > 1 and vim.trim(lines[first_comment - 1]):match("^#") do
		first_comment = first_comment - 1
	end
	local layout, comments = {}, {}
	for index = 1, first_comment - 1 do
		table.insert(layout, lines[index])
	end
	for index = first_comment, #lines do
		table.insert(comments, lines[index])
	end
	return layout, comments
end

local function parse_lang(content)
	local trailing_newline = content:sub(-1) == "\n"
	local lines = vim.split(content, "\n", { plain = true })
	if trailing_newline then
		table.remove(lines)
	end
	local parsed = {
		format = "lang",
		values = {},
		keys = {},
		comments = {},
		leading = {},
		separators = {},
		trailing = {},
		trailing_newline = trailing_newline,
	}
	local pending = {}
	for line_number, line in ipairs(lines) do
		local trimmed = vim.trim(line)
		if trimmed == "" or trimmed:match("^#") then
			table.insert(pending, line)
		else
			local separator = line:find("=", 1, true)
			if separator == nil then
				return failure("invalid_lang", line_number)
			end
			local key = vim.trim(line:sub(1, separator - 1))
			if key == "" then
				return failure("empty_key", line_number)
			end
			if parsed.values[key] ~= nil then
				return failure("duplicate_key", key)
			end
			local layout, comments = split_pending(pending)
			if #parsed.keys == 0 then
				parsed.leading = layout
			else
				parsed.separators[#parsed.keys] = layout
			end
			pending = {}
			parsed.values[key] = line:sub(separator + 1)
			parsed.comments[key] = comments
			table.insert(parsed.keys, key)
		end
	end
	parsed.trailing = pending
	return parsed
end

local function parse(content, format)
	if format == "lang" then
		return parse_lang(content)
	end
	return parse_json(content)
end

local function split_key(key)
	return vim.split(key, ".", { plain = true })
end

local function key_less(left, right)
	local left_parts, right_parts = split_key(left), split_key(right)
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
		return descending and key_less(right, left) or (not descending and key_less(left, right))
	end)
	return keys
end

local function keys_like_default(values, default_keys)
	local keys, included = {}, {}
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

local QUANTIFIERS = {
	["!"] = { min = 1, max = 1, non_dot = true },
	["!+"] = { min = 1, non_dot = true },
	["!*"] = { min = 0, non_dot = true },
	["?"] = { min = 1, max = 1 },
	["?+"] = { min = 2 },
	["?*"] = { min = 1 },
	["+"] = { min = 1 },
	["*"] = { min = 0 },
}

local function tokenize_matcher(pattern)
	local tokens, literal = {}, {}
	local function flush_literal()
		if #literal > 0 then
			table.insert(tokens, { literal = table.concat(literal) })
			literal = {}
		end
	end
	local index = 1
	while index <= #pattern do
		local pair = pattern:sub(index, index + 1)
		local single = pattern:sub(index, index)
		local quantifier = QUANTIFIERS[pair] and pair or QUANTIFIERS[single] and single or nil
		if quantifier then
			flush_literal()
			table.insert(tokens, QUANTIFIERS[quantifier])
			index = index + #quantifier
		else
			table.insert(literal, single)
			index = index + 1
		end
	end
	flush_literal()
	return tokens
end

local function matcher_matches(tokens, key)
	local memo = {}
	local function visit(token_index, key_index)
		local memo_key = token_index .. ":" .. key_index
		if memo[memo_key] ~= nil then
			return memo[memo_key]
		end
		if token_index > #tokens then
			return key_index > #key
		end
		local token = tokens[token_index]
		if token.literal then
			local matches = key:sub(key_index, key_index + #token.literal - 1) == token.literal
			memo[memo_key] = matches and visit(token_index + 1, key_index + #token.literal) or false
			return memo[memo_key]
		end
		local available = #key - key_index + 1
		local maximum = math.min(token.max or available, available)
		if token.non_dot then
			maximum = 0
			while maximum < available and key:sub(key_index + maximum, key_index + maximum) ~= "." do
				maximum = maximum + 1
			end
			if token.max then
				maximum = math.min(maximum, token.max)
			end
		end
		for count = maximum, token.min, -1 do
			if visit(token_index + 1, key_index + count) then
				memo[memo_key] = true
				return true
			end
		end
		memo[memo_key] = false
		return false
	end
	return visit(1, 1)
end

local function parse_template(content)
	if content == nil or content == "" then
		return {}
	end
	local elements = {}
	local lines = vim.split(content or "", "\n", { plain = true })
	if (content or ""):sub(-1) == "\n" then
		table.remove(lines)
	end
	for _, line in ipairs(lines) do
		local trimmed = vim.trim(line)
		if trimmed == "" then
			table.insert(elements, { kind = "empty" })
		elseif trimmed:match("^#") then
			table.insert(elements, { kind = "comment", text = vim.trim(trimmed:sub(2)) })
		else
			table.insert(elements, { kind = "matcher", tokens = tokenize_matcher(trimmed) })
		end
	end
	return elements
end

local function template_items(values, template_content)
	local remaining, items = sorted_keys(values, false), {}
	for _, element in ipairs(parse_template(template_content)) do
		if element.kind == "matcher" then
			local unmatched = {}
			for _, key in ipairs(remaining) do
				if matcher_matches(element.tokens, key) then
					table.insert(items, { kind = "key", key = key })
				else
					table.insert(unmatched, key)
				end
			end
			remaining = unmatched
		else
			table.insert(items, element)
		end
	end
	for _, key in ipairs(remaining) do
		table.insert(items, { kind = "key", key = key })
	end
	return items
end

local function key_items(keys)
	local items = {}
	for _, key in ipairs(keys) do
		table.insert(items, { kind = "key", key = key })
	end
	return items
end

local function render_json(values, items, indent, trailing_newline)
	local key_count = 0
	for _, item in ipairs(items) do
		if item.kind == "key" then
			key_count = key_count + 1
		end
	end
	if key_count == 0 then
		return "{}" .. (trailing_newline and "\n" or "")
	end
	local lines, written = { "{" }, 0
	for _, item in ipairs(items) do
		if item.kind == "key" then
			written = written + 1
			local suffix = written < key_count and "," or ""
			table.insert(
				lines,
				indent .. vim.json.encode(item.key) .. ": " .. vim.json.encode(values[item.key]) .. suffix
			)
		elseif item.kind == "empty" then
			table.insert(lines, "")
		end
	end
	table.insert(lines, "}")
	return table.concat(lines, "\n") .. (trailing_newline and "\n" or "")
end

local function append_all(target, values)
	for _, value in ipairs(values or {}) do
		table.insert(target, value)
	end
end

local function render_lang(parsed, items, templated)
	local lines = {}
	if not templated then
		append_all(lines, parsed.leading)
	end
	local written = 0
	for _, item in ipairs(items) do
		if item.kind == "key" then
			if not templated and written > 0 then
				append_all(lines, parsed.separators[written])
			end
			append_all(lines, parsed.comments[item.key])
			table.insert(lines, item.key .. "=" .. parsed.values[item.key])
			written = written + 1
		elseif templated and item.kind == "empty" then
			table.insert(lines, "")
		elseif templated and item.kind == "comment" then
			table.insert(lines, "# " .. item.text)
		end
	end
	if not templated then
		append_all(lines, parsed.trailing)
	end
	local result = table.concat(lines, "\n")
	return result .. (parsed.trailing_newline and "\n" or "")
end

---@param content string
---@param options? { order?: string, default_content?: string, template_content?: string, format?: string, indent?: string }
---@return string?, table?
function M.sort_content(content, options)
	options = options or {}
	local order = options.order or "ascending"
	if not ORDERINGS[order] then
		return failure("invalid_order", order)
	end
	local format = options.format == "lang" and "lang" or "json"
	local translations, parse_error = parse(content, format)
	if translations == nil then
		return nil, parse_error
	end

	local items
	if order == "like-default" then
		if options.default_content == nil then
			return failure("missing_default")
		end
		local defaults, default_error = parse(options.default_content, format)
		if defaults == nil then
			return nil, default_error
		end
		items = key_items(keys_like_default(translations.values, defaults.keys))
	elseif order == "template" then
		if options.template_content == nil then
			return failure("missing_template")
		end
		items = template_items(translations.values, options.template_content)
	else
		items = key_items(sorted_keys(translations.values, order == "descending"))
	end

	if format == "lang" then
		return render_lang(translations, items, order == "template")
	end
	local indent = options.indent or content:match('\n([ \t]+)%"') or "  "
	return render_json(translations.values, items, indent, content:sub(-1) == "\n")
end

local function translation_format(file_path)
	local normalized = file_path:gsub("\\", "/")
	local extension = normalized:match("/assets/[^/]+/lang/[^/]+%.(json)$")
		or normalized:match("^assets/[^/]+/lang/[^/]+%.(json)$")
		or normalized:match("/assets/[^/]+/lang/[^/]+%.(lang)$")
		or normalized:match("^assets/[^/]+/lang/[^/]+%.(lang)$")
	return extension
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

local function resolve_template_path(configured_path)
	if configured_path == nil then
		return nil
	end
	if path_util.is_absolute(configured_path) then
		return configured_path
	end
	return path_util.join(vim.fn.getcwd(), configured_path)
end

---@param options? { buffer?: integer, order?: string, default_path?: string, template_path?: string, template_content?: string }
---@return table
function M.sort_buffer(options)
	options = options or {}
	local buffer = options.buffer or 0
	if not vim.api.nvim_buf_is_loaded(buffer) then
		return { status = "failed", error = { code = "buffer_unloaded" } }
	end

	local file_path = vim.api.nvim_buf_get_name(buffer)
	local format = translation_format(file_path)
	if format == nil then
		return { status = "failed", error = { code = "not_translation_file", detail = file_path } }
	end

	local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
	local content = table.concat(lines, "\n")
	if vim.bo[buffer].eol then
		content = content .. "\n"
	end

	---@type MinecraftDevConfig
	local config = require("minecraft-dev").config
	local translation_defaults = config.defaults.translations
	local order = options.order or translation_defaults.order
	local default_content
	if order == "like-default" then
		local default_name = translation_defaults.default_locale .. "." .. format
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

	local template_content = options.template_content
	if order == "template" and template_content == nil then
		local template_path = resolve_template_path(options.template_path or translation_defaults.template_path)
		if template_path == nil then
			return { status = "failed", error = { code = "missing_template" } }
		end
		template_content = read_file(template_path)
		if template_content == nil then
			return { status = "failed", error = { code = "missing_template", detail = template_path } }
		end
	end

	local sorted, sort_error = M.sort_content(content, {
		order = order,
		format = format,
		default_content = default_content,
		template_content = template_content,
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
	return { status = "sorted", buffer = buffer, order = order, path = file_path, format = format }
end

---@return string[]
function M.orderings()
	return { "ascending", "descending", "like-default", "template" }
end

---@param order any
---@return boolean
function M.is_order(order)
	return ORDERINGS[order] == true
end

return M
