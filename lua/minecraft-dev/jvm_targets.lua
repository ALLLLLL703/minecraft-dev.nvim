local M = {}

local CLASS_NODES = {
	class_declaration = true,
	interface_declaration = true,
	enum_declaration = true,
	record_declaration = true,
	annotation_type_declaration = true,
	object_declaration = true,
}

local JAVA_LANG = {
	Boolean = "java/lang/Boolean",
	Byte = "java/lang/Byte",
	Character = "java/lang/Character",
	Class = "java/lang/Class",
	Double = "java/lang/Double",
	Exception = "java/lang/Exception",
	Float = "java/lang/Float",
	Integer = "java/lang/Integer",
	Long = "java/lang/Long",
	Object = "java/lang/Object",
	Short = "java/lang/Short",
	String = "java/lang/String",
	Throwable = "java/lang/Throwable",
	Void = "java/lang/Void",
}

local PRIMITIVES = {
	boolean = "Z",
	byte = "B",
	char = "C",
	double = "D",
	float = "F",
	int = "I",
	long = "J",
	short = "S",
	void = "V",
	Boolean = "Z",
	Byte = "B",
	Char = "C",
	Double = "D",
	Float = "F",
	Int = "I",
	Long = "J",
	Short = "S",
	Unit = "V",
}

local KOTLIN_ARRAYS = {
	BooleanArray = "[Z",
	ByteArray = "[B",
	CharArray = "[C",
	DoubleArray = "[D",
	FloatArray = "[F",
	IntArray = "[I",
	LongArray = "[J",
	ShortArray = "[S",
}

local function failure(code, detail)
	return { status = "failed", error = { code = code, detail = detail or "" } }
end

local function node_text(node, buffer)
	return vim.treesitter.get_node_text(node, buffer)
end

local function first_descendant(node, kinds)
	for child in node:iter_children() do
		if child:named() then
			if kinds[child:type()] then
				return child
			end
			local nested = first_descendant(child, kinds)
			if nested then
				return nested
			end
		end
	end
end

local function field(node, name)
	local values = node:field(name)
	return values and values[1] or nil
end

local function strip_generics(value)
	local result, depth = {}, 0
	for index = 1, #value do
		local char = value:sub(index, index)
		if char == "<" then
			depth = depth + 1
		elseif char == ">" then
			depth = math.max(0, depth - 1)
		elseif depth == 0 then
			table.insert(result, char)
		end
	end
	return table.concat(result)
end

local function descriptor_for(raw, context, allow_void)
	if type(raw) ~= "string" then
		return nil
	end
	local value = vim.trim(raw)
	value = value:gsub("@[%w_.$]+%s*%b()", ""):gsub("@[%w_.$]+", "")
	value = value:gsub("%f[%w]final%f[%W]", ""):gsub("%?", "")
	value = vim.trim(strip_generics(value))
	local dimensions = 0
	if value:match("^Array%s*<") then
		-- Generic text was removed above, so handle Kotlin Array before stripping in callers.
		return nil
	end
	while value:match("%[%]%s*$") do
		dimensions = dimensions + 1
		value = vim.trim(value:gsub("%[%]%s*$", ""))
	end
	if value:match("%.%.%.$") then
		dimensions = dimensions + 1
		value = vim.trim(value:gsub("%.%.%.$", ""))
	end
	local descriptor = PRIMITIVES[value] or KOTLIN_ARRAYS[value]
	if descriptor == "V" and (not allow_void or dimensions > 0) then
		return nil
	end
	if not descriptor then
		local qualified = context.imports[value] or JAVA_LANG[value]
		if not qualified then
			if value:match("^[A-Z]$") then
				return nil
			end
			if value:find("%.") then
				qualified = value
			elseif value:match("^[%a_$][%w_$]*$") then
				qualified = context.package ~= "" and (context.package .. "." .. value) or value
			else
				return nil
			end
		end
		descriptor = "L" .. qualified:gsub("%.", "/") .. ";"
	end
	return string.rep("[", dimensions) .. descriptor
