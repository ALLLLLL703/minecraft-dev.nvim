local M = {}

local SKIP_DIRECTORIES = { [".git"] = true, [".gradle"] = true, build = true, target = true, node_modules = true }
local SOURCE_EXTENSIONS = { java = "java", kt = "kotlin", kts = "kotlin" }
local DECLARATIONS = { class_declaration = true, interface_declaration = true, object_declaration = true }

local function resolve_root(buffer, explicit_root)
	if explicit_root then
		return vim.fs.normalize(explicit_root)
	end
	local path = vim.api.nvim_buf_get_name(buffer)
	if path ~= "" then
		local root = vim.fs.root(
			path,
			{ ".git", "settings.gradle", "settings.gradle.kts", "build.gradle", "build.gradle.kts", "pom.xml" }
		)
		if root then
			return root
		end
	end
	return vim.fn.getcwd()
end

local function collect_files(directory, files)
	local ok, iterator = pcall(vim.fs.dir, directory)
	if not ok or iterator == nil then
		return
	end
	for name, kind in iterator do
		local child = vim.fs.normalize(directory .. "/" .. name)
		if kind == "directory" and not SKIP_DIRECTORIES[name] and name:sub(1, 1) ~= "." then
			collect_files(child, files)
		elseif kind == "file" then
			local extension = name:match("%.([^.]*)$")
			local language = extension and SOURCE_EXTENSIONS[extension]
			if language then
				table.insert(files, { path = child, language = language })
			end
		end
	end
end

local function collect_loaded(root, files)
	local seen = {}
	for _, file in ipairs(files) do
		seen[file.path] = true
	end
	local prefix = vim.fs.normalize(root) .. "/"
	for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buffer) then
			local path = vim.fs.normalize(vim.api.nvim_buf_get_name(buffer))
			local extension = path:match("%.([^./]*)$")
			local language = extension and SOURCE_EXTENSIONS[extension]
			if language and vim.startswith(path, prefix) and not seen[path] then
				table.insert(files, { path = path, language = language })
				seen[path] = true
			end
		end
	end
end

local function source_buffer(file)
	local existing = vim.fn.bufnr(file.path)
	if existing ~= -1 then
		if not vim.api.nvim_buf_is_loaded(existing) then
			vim.fn.bufload(existing)
		end
		return existing, false
	end
	local handle = io.open(file.path, "r")
	if handle == nil then
		return nil, false, { code = "source_open_failed", detail = file.path }
	end
	local content = handle:read("*a")
	handle:close()
	local buffer = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buffer, file.path)
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.split(content, "\n", { plain = true }))
	vim.bo[buffer].filetype = file.language
	return buffer, true
end

local function package_and_imports(root, buffer)
	local package_name, imports = "", {}
	local function visit(node)
		local kind = node:type()
		local text = vim.treesitter.get_node_text(node, buffer)
		if kind == "package_declaration" or kind == "package_header" then
			package_name = text:match("^%s*package%s+([%w_.$]+)") or ""
		elseif kind == "import_declaration" or kind == "import_header" then
			local imported = text:match("^%s*import%s+([%w_.$]+)")
			if imported and not imported:match("%*$") then
				imports[imported:match("([%w_$]+)$")] = imported
			end
		end
		if not DECLARATIONS[kind] then
			for child in node:iter_children() do
				if child:named() then
					visit(child)
				end
			end
		end
	end
	visit(root)
	return package_name, imports
end

local function declaration_name(node, buffer)
	for child in node:iter_children() do
		if child:named() and (child:type() == "identifier" or child:type() == "type_identifier") then
			return vim.treesitter.get_node_text(child, buffer), child
		end
	end
	return nil
end

local function normalize_parent(value, imports, package_name)
	value = vim.trim(value:gsub("^extends%s+", ""):gsub("^implements%s+", ""))
	value = value:gsub("%b()", ""):gsub("%b<>", "")
	value = vim.trim(value)
	if value == "" then
		return nil
	end
	if value:find("%.") then
		return value
	end
	if imports[value] then
		return imports[value]
	end
	return package_name ~= "" and (package_name .. "." .. value) or value
end

