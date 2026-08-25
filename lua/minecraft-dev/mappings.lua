local M = {}

local function failure(code, detail)
	return { status = "failed", error = { code = code, detail = detail or "" } }
end

local function member(value, descriptor)
	local owner, name = value:match("^(.*)/([^/]+)$")
	if not owner then
		return nil
	end
	return owner:gsub("/", "."), name, descriptor
end

local function entry(
	kind,
	source_owner,
	source_name,
	source_descriptor,
	target_owner,
	target_name,
	target_descriptor,
	line
)
	return {
		kind = kind,
		source_owner = source_owner,
		source_name = source_name,
		source_descriptor = source_descriptor,
		target_owner = target_owner,
		target_name = target_name,
		target_descriptor = target_descriptor,
		lnum = line - 1,
	}
end

local function parse_srg(content)
	local entries, diagnostics = {}, {}
	for line_number, line in ipairs(vim.split(content, "\n", { plain = true })) do
		local parts = vim.split(vim.trim(line), "%s+")
		if parts[1] == "CL:" and #parts == 3 then
			table.insert(
				entries,
				entry("class", nil, parts[2]:gsub("/", "."), nil, nil, parts[3]:gsub("/", "."), nil, line_number)
			)
		elseif parts[1] == "FD:" and #parts == 3 then
			local source_owner, source_name = member(parts[2])
			local target_owner, target_name = member(parts[3])
			if source_owner and target_owner then
				table.insert(
					entries,
					entry("field", source_owner, source_name, nil, target_owner, target_name, nil, line_number)
				)
			end
		elseif parts[1] == "MD:" and #parts == 5 then
			local source_owner, source_name = member(parts[2], parts[3])
			local target_owner, target_name = member(parts[4], parts[5])
			if source_owner and target_owner then
				table.insert(
					entries,
					entry(
						"method",
						source_owner,
						source_name,
						parts[3],
						target_owner,
						target_name,
						parts[5],
						line_number
					)
				)
			end
		elseif parts[1] and parts[1] ~= "" and not parts[1]:match("^#") then
			table.insert(diagnostics, { code = "mapping_syntax_invalid", lnum = line_number - 1, col = 0 })
		end
	end
	return entries, diagnostics
end

