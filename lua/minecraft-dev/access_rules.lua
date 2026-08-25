local jvm_index = require("minecraft-dev.jvm_index")
local jvm_targets = require("minecraft-dev.jvm_targets")

local M = {}
local namespace = vim.api.nvim_create_namespace("minecraft-dev.access-rules")

local AT_ACCESS = { public = true, protected = true, default = true, private = true }
local AW_ACCESS = { accessible = true, extendable = true, mutable = true }
local AW_KINDS = { class = true, field = true, method = true }

local function failure(code, detail)
	return { status = "failed", error = { code = code, detail = detail or "" } }
end

local function diagnostic(code, line, detail)
	local config = require("minecraft-dev").config
	local messages = config.messages.access_rules or {}
	local template = messages[code] or code:gsub("_", " ") .. ": %s"
	return {
		code = code,
		message = string.format(template, detail or ""),
		severity = vim.diagnostic.severity.ERROR,
		lnum = math.max(0, line - 1),
		col = 0,
		end_lnum = math.max(0, line - 1),
		end_col = 1,
		source = "minecraft-dev",
	}
end

local function split(line)
	return vim.split(vim.trim(line), "%s+")
end

local function at_modifier(value)
	local access, final = value:match("^([%a]+)([+-]f)$")
	if not access then
		access = value
	end
	if not AT_ACCESS[access] then
		return nil
	end
	return access, final
end

local function parse_at(content)
	local entries, diagnostics, seen = {}, {}, {}
	for line_number, raw in ipairs(vim.split(content, "\n", { plain = true })) do
		local line = raw:gsub("#.*$", "")
		if vim.trim(line) ~= "" then
			local parts = split(line)
			local access, final = at_modifier(parts[1] or "")
			if not access then
				table.insert(diagnostics, diagnostic("access_modifier_invalid", line_number, parts[1]))
			elseif not parts[2] or #parts > 3 then
				table.insert(diagnostics, diagnostic("access_rule_syntax_invalid", line_number, raw))
			else
				local item = {
					format = "at",
					access = access,
					final = final,
					owner = parts[2]:gsub("/", "."),
					kind = "class",
					lnum = line_number - 1,
					text = raw,
				}
				if parts[3] then
					item.name, item.descriptor = parts[3]:match("^([^%(]+)(%b().+)$")
					if item.name then
						item.kind = "method"
					else
						item.name = parts[3]
						item.kind = "field"
					end
				end
				local key = table.concat({ item.kind, item.owner, item.name or "", item.descriptor or "" }, "\0")
				if seen[key] then
					table.insert(diagnostics, diagnostic("access_rule_duplicate", line_number, item.name or item.owner))
				else
					seen[key] = true
				end
				table.insert(entries, item)
			end
		end
	end
	return entries, diagnostics
end

local function valid_aw_combination(access, kind)
	if access == "mutable" then
		return kind == "field"
	end
	if access == "extendable" then
		return kind == "class" or kind == "method"
	end
	return access == "accessible"
end

local function parse_aw(content)
	local entries, diagnostics, seen = {}, {}, {}
	local lines = vim.split(content, "\n", { plain = true })
	local header = split(lines[1] or "")
	if header[1] ~= "accessWidener" or not header[2] or not header[3] then
		table.insert(diagnostics, diagnostic("access_header_invalid", 1, lines[1]))
	end
	for line_number = 2, #lines do
		local raw = lines[line_number]
		local line = raw:gsub("#.*$", "")
		if vim.trim(line) ~= "" then
			local parts = split(line)
			local access, kind = parts[1], parts[2]
			local expected = kind == "class" and 3 or 5
			if not AW_ACCESS[access] or not AW_KINDS[kind] or #parts ~= expected then
				table.insert(diagnostics, diagnostic("access_rule_syntax_invalid", line_number, raw))
			else
				local item = {
					format = "aw",
					access = access,
					kind = kind,
					owner = parts[3]:gsub("/", "."),
					name = parts[4],
					descriptor = parts[5],
					namespace = header[3],
					lnum = line_number - 1,
					text = raw,
				}
				if not valid_aw_combination(access, kind) then
					table.insert(diagnostics, diagnostic("access_kind_invalid", line_number, access .. " " .. kind))
				end
				local key = table.concat({ kind, item.owner, item.name or "", item.descriptor or "" }, "\0")
				if seen[key] then
					table.insert(diagnostics, diagnostic("access_rule_duplicate", line_number, item.name or item.owner))
				else
					seen[key] = true
				end
				table.insert(entries, item)
			end
		end
	end
	return entries, diagnostics, { version = header[2], namespace = header[3] }
end

local function object_string(body, key)
	return body:match("[\"']?" .. key .. "[\"']?%s*:%s*[\"']([^\"']+)[\"']")
end