local function declaration_parents(node, buffer, language, imports, package_name)
	local parents = {}
	for child in node:iter_children() do
		if child:named() then
			local kind = child:type()
			local text = vim.treesitter.get_node_text(child, buffer)
			if
				language == "java"
				and (kind == "superclass" or kind == "super_interfaces" or kind == "extends_interfaces")
			then
				text = text:gsub("^%s*extends%s+", ""):gsub("^%s*implements%s+", "")
				for parent in text:gmatch("[^,]+") do
					local normalized = normalize_parent(parent, imports, package_name)
					if normalized then
						table.insert(parents, normalized)
					end
				end
			elseif language == "kotlin" and kind == "delegation_specifier" then
				local normalized = normalize_parent(text, imports, package_name)
				if normalized then
					table.insert(parents, normalized)
				end
			end
		end
	end
	return parents
end

local function forge_mod_ids(node, buffer)
	local text = vim.treesitter.get_node_text(node, buffer)
	local header = text:match("^[^{]*") or text
	local ids = {}
	for arguments in header:gmatch("@[%w_.$]*Mod%s*%((.-)%)") do
		local direct = arguments:match('^%s*"([^"]+)"%s*$') or arguments:match('value%s*=%s*"([^"]+)"')
		if direct then
			table.insert(ids, direct)
		else
			local expression = arguments:match("value%s*=%s*([%w_.$]+)") or vim.trim(arguments):match("^([%w_.$]+)$")
			local constant = expression and expression:match("([%w_$]+)$")
			if constant then
				local escaped = vim.pesc(constant)
				local value = text:match("[%w_<>?,%s]*String%s+" .. escaped .. '%s*=%s*"([^"]+)"')
					or text:match("const%s+val%s+" .. escaped .. '%s*=%s*"([^"]+)"')
				if value then
					table.insert(ids, value)
				end
			end
		end
	end
	return ids
end

local function annotation_names(node, buffer)
	local text = vim.treesitter.get_node_text(node, buffer)
	local header = text:match("^[^{]*") or text
	local names = {}
	for name in header:gmatch("@([%w_.$]+)") do
		names[name] = true
		names[name:match("([%w_$]+)$") or name] = true
	end
	return names
end

local function collect_declarations(node, buffer, file, package_name, imports, output, enclosing)
	local next_enclosing = enclosing
	if DECLARATIONS[node:type()] then
		local name, name_node = declaration_name(node, buffer)
		if name and name_node then
			local nested = vim.list_extend(vim.deepcopy(enclosing), { name })
			local class_name = table.concat(nested, "$")
			local start_row, start_col, end_row, end_col = name_node:range()
			local declaration_lnum, declaration_col, declaration_end_lnum, declaration_end_col = node:range()
			local header = vim.treesitter.get_node_text(node, buffer):match("^[^{]*") or ""
			table.insert(output, {
				name = name,
				fqn = package_name ~= "" and (package_name .. "." .. class_name) or class_name,
				package = package_name,
				path = file.path,
				language = file.language,
				lnum = start_row,
				col = start_col,
				end_lnum = end_row,
				end_col = end_col,
				declaration_lnum = declaration_lnum,
				declaration_col = declaration_col,
				declaration_end_lnum = declaration_end_lnum,
				declaration_end_col = declaration_end_col,
				abstract = header:match("%f[%w]abstract%f[%W]") ~= nil or node:type() == "interface_declaration",
				parents = declaration_parents(node, buffer, file.language, imports, package_name),
				forge_mod_ids = forge_mod_ids(node, buffer),
				annotations = annotation_names(node, buffer),
			})
			next_enclosing = nested
		end
	end
	for child in node:iter_children() do
		if child:named() then
			collect_declarations(child, buffer, file, package_name, imports, output, next_enclosing)
		end
	end
end

local function parse_file(file)
	local buffer, created, open_error = source_buffer(file)
	if buffer == nil then
		return nil, open_error
	end
	local ok, parser = pcall(vim.treesitter.get_parser, buffer, file.language)
	if not ok or parser == nil then
		if created then
			vim.api.nvim_buf_delete(buffer, { force = true })
		end
		return nil, { code = "parser_unavailable", detail = file.language }
	end
	local parsed, trees = pcall(function()
		return parser:parse()
	end)
	if not parsed or trees == nil or trees[1] == nil then
		if created then
			vim.api.nvim_buf_delete(buffer, { force = true })
		end
		return nil, { code = "parser_unavailable", detail = file.language }
	end
	local root = trees[1]:root()
	local package_name, imports = package_and_imports(root, buffer)
	local entries = {}
	collect_declarations(root, buffer, file, package_name, imports, entries, {})
	if created then
		vim.api.nvim_buf_delete(buffer, { force = true })
	end
	return entries
