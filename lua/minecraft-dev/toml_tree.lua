local M = {}

local function location(node)
	local lnum, col, end_lnum, end_col = node:range()
	return { lnum = lnum, col = col, end_lnum = end_lnum, end_col = end_col }
end

local function node_text(node, buffer)
	return vim.treesitter.get_node_text(node, buffer)
end

local function decode_key(text)
	text = vim.trim(text)
	if text:sub(1, 1) == '"' and text:sub(-1) == '"' then
		local ok, decoded = pcall(vim.json.decode, text)
		return ok and decoded or text:sub(2, -2)
	end
	if text:sub(1, 1) == "'" and text:sub(-1) == "'" then
		return text:sub(2, -2)
	end
	return text
end

local function key_segments(node, buffer)
	if node:type() ~= "dotted_key" then
		return { decode_key(node_text(node, buffer)) }
	end
	local segments = {}
	for child in node:iter_children() do
		if child:named() then
			table.insert(segments, decode_key(node_text(child, buffer)))
		end
	end
	return segments
end

local function decode_string(text)
	if text:sub(1, 3) == '"""' and text:sub(-3) == '"""' then
		return text:sub(4, -4)
	end
	if text:sub(1, 3) == "'''" and text:sub(-3) == "'''" then
		return text:sub(4, -4)
	end
	if text:sub(1, 1) == '"' and text:sub(-1) == '"' then
		local ok, decoded = pcall(vim.json.decode, text)
		return ok and decoded or text:sub(2, -2)
	end
	if text:sub(1, 1) == "'" and text:sub(-1) == "'" then
		return text:sub(2, -2)
	end
	return text
end

local function value_node(node, buffer)
	local result = location(node)
	local node_type = node:type()
	result.node_type = node_type
	result.text = node_text(node, buffer)
	if node_type == "string" then
		result.kind = "string"
		result.value = decode_string(result.text)
	elseif node_type == "boolean" then
		result.kind = "boolean"
		result.value = result.text == "true"
	elseif node_type == "integer" or node_type == "float" then
		result.kind = "number"
		result.value = tonumber((result.text:gsub("_", "")))
	elseif node_type == "array" then
		result.kind = "array"
	elseif node_type == "inline_table" then
		result.kind = "table"
	elseif node_type:find("date", 1, true) or node_type:find("time", 1, true) then
		result.kind = "datetime"
	else
		result.kind = node_type
	end
	return result
end

local function mapping()
	return { entries = {}, by_key = {} }
end

local function parse_pair(node, buffer)
	local children = {}
	for child in node:iter_children() do
		if child:named() then
			table.insert(children, child)
		end
	end
	if children[1] == nil then
		return nil
	end
	local segments = key_segments(children[1], buffer)
	local entry = vim.tbl_extend("force", location(node), {
		key = table.concat(segments, "."),
		key_segments = segments,
		key_node = location(children[1]),
		value = children[2] and value_node(children[2], buffer) or nil,
	})
	return entry
end

local function add_entry(target, entry)
	table.insert(target.entries, entry)
	target.by_key[entry.key] = target.by_key[entry.key] or {}
	table.insert(target.by_key[entry.key], entry)
end

local function parse_table(node, buffer)
	local children = {}
	for child in node:iter_children() do
		if child:named() then
			table.insert(children, child)
		end
	end
	if children[1] == nil then
		return nil
	end
	local table_node = vim.tbl_extend("force", location(node), mapping())
	table_node.kind = node:type() == "table_array_element" and "array_table" or "table"
	table_node.path = key_segments(children[1], buffer)
	table_node.header = location(children[1])
	for index = 2, #children do
		if children[index]:type() == "pair" then
			local entry = parse_pair(children[index], buffer)
			if entry then
				add_entry(table_node, entry)
			end
		end
	end
	return table_node
end

---@param options? { buffer?: integer, language?: string }
---@return table
function M.parse_buffer(options)
	options = options or {}
	local buffer = options.buffer or 0
	if not vim.api.nvim_buf_is_loaded(buffer) then
		return { status = "failed", error = { code = "buffer_unloaded" } }
	end
	local language = options.language or "toml"
	local ok, parser = pcall(vim.treesitter.get_parser, buffer, language)
	if not ok or parser == nil then
		return { status = "skipped", error = { code = "parser_unavailable", detail = language } }
	end
	local parsed, trees = pcall(function()
		return parser:parse()
	end)
	if not parsed or trees == nil or trees[1] == nil then
		return { status = "skipped", error = { code = "parser_unavailable", detail = language } }
	end
	local root = trees[1]:root()
	if root:has_error() then
		return { status = "failed", error = { code = "invalid_toml" } }
	end
	local document = { top = mapping(), tables = {} }
	for child in root:iter_children() do
		if child:named() then
			if child:type() == "pair" then
				local entry = parse_pair(child, buffer)
				if entry then
					add_entry(document.top, entry)
				end
			elseif child:type() == "table" or child:type() == "table_array_element" then
				local parsed_table = parse_table(child, buffer)
				if parsed_table then
					table.insert(document.tables, parsed_table)
				end
			end
		end
	end
	return { status = "parsed", buffer = buffer, document = document }
end

return M