local function parse_tsrg(content)
	local entries, diagnostics = {}, {}
	local source_class, target_class
	for line_number, raw in ipairs(vim.split(content, "\n", { plain = true })) do
		local line = raw:gsub("#.*$", "")
		if vim.trim(line) ~= "" then
			local indent = line:match("^(%s*)") or ""
			local parts = vim.split(vim.trim(line), "%s+")
			if line_number == 1 and parts[1] == "tsrg2" then
				-- Namespace names are descriptive only; lookup stays bidirectional.
			elseif indent == "" and #parts >= 2 then
				source_class, target_class = parts[1]:gsub("/", "."), parts[#parts]:gsub("/", ".")
				table.insert(entries, entry("class", nil, source_class, nil, nil, target_class, nil, line_number))
			elseif source_class and #parts == 2 then
				table.insert(
					entries,
					entry("field", source_class, parts[1], nil, target_class, parts[2], nil, line_number)
				)
			elseif source_class and #parts >= 3 and parts[2]:match("^%(") then
				table.insert(
					entries,
					entry(
						"method",
						source_class,
						parts[1],
						parts[2],
						target_class,
						parts[#parts],
						parts[2],
						line_number
					)
				)
			elseif indent:find("\t\t", 1, true) ~= 1 then
				table.insert(diagnostics, { code = "mapping_syntax_invalid", lnum = line_number - 1, col = 0 })
			end
		end
	end
	return entries, diagnostics
end

local function parse_tiny(content)
	local lines = vim.split(content, "\n", { plain = true })
	local header = vim.split(lines[1] or "", "\t", { plain = true })
	if header[1] ~= "tiny" or header[2] ~= "2" or #header < 6 then
		return {}, { { code = "mapping_header_invalid", lnum = 0, col = 0 } }
	end
	local entries, diagnostics = {}, {}
	local source_class, target_class
	for line_number = 2, #lines do
		local parts = vim.split(lines[line_number], "\t", { plain = true })
		if parts[1] == "c" and #parts >= 4 then
			source_class, target_class = parts[2]:gsub("/", "."), parts[#parts]:gsub("/", ".")
			table.insert(entries, entry("class", nil, source_class, nil, nil, target_class, nil, line_number))
		elseif parts[1] == "" and source_class and (parts[2] == "f" or parts[2] == "m") and #parts >= 5 then
			local kind = parts[2] == "f" and "field" or "method"
			local descriptor = kind == "method" and parts[3] or nil
			table.insert(
				entries,
				entry(kind, source_class, parts[4], descriptor, target_class, parts[#parts], descriptor, line_number)
			)
		elseif vim.trim(lines[line_number]) ~= "" and parts[1] ~= "" then
			table.insert(diagnostics, { code = "mapping_syntax_invalid", lnum = line_number - 1, col = 0 })
		end
	end
	return entries, diagnostics
end

local function format_for(options)
	if options.format then
		return options.format
	end
	local path = options.path or ""
	if path:match("%.tsrg$") then
		return "tsrg"
	end
	if path:match("%.tiny$") then
		return "tiny"
	end
	local first = (options.content or ""):match("([^\r\n]+)") or ""
	if first:match("^tiny\t2\t") then
		return "tiny"
	end
	if not first:match("^[A-Z][A-Z]:") then
		return "tsrg"
	end
	return "srg"
end

local function read(path)
	local handle = io.open(path, "r")
	if not handle then
		return nil
	end
	local content = handle:read("*a")
	handle:close()
	return content
end

---@param options { content?: string, path?: string, format?: "srg"|"tsrg"|"tiny" }
---@return table
function M.inspect(options)
	options = options or {}
	local content = options.content or (options.path and read(options.path))
	if type(content) ~= "string" then
		return failure("mapping_unavailable", tostring(options.path or ""))
	end
	local format = format_for(vim.tbl_extend("force", options, { content = content }))
	local parsers = { srg = parse_srg, tsrg = parse_tsrg, tiny = parse_tiny }
	if not parsers[format] then
		return failure("mapping_format_invalid", tostring(format))
	end
	local entries, diagnostics = parsers[format](content)
	return { status = "indexed", entries = entries, diagnostics = diagnostics, format = format, path = options.path }
end

local function matches(entry_value, query)
	if type(entry_value) ~= "string" then
		return false
	end
	return entry_value == query or entry_value:match("([^./$]+)$") == query
end

---@param options { query?: string, content?: string, path?: string, paths?: string[], format?: string }
---@return table
function M.lookup(options)
	options = options or {}
	local query = type(options.query) == "string" and vim.trim(options.query) or ""
	if query == "" then
		return failure("mapping_query_required")
	end
	local sources = {}
	if options.content then
		table.insert(sources, { content = options.content, path = options.path, format = options.format })
	else
		local paths = options.paths
		if paths == nil then
			---@diagnostic disable-next-line: undefined-field
			local config = require("minecraft-dev").config.defaults.mappings or {}
			paths = config.paths or {}
		end
		for _, path in ipairs(paths) do
			table.insert(sources, { path = path })
		end
	end
	if #sources == 0 then
		return failure("mapping_unavailable")
	end
	local found, diagnostics = {}, {}
	for _, source in ipairs(sources) do
		local indexed = M.inspect(source)
		if indexed.status == "indexed" then
			vim.list_extend(diagnostics, indexed.diagnostics)
			for _, item in ipairs(indexed.entries) do
				if
					matches(item.source_name, query)
					or matches(item.target_name, query)
					or matches(item.source_owner, query)
					or matches(item.target_owner, query)
				then
					table.insert(found, vim.tbl_extend("force", item, { path = source.path }))
				end
			end
		else
			table.insert(diagnostics, indexed.error)
		end
	end
	table.sort(found, function(left, right)
		if left.kind ~= right.kind then
			return left.kind < right.kind
		end
		return (left.source_name or "") < (right.source_name or "")
	end)
	return { status = "found", matches = found, diagnostics = diagnostics }
end

return M
