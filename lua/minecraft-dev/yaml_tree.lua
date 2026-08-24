local M = {}

local TRANSPARENT = {
	stream = true,
	document = true,
	block_node = true,
	flow_node = true,
	block_sequence_item = true,
}

local function named_children(node)
	local children = {}
	for child in node:iter_children() do
		if child:named() then
			table.insert(children, child)
		end
	end
	return children
end

local function location(node)
	local lnum, col, end_lnum, end_col = node:range()
	return { lnum = lnum, col = col, end_lnum = end_lnum, end_col = end_col }
end

local function decode_scalar(raw)
	local trimmed = vim.trim(raw)
	if trimmed:sub(1, 1) == '"' and trimmed:sub(-1) == '"' then
		local ok, value = pcall(vim.json.decode, trimmed)
		return ok and value or nil
	end
	if trimmed:sub(1, 1) == "'" and trimmed:sub(-1) == "'" then
		return trimmed:sub(2, -2):gsub("''", "'")
	end
	if trimmed == "true" or trimmed == "True" or trimmed == "TRUE" then
		return true
	end
	if trimmed == "false" or trimmed == "False" or trimmed == "FALSE" then
		return false
	end
	return vim.trim((trimmed:gsub("%s+#.*$", "")))
end

local parse_node

local function parse_mapping(node, buffer)
	local result = vim.tbl_extend("force", location(node), { kind = "mapping", entries = {}, by_key = {} })
	for _, pair in ipairs(named_children(node)) do
		if pair:type() == "block_mapping_pair" or pair:type() == "flow_pair" then
			local pair_children = named_children(pair)
			local key_node, value_node = pair_children[1], pair_children[2]
			local key = key_node and decode_scalar(vim.treesitter.get_node_text(key_node, buffer)) or nil
			local value = value_node and parse_node(value_node, buffer) or nil
			local entry = vim.tbl_extend("force", location(pair), {
				key = type(key) == "string" and key or nil,
				key_node = key_node and vim.tbl_extend(
					"force",
					location(key_node),
					{ kind = "scalar", value = key, raw = vim.treesitter.get_node_text(key_node, buffer) }
				) or nil,
				value = value,
			})
			table.insert(result.entries, entry)
			if entry.key then
				result.by_key[entry.key] = result.by_key[entry.key] or {}
				table.insert(result.by_key[entry.key], entry)
			end
		end
	end
	return result
end

local function parse_sequence(node, buffer)
	local result = vim.tbl_extend("force", location(node), { kind = "sequence", items = {} })
	for _, child in ipairs(named_children(node)) do
		local parsed = parse_node(child, buffer)
		if parsed then
			table.insert(result.items, parsed)
		end
	end
	return result
end

parse_node = function(node, buffer)
	local kind = node:type()
	local children = named_children(node)
	if TRANSPARENT[kind] and #children == 1 then
		return parse_node(children[1], buffer)
	end
	if kind == "block_mapping" or kind == "flow_mapping" then
		return parse_mapping(node, buffer)
	end
	if kind == "block_sequence" or kind == "flow_sequence" then
		return parse_sequence(node, buffer)
	end
	local raw = vim.treesitter.get_node_text(node, buffer)
	return vim.tbl_extend("force", location(node), { kind = "scalar", value = decode_scalar(raw), raw = raw })
end

---@param options? { buffer?: integer, language?: string }
---@return table
function M.parse_buffer(options)
	options = options or {}
	local buffer = options.buffer or 0
	if not vim.api.nvim_buf_is_loaded(buffer) then
		return { status = "failed", error = { code = "buffer_unloaded" } }
	end
	local language = options.language or "yaml"
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
		return { status = "failed", error = { code = "invalid_yaml" } }
	end
	return { status = "parsed", buffer = buffer, document = parse_node(root, buffer) }
end

return M
