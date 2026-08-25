local jvm_index = require("minecraft-dev.jvm_index")
local jvm_targets = require("minecraft-dev.jvm_targets")

local M = {}

local GENERATION_KINDS = {
	accessor_getter = true,
	accessor_setter = true,
	invoker = true,
	shadow = true,
	overwrite = true,
	soft_implements = true,
}

local function failure(code, detail)
	return { status = "failed", error = { code = code, detail = detail or "" } }
end

local function source_buffer(path, language)
	local buffer = vim.fn.bufadd(path)
	vim.fn.bufload(buffer)
	if vim.bo[buffer].filetype == "" then
		vim.bo[buffer].filetype = language
	end
	return buffer
end

local function target_name(options)
	if type(options.target) == "string" and vim.trim(options.target) ~= "" then
		return vim.trim(options.target)
	end
	local found = jvm_targets.find({ buffer = options.buffer or 0, row = options.row })
	return found.status == "found" and found.class.fqn or nil
end

---@param options? { buffer?: integer, target?: string, root?: string, row?: integer, open?: boolean, max_files?: integer }
---@return table
function M.find_mixins(options)
	options = options or {}
	local target = target_name(options)
	if not target then
		return failure("mixin_target_required")
	end
	local indexed = jvm_index.list({ buffer = options.buffer or 0, root = options.root, max_files = options.max_files })
	local matches = {}
	for _, class in ipairs(indexed.entries) do
		for _, candidate in ipairs(class.mixin_targets or {}) do
			if candidate == target then
				table.insert(matches, class)
				break
			end
		end
	end
	if options.open ~= false and #matches == 1 then
		local match = matches[1]
		local buffer = source_buffer(match.path, match.language)
		vim.api.nvim_set_current_buf(buffer)
		vim.api.nvim_win_set_cursor(0, { match.lnum + 1, match.col })
	elseif options.open ~= false and #matches > 1 then
		local config = require("minecraft-dev").config
		local items = vim.tbl_map(function(match)
			return { filename = match.path, lnum = match.lnum + 1, col = match.col + 1, text = match.fqn }
		end, matches)
		vim.fn.setqflist({}, " ", { title = string.format(config.prompts.mixin.find_title, target), items = items })
		vim.cmd("copen")
	end
	return { status = "found", target = target, matches = matches, warnings = indexed.warnings, root = indexed.root }
end

local function capitalize(value)
	return value:sub(1, 1):upper() .. value:sub(2)
end

local function access(member, default)
	if member.modifiers.public then
		return "public"
	end
	if member.modifiers.protected then
		return "protected"
	end
	if member.modifiers.private then
		return "private"
	end
	return default or "public"
end

local function static(member)
	return member.modifiers.static and " static" or ""
end

local function body(exception)
	return string.format('{ throw new %s("Generated Mixin fallback"); }', exception or "java.lang.AssertionError")
end

local function parameters(member)
	return table.concat(member.parameters or {}, ", ")
end

local function method_return(member)
	return member.return_source_type or "void"
end

local function generated_signature(kind, class, member, prefix)
	if kind == "accessor_getter" then
		return "get" .. capitalize(member.name), "()" .. member.descriptor
	elseif kind == "accessor_setter" then
		return "set" .. capitalize(member.name), "(" .. member.descriptor .. ")V"
	elseif kind == "invoker" then
		if member.name == "<init>" then
			local params = member.descriptor:match("^(%b())")
			return "create" .. class.name, params .. "L" .. class.owner .. ";"
		end
		return "call" .. capitalize(member.name), member.descriptor
	elseif kind == "soft_implements" then
		return prefix .. member.name, member.descriptor
	end
	return member.name, member.descriptor
end

local function generated_lines(kind, class, member, prefix, indent)
	local annotation, declaration
	if kind == "accessor_getter" then
		annotation = "@org.spongepowered.asm.mixin.gen.Accessor"
		declaration =
			string.format("public%s %s get%s() %s", static(member), member.source_type, capitalize(member.name), body())
	elseif kind == "accessor_setter" then
		annotation = "@org.spongepowered.asm.mixin.gen.Accessor"
		local mutable = member.modifiers.final and "\n@org.spongepowered.asm.mixin.Mutable" or ""
		annotation = annotation .. mutable
		declaration = string.format(
			"public%s void set%s(%s %s) %s",
			static(member),
			capitalize(member.name),
			member.source_type,
			member.name,
			body()
		)
	elseif kind == "invoker" then
		local constructor = member.name == "<init>"
		annotation = constructor and '@org.spongepowered.asm.mixin.gen.Invoker("<init>")'
			or "@org.spongepowered.asm.mixin.gen.Invoker"
		declaration = string.format(
			"public%s %s %s(%s)%s %s",
			static(member),
			constructor and class.name or method_return(member),
			constructor and ("create" .. class.name) or ("call" .. capitalize(member.name)),
			parameters(member),
			member.throws and (" throws " .. member.throws) or "",
			body()
		)
	elseif kind == "shadow" and member.kind == "field" then
		annotation = "@org.spongepowered.asm.mixin.Shadow"
		if member.modifiers.final then
			annotation = annotation .. "\n@org.spongepowered.asm.mixin.Final"
		end
		declaration =
			string.format("%s%s %s %s;", access(member, "private"), static(member), member.source_type, member.name)
	elseif kind == "shadow" then
		annotation = "@org.spongepowered.asm.mixin.Shadow"
		declaration = string.format(
			"%s%s %s %s(%s)%s %s",
			access(member, "protected"),
			static(member),
			method_return(member),
			member.name,
			parameters(member),
			member.throws and (" throws " .. member.throws) or "",
			body("java.lang.UnsupportedOperationException")
		)
	elseif kind == "overwrite" then
		annotation = "@org.spongepowered.asm.mixin.Overwrite"
		declaration = string.format(
			"%s%s %s %s(%s)%s %s",
			access(member),
			static(member),
			method_return(member),
			member.name,
			parameters(member),
			member.throws and (" throws " .. member.throws) or "",
			body("java.lang.UnsupportedOperationException")
		)
	else
		declaration = string.format(
			"public%s %s %s%s(%s)%s %s",
			static(member),
			method_return(member),
			prefix,
			member.name,
			parameters(member),
			member.throws and (" throws " .. member.throws) or "",
			body("java.lang.UnsupportedOperationException")
		)
	end
	local lines = { "" }
	for _, line in ipairs(vim.split(annotation or "", "\n", { plain = true })) do
		table.insert(lines, indent .. line)
	end
	table.insert(lines, indent .. declaration)
	return lines