local function parse_coremod(content)
	local entries, diagnostics, seen = {}, {}, {}
	for offset, body in content:gmatch("()[\"']?target[\"']?%s*:%s*%{(.-)%}") do
		local line_number = select(2, content:sub(1, offset):gsub("\n", "")) + 1
		local target = object_string(body, "target") or object_string(body, "type")
		local item = { format = "coremod", lnum = line_number - 1, text = body }
		if target == "CLASS" then
			item.kind = "class"
			item.owner = object_string(body, "name")
		elseif target == "FIELD" then
			item.kind = "field"
			item.owner = object_string(body, "class")
			item.name = object_string(body, "fieldName")
		elseif target == "METHOD" then
			item.kind = "method"
			item.owner = object_string(body, "class")
			item.name = object_string(body, "methodName")
			item.descriptor = object_string(body, "methodDesc")
		end
		if
			not item.kind
			or not item.owner
			or (item.kind ~= "class" and not item.name)
			or (item.kind == "method" and not item.descriptor)
		then
			table.insert(diagnostics, diagnostic("coremod_target_invalid", line_number, body))
		else
			item.owner = item.owner:gsub("/", ".")
			local key = table.concat({ item.kind, item.owner, item.name or "", item.descriptor or "" }, "\0")
			if seen[key] then
				table.insert(diagnostics, diagnostic("access_rule_duplicate", line_number, item.name or item.owner))
			else
				seen[key] = true
			end
			table.insert(entries, item)
		end
	end
	if #entries == 0 and #diagnostics == 0 then
		table.insert(diagnostics, diagnostic("coremod_target_missing", 1, ""))
	end
	return entries, diagnostics
end

local function buffer_content(buffer)
	return table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
end

local function format_for(buffer, explicit)
	if explicit then
		return explicit
	end
	local name = vim.fs.basename(vim.api.nvim_buf_get_name(buffer))
	if name:match("%.accesswidener$") then
		return "aw"
	end
	if name == "accesstransformer.cfg" or name:match("_at%.cfg$") then
		return "at"
	end
	if name == "coremods.js" or name:match("%.coremod%.js$") then
		return "coremod"
	end
end

---@param options? { buffer?: integer, format?: "at"|"aw"|"coremod" }
---@return table
function M.inspect(options)
	options = options or {}
	local buffer = options.buffer or 0
	local format = format_for(buffer, options.format)
	if not format then
		return failure("not_access_rule_file")
	end
	local entries, diagnostics, header
	if format == "at" then
		entries, diagnostics = parse_at(buffer_content(buffer))
	elseif format == "aw" then
		entries, diagnostics, header = parse_aw(buffer_content(buffer))
	else
		entries, diagnostics = parse_coremod(buffer_content(buffer))
	end
	return {
		status = "parsed",
		buffer = buffer,
		format = format,
		entries = entries,
		diagnostics = diagnostics,
		header = header,
	}
end

---@param options? { buffer?: integer, format?: "at"|"aw"|"coremod" }
---@return table
function M.diagnose_buffer(options)
	local parsed = M.inspect(options)
	local buffer = (options and options.buffer) or 0
	if parsed.status ~= "parsed" then
		vim.diagnostic.reset(namespace, buffer)
		return parsed
	end
	vim.diagnostic.set(namespace, buffer, parsed.diagnostics)
	return vim.tbl_extend("force", parsed, { status = "diagnosed" })
end

local function source_buffer(path)
	local buffer = vim.fn.bufadd(path)
	vim.fn.bufload(buffer)
	if vim.bo[buffer].filetype == "" then
		vim.bo[buffer].filetype = path:match("%.kt$") and "kotlin" or "java"
	end
	return buffer
end

local function resolve_entry(item, options)
	local indexed = jvm_index.list({ buffer = options.buffer, root = options.root, max_files = options.max_files })
	for _, class in ipairs(indexed.entries) do
		if class.fqn == item.owner then
			local buffer = source_buffer(class.path)
			local source = jvm_targets.inspect({ buffer = buffer })
			if source.status == "indexed" then
				for _, candidate in ipairs(source.classes) do
					if candidate.fqn == item.owner then
						if item.kind == "class" then
							return { class = candidate, buffer = buffer, path = class.path }
						end
						for _, member in ipairs(candidate.members) do
							if
								member.kind == item.kind
								and member.name == item.name
								and (not item.descriptor or item.descriptor == member.descriptor)
							then
								return { class = candidate, member = member, buffer = buffer, path = class.path }
							end
						end
					end
				end
			end
		end
	end
	return nil, indexed
end

---@param options? { buffer?: integer, format?: "at"|"aw"|"coremod", row?: integer, root?: string, open?: boolean, max_files?: integer }
---@return table
function M.goto_target(options)
	options = options or {}
	local parsed = M.inspect(options)
	if parsed.status ~= "parsed" then
		return parsed
	end
	local row = options.row
	if row == nil then
		row = vim.api.nvim_win_get_cursor(0)[1] - 1
	end
	local selected
	for _, item in ipairs(parsed.entries) do
		if item.lnum == row then
			selected = item
			break
		end
	end
	if not selected then
		return failure("access_target_required")
	end
	local resolved, indexed = resolve_entry(selected, vim.tbl_extend("force", options, { buffer = parsed.buffer }))
	if not resolved then
		return failure("access_target_unresolved", selected.owner .. (selected.name and (" " .. selected.name) or ""))
	end
	local target = resolved.member or resolved.class
	if options.open ~= false then
		vim.api.nvim_set_current_buf(resolved.buffer)
		vim.api.nvim_win_set_cursor(0, { target.lnum + 1, target.col })
	end
	return vim.tbl_extend(
		"force",
		{ status = "found", entry = selected, warnings = indexed and indexed.warnings },
		resolved
	)
end

function M.setup()
	local group = vim.api.nvim_create_augroup("MinecraftDevAccessRules", { clear = true })
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "TextChanged", "TextChangedI" }, {
		group = group,
		pattern = { "*.accesswidener", "accesstransformer.cfg", "*_at.cfg", "coremods.js", "*.coremod.js" },
		callback = function(event)
			require("minecraft-dev.access_rules").diagnose_buffer({ buffer = event.buf })
		end,
	})
end

function M.namespace()
	return namespace
end

return M
