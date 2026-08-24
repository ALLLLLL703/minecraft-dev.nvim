local M = {}

local function location(node)
	local lnum, col, end_lnum, end_col = node:range()
	return { lnum = lnum, col = col, end_lnum = end_lnum, end_col = end_col }
end

local function decode_string(node, buffer)
	local text = vim.treesitter.get_node_text(node, buffer)
	local ok, value = pcall(vim.json.decode, text)
	if ok then
		return value
	end
	if text:sub(1, 1) == "'" and text:sub(-1) == "'" then
		return text:sub(2, -2):gsub("\\'", "'")
	end
	if text:match("^[%a_$][%w_$-]*$") then
		return text
	end
	return nil
end

local parse_value

local function add_entry(object, entry)
	table.insert(object.entries, entry)
	object.by_key[entry.key] = object.by_key[entry.key] or {}
	table.insert(object.by_key[entry.key], entry)
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
	local key = decode_string(children[1], buffer)
	if type(key) ~= "string" then
		return nil
	end
	return vim.tbl_extend("force", location(node), {
		key = key,
		key_node = location(children[1]),
		value = children[2] and parse_value(children[2], buffer) or nil,
	})
end

local function parse_object(node, buffer)
	local object = vim.tbl_extend("force", location(node), { kind = "object", entries = {}, by_key = {} })
	for child in node:iter_children() do
		if child:named() and child:type() == "pair" then
			local entry = parse_pair(child, buffer)
			if entry then
				add_entry(object, entry)
			end
		end
	end
	return object
end

local function parse_array(node, buffer)
	local array = vim.tbl_extend("force", location(node), { kind = "array", items = {} })
	for child in node:iter_children() do
		if child:named() then
			table.insert(array.items, parse_value(child, buffer))
		end
	end
	return array
end

function parse_value(node, buffer)
	local node_type = node:type()
	if node_type == "object" then
		return parse_object(node, buffer)
	end
	if node_type == "array" then
		return parse_array(node, buffer)
	end
	local value = location(node)
	value.node_type = node_type
	if node_type == "string" then
		value.kind = "string"
		value.value = decode_string(node, buffer)
	elseif node_type == "number" then
		value.kind = "number"
		value.value = tonumber(vim.treesitter.get_node_text(node, buffer))
	elseif node_type == "true" or node_type == "false" then
		value.kind = "boolean"
		value.value = node_type == "true"
	elseif node_type == "null" then
		value.kind = "null"
		value.value = vim.NIL
	else
		value.kind = node_type
	end
	return value
end

---@param options? { buffer?: integer, language?: string }
---@return table
function M.parse_buffer(options)
	options = options or {}
	local buffer = options.buffer or 0
	if not vim.api.nvim_buf_is_loaded(buffer) then
		return { status = "failed", error = { code = "buffer_unloaded" } }
	end
	local language = options.language or "json"
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
		return { status = "failed", error = { code = "invalid_json" } }
	end
	local document
	for child in root:iter_children() do
		if child:named() then
			document = parse_value(child, buffer)
			break
		end
	end
	if document == nil then
		return { status = "failed", error = { code = "invalid_json" } }
	end
	return { status = "parsed", buffer = buffer, document = document }
end

return M