end

local function mixin_class(buffer)
	local indexed = jvm_targets.inspect({ buffer = buffer })
	if indexed.status ~= "indexed" then
		return nil, indexed
	end
	if vim.bo[buffer].filetype ~= "java" then
		return nil, failure("mixin_generation_java_only", vim.bo[buffer].filetype)
	end
	for _, class in ipairs(indexed.classes) do
		if class.header:match("@[%w_.$]*Mixin%f[%W]") then
			return class, indexed
		end
	end
	return nil, failure("not_mixin_source")
end

local function select_target_buffer(options)
	if options.target_buffer then
		return options.target_buffer
	end
	local found = M.find_mixins({ buffer = options.source_buffer, open = false, root = options.root })
	if found.status ~= "found" or #found.matches == 0 then
		return nil, failure("mixin_source_unresolved")
	end
	if #found.matches ~= 1 then
		return nil, failure("mixin_source_ambiguous", tostring(#found.matches))
	end
	local match = found.matches[1]
	return source_buffer(match.path, match.language)
end

---@param options { source_buffer?: integer, target_buffer?: integer, root?: string, kind: "accessor_getter"|"accessor_setter"|"invoker"|"shadow"|"overwrite"|"soft_implements", member: string, prefix?: string }
---@return table
function M.generate(options)
	options = options or {}
	if not GENERATION_KINDS[options.kind] then
		return failure("mixin_generation_kind_invalid", tostring(options.kind))
	end
	if type(options.member) ~= "string" or vim.trim(options.member) == "" then
		return failure("mixin_generation_member_required")
	end
	local source_buffer_id = options.source_buffer or 0
	local found = jvm_targets.find({ buffer = source_buffer_id, member = options.member })
	if found.status ~= "found" then
		return found
	end
	local member = found.member
	if (options.kind == "accessor_getter" or options.kind == "accessor_setter") and member.kind ~= "field" then
		return failure("mixin_generation_member_kind", member.kind)
	end
	if
		(options.kind == "invoker" or options.kind == "overwrite" or options.kind == "soft_implements")
		and member.kind ~= "method"
	then
		return failure("mixin_generation_member_kind", member.kind)
	end
	if options.kind == "overwrite" and member.name == "<init>" then
		return failure("mixin_generation_member_kind", "constructor")
	end
	local prefix = options.prefix or ""
	if options.kind == "soft_implements" and not prefix:match("^[%a_$][%w_$]*$") then
		return failure("mixin_prefix_invalid", prefix)
	end
	local target_buffer, target_error =
		select_target_buffer(vim.tbl_extend("force", options, { source_buffer = source_buffer_id }))
	if not target_buffer then
		return target_error or failure("mixin_source_unresolved")
	end
	local target_class, target_indexed = mixin_class(target_buffer)
	if not target_class then
		return target_indexed
	end
	if not vim.bo[target_buffer].modifiable or vim.bo[target_buffer].readonly then
		return failure("mixin_buffer_readonly")
	end
	if options.kind == "soft_implements" then
		local escaped = vim.pesc(prefix)
		if
			not target_class.header:match("@[%w_.$]*Implements")
			or not target_class.header:match('prefix%s*=%s*"' .. escaped .. '"')
		then
			return failure("soft_implements_required", prefix)
		end
	end
	local generated_name, generated_descriptor = generated_signature(options.kind, found.class, member, prefix)
	for _, existing in ipairs(target_class.members) do
		if existing.name == generated_name and existing.descriptor == generated_descriptor then
			return failure("mixin_member_duplicate", generated_name .. generated_descriptor)
		end
	end
	local config = require("minecraft-dev").config
	local indent = config.defaults.mixin.indent
	local lines = generated_lines(options.kind, found.class, member, prefix, indent)
	vim.api.nvim_buf_set_lines(target_buffer, target_class.end_lnum, target_class.end_lnum, false, lines)
	return {
		status = "generated",
		buffer = target_buffer,
		kind = options.kind,
		name = generated_name,
		descriptor = generated_descriptor,
		line = target_class.end_lnum,
	}
end

return M