end

---@param options? { buffer?: integer, root?: string, max_files?: integer }
---@return table
function M.list(options)
	options = options or {}
	local buffer = options.buffer or 0
	local root = resolve_root(buffer, options.root)
	---@type MinecraftDevConfig
	local config = require("minecraft-dev").config
	local max_files = options.max_files or config.defaults.metadata.source_scan_max_files
	if type(max_files) ~= "number" or max_files < 1 or max_files % 1 ~= 0 then
		max_files = config.defaults.metadata.source_scan_max_files
	end
	local files = {}
	collect_files(root, files)
	collect_loaded(root, files)
	table.sort(files, function(left, right)
		return left.path < right.path
	end)
	local entries, warnings = {}, {}
	if #files > max_files then
		table.insert(warnings, { code = "source_scan_limit", limit = max_files, total = #files })
	end
	for index = 1, math.min(#files, max_files) do
		local parsed, err = parse_file(files[index])
		if parsed then
			vim.list_extend(entries, parsed)
		else
			table.insert(warnings, vim.tbl_extend("force", { path = files[index].path }, err or {}))
		end
	end
	table.sort(entries, function(left, right)
		if left.fqn ~= right.fqn then
			return left.fqn < right.fqn
		end
		return left.path < right.path
	end)
	return { status = "indexed", root = root, entries = entries, warnings = warnings }
end

local BUKKIT_TYPES = { ["org.bukkit.plugin.Plugin"] = true, ["org.bukkit.plugin.java.JavaPlugin"] = true }

local function bukkit_status(entry, by_fqn, visiting)
	if visiting[entry.fqn] then
		return nil
	end
	visiting[entry.fqn] = true
	local unknown = false
	for _, parent in ipairs(entry.parents) do
		if BUKKIT_TYPES[parent] then
			visiting[entry.fqn] = nil
			return true
		end
		local local_parent = by_fqn[parent]
		if local_parent then
			local status = bukkit_status(local_parent, by_fqn, visiting)
			if status == true then
				visiting[entry.fqn] = nil
				return true
			end
			if status == nil then
				unknown = true
			end
		elseif not parent:match("^java%.") and not parent:match("^kotlin%.") then
			unknown = true
		end
	end
	visiting[entry.fqn] = nil
	if unknown then
		return nil
	end
	return false
end

---@param indexed table
---@param entry table
---@return boolean?
function M.is_bukkit_plugin(indexed, entry)
	local by_fqn = {}
	for _, candidate in ipairs(indexed.entries) do
		by_fqn[candidate.fqn] = candidate
	end
	return bukkit_status(entry, by_fqn, {})
end

local function inheritance_status(entry, by_fqn, targets, visiting)
	if visiting[entry.fqn] then
		return nil
	end
	visiting[entry.fqn] = true
	local unknown = false
	for _, parent in ipairs(entry.parents) do
		if targets[parent] then
			visiting[entry.fqn] = nil
			return true
		end
		local local_parent = by_fqn[parent]
		if local_parent then
			local status = inheritance_status(local_parent, by_fqn, targets, visiting)
			if status == true then
				visiting[entry.fqn] = nil
				return true
			end
			if status == nil then
				unknown = true
			end
		elseif not parent:match("^java%.") and not parent:match("^kotlin%.") then
			unknown = true
		end
	end
	visiting[entry.fqn] = nil
	return unknown and nil or false
end

---@param indexed table
---@param entry table
---@param target string|string[]
---@return boolean?
function M.inherits(indexed, entry, target)
	local targets = {}
	if type(target) == "string" then
		targets[target] = true
	else
		for _, value in ipairs(target) do
			targets[value] = true
		end
	end
	local by_fqn = {}
	for _, candidate in ipairs(indexed.entries) do
		by_fqn[candidate.fqn] = candidate
	end
	return inheritance_status(entry, by_fqn, targets, {})
end

return M