end

local function kotlin_descriptor(raw, context, allow_void)
	local element = raw:match("^%s*Array%s*<(.+)>%s*%??%s*$")
	if element then
		local descriptor = kotlin_descriptor(element, context, false)
		return descriptor and ("[" .. descriptor) or nil
	end
	return descriptor_for(raw, context, allow_void)
end

local function split_parameters(value)
	local result, start, angle, paren = {}, 1, 0, 0
	for index = 1, #value do
		local char = value:sub(index, index)
		if char == "<" then
			angle = angle + 1
		elseif char == ">" then
			angle = math.max(0, angle - 1)
		elseif char == "(" then
			paren = paren + 1
		elseif char == ")" then
			paren = math.max(0, paren - 1)
		elseif char == "," and angle == 0 and paren == 0 then
			table.insert(result, vim.trim(value:sub(start, index - 1)))
			start = index + 1
		end
	end
	local tail = vim.trim(value:sub(start))
	if tail ~= "" then
		table.insert(result, tail)
	end
	return result
end

local function method_descriptor(node, buffer, language, context)
	local parameters = field(node, "parameters")
		or first_descendant(
			node,
			{ formal_parameters = true, function_value_parameters = true, primary_constructor = true }
		)
	local parameter_text = parameters and node_text(parameters, buffer):match("^%s*%((.*)%)%s*$") or ""
	local descriptors, parameter_sources = {}, {}
	for _, parameter in ipairs(split_parameters(parameter_text or "")) do
		local source_type
		if language == "java" then
			parameter = parameter:gsub("@[%w_.$]+%s*%b()", ""):gsub("@[%w_.$]+", "")
			parameter = vim.trim(parameter:gsub("%f[%w]final%f[%W]", ""))
			source_type = parameter:match("^(.-)%s+[%w_$]+%s*$")
		else
			source_type = parameter:match("^[%w_$]+%s*:%s*(.-)%s*=") or parameter:match("^[%w_$]+%s*:%s*(.+)$")
		end
		local descriptor = language == "kotlin" and kotlin_descriptor(source_type, context, false)
			or descriptor_for(source_type, context, false)
		if not descriptor then
			return nil
		end
		table.insert(descriptors, descriptor)
		table.insert(parameter_sources, parameter)
	end
	local kind = node:type()
	local return_type
	local return_source_type
	if kind == "constructor_declaration" or kind == "secondary_constructor" then
		return_type = "V"
		return_source_type = "void"
	else
		local type_node = field(node, "type")
		if not type_node and language == "kotlin" and parameters then
			for sibling in node:iter_children() do
				if sibling:named() and sibling:start() >= parameters:end_() and sibling:type() == "user_type" then
					type_node = sibling
					break
				end
			end
		end
		return_source_type = type_node and node_text(type_node, buffer) or (language == "kotlin" and "Unit" or nil)
		return_type = language == "kotlin" and kotlin_descriptor(return_source_type, context, true)
			or descriptor_for(return_source_type, context, true)
	end
	if not return_type then
		return nil
	end
	return "(" .. table.concat(descriptors) .. ")" .. return_type, parameter_sources, return_source_type
end

local function modifiers(header)
	local result = {}
	for _, name in ipairs({ "public", "protected", "private", "static", "final", "abstract", "native", "synchronized" }) do
		if header:match("%f[%w]" .. name .. "%f[%W]") then
			result[name] = true
		end
	end
	return result
end

local function class_name(node, buffer)
	local name = field(node, "name") or first_descendant(node, { identifier = true, type_identifier = true })
	return name and node_text(name, buffer), name
end

local function collect_member(node, buffer, language, context, owner)
	local kind = node:type()
	local text = node_text(node, buffer)
	local header = text:match("^[^{;]*") or text
	local start_row, start_col, end_row, end_col = node:range()
	if kind == "field_declaration" then
		local type_node = field(node, "type")
		local source_type = type_node and node_text(type_node, buffer)
		local descriptor = descriptor_for(source_type, context, false)
		local result = {}
		for child in node:iter_children() do
			if child:named() and child:type() == "variable_declarator" then
				local name_node = field(child, "name") or first_descendant(child, { identifier = true })
				local name = name_node and node_text(name_node, buffer)
				if name then
					table.insert(result, {
						kind = "field",
						name = name,
						descriptor = descriptor,
						source_type = source_type,
						owner = owner,
						modifiers = modifiers(header),
						lnum = start_row,
						col = start_col,
						end_lnum = end_row,
						end_col = end_col,
						text = text,
					})
				end
			end
		end
		return result
	elseif kind == "property_declaration" then
		local declaration = first_descendant(node, { variable_declaration = true })
		local name_node = declaration and first_descendant(declaration, { simple_identifier = true })
		local type_node = declaration and first_descendant(declaration, { user_type = true, nullable_type = true })
		local name = name_node and node_text(name_node, buffer)
		local source_type = type_node and node_text(type_node, buffer)
		return name
				and {
					{
						kind = "field",
						name = name,
						descriptor = kotlin_descriptor(source_type, context, false),
						source_type = source_type,
						owner = owner,
						modifiers = modifiers(header),
						lnum = start_row,
						col = start_col,
						end_lnum = end_row,
						end_col = end_col,
						text = text,
					},
				}
			or {}
	elseif kind == "method_declaration" or kind == "constructor_declaration" or kind == "function_declaration" then
		local name_node = field(node, "name") or first_descendant(node, { identifier = true, simple_identifier = true })
		local name = name_node and node_text(name_node, buffer)
		if kind == "constructor_declaration" then
			name = "<init>"
		end
		local descriptor, parameters, return_source_type = method_descriptor(node, buffer, language, context)
		local throws = header:match("%f[%w]throws%f[%W]%s+(.+)$")
		return name
				and {
					{
						kind = "method",
						name = name,
						descriptor = descriptor,
						parameters = parameters,
						return_source_type = return_source_type,
						throws = throws,
						owner = owner,
						modifiers = modifiers(header),
						lnum = start_row,
						col = start_col,
						end_lnum = end_row,
						end_col = end_col,
						text = text,
					},
				}
			or {}
	end
	return {}
end

local function collect_classes(node, buffer, language, context, enclosing, output)
	if not CLASS_NODES[node:type()] then
		for child in node:iter_children() do
			if child:named() then
				collect_classes(child, buffer, language, context, enclosing, output)
			end
		end
		return
	end
	local name = class_name(node, buffer)
	if not name then
		return
	end
	local nested = vim.list_extend(vim.deepcopy(enclosing), { name })
	local fqn = (context.package ~= "" and (context.package .. ".") or "") .. table.concat(nested, "$")
	local start_row, start_col, end_row, end_col = node:range()
	local class = {
		kind = "class",
		name = name,
		fqn = fqn,
		owner = fqn:gsub("%.", "/"),
		lnum = start_row,
		col = start_col,
		end_lnum = end_row,
		end_col = end_col,
		members = {},
		language = language,
		declaration_type = node:type(),
		header = node_text(node, buffer):match("^[^{]*") or "",
	}
	table.insert(output, class)
	local body = field(node, "body") or first_descendant(node, { class_body = true, enum_class_body = true })
	if body then
		for child in body:iter_children() do
			if child:named() then
				if CLASS_NODES[child:type()] then
					collect_classes(child, buffer, language, context, nested, output)
				else
					vim.list_extend(class.members, collect_member(child, buffer, language, context, class))
				end
			end
		end
	end
end

local function context_for(root, buffer)
	local package_name, imports = "", {}
	local function visit(node)
		if node:type() == "package_declaration" or node:type() == "package_header" then
			package_name = node_text(node, buffer):match("package%s+([%w_.$]+)") or ""
		elseif node:type() == "import_declaration" or node:type() == "import_header" then
			local imported = node_text(node, buffer):match("import%s+([%w_.$]+)")
			if imported and not imported:match("%*$") then
				imports[imported:match("([%w_$]+)$")] = imported
			end
		end
		if not CLASS_NODES[node:type()] then
			for child in node:iter_children() do
				if child:named() then
					visit(child)
				end
			end
		end
	end
	visit(root)
	return { package = package_name, imports = imports }
end

---@param options? { buffer?: integer }
---@return table
function M.inspect(options)
	options = options or {}
	local buffer = options.buffer or 0
	local language = vim.bo[buffer].filetype
	if language ~= "java" and language ~= "kotlin" then
		return failure("jvm_source_required", language)
	end
	local ok, parser = pcall(vim.treesitter.get_parser, buffer, language)
	if not ok or not parser then
		return failure("parser_unavailable", language)
	end
	local parsed, trees = pcall(function()
		return parser:parse()
	end)
	local tree = parsed and trees and trees[1] or nil
	if not tree then
		return failure("parser_unavailable", language)
	end
	local root = tree:root()
	local context = context_for(root, buffer)
	local classes = {}
	collect_classes(root, buffer, language, context, {}, classes)
	return { status = "indexed", buffer = buffer, classes = classes, context = context }
end

---@param options? { buffer?: integer, member?: string, row?: integer, col?: integer }
---@return table
function M.find(options)
	options = options or {}
	local indexed = M.inspect(options)
	if indexed.status ~= "indexed" then
		return indexed
	end
	local row = options.row
	local selected_class
	for _, class in ipairs(indexed.classes) do
		if row == nil or (row >= class.lnum and row <= class.end_lnum) then
			selected_class = class
			for _, item in ipairs(class.members) do
				if
					(options.member and item.name == options.member)
					or (not options.member and row and row >= item.lnum and row <= item.end_lnum)
				then
					if not item.descriptor then
						return failure("descriptor_unresolved", item.name)
					end
					return { status = "found", class = class, member = item }
				end
			end
		end
	end
	if options.member then
		return failure("member_unresolved", options.member)
	end
	return selected_class and { status = "found", class = selected_class } or failure("class_unresolved")
end

---@param options { buffer?: integer, member?: string, row?: integer, format: "at"|"aw"|"coremod"|"mixin", access?: string, clipboard?: boolean }
---@return table
function M.copy(options)
	options = options or {}
	local found = M.find(options)
	if found.status ~= "found" then
		return found
	end
	local class, item = found.class, found.member
	local text
	if options.format == "at" then
		text = class.fqn .. (item and (" " .. item.name .. item.descriptor) or "")
	elseif options.format == "aw" then
		local access = options.access or "accessible"
		text = access .. " " .. (item and item.kind or "class") .. " " .. class.owner
		if item then
			text = text .. " " .. item.name .. " " .. item.descriptor
		end
	elseif options.format == "coremod" then
		local target
		if not item then
			target = { target = "CLASS", name = class.fqn }
		elseif item.kind == "field" then
			target = { target = "FIELD", class = class.fqn, fieldName = item.name }
		else
			target = { target = "METHOD", class = class.fqn, methodName = item.name, methodDesc = item.descriptor }
		end
		text = vim.json.encode(target)
	elseif options.format == "mixin" then
		if not item then
			text = "L" .. class.owner .. ";"
		elseif item.kind == "field" then
			text = "L" .. class.owner .. ";" .. item.name .. ":" .. item.descriptor
		else
			text = "L" .. class.owner .. ";" .. item.name .. item.descriptor
		end
	else
		return failure("target_format_invalid", tostring(options.format))
	end
	if options.clipboard ~= false then
		vim.fn.setreg('"', text)
		pcall(vim.fn.setreg, "+", text)
	end
	return { status = "copied", text = text, class = class, member = item }
end

return M
