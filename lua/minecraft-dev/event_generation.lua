local M = {}

local CLASS_NODES = {
	class_declaration = true,
	enum_declaration = true,
	record_declaration = true,
	object_declaration = true,
}

local PRIORITIES = {
	LOWEST = true,
	LOW = true,
	NORMAL = true,
	HIGH = true,
	HIGHEST = true,
	MONITOR = true,
}
local VELOCITY_ORDERS = {
	FIRST = true,
	EARLY = true,
	NORMAL = true,
	LATE = true,
	LAST = true,
}
local SPONGE_ORDERS = {
	FIRST = true,
	EARLY = true,
	DEFAULT = true,
	LATE = true,
	LAST = true,
}
local FORGE_KINDS = { fml = true, eventbus = true }

local function failure(code, detail)
	return { status = "failed", error = { code = code, detail = detail or "" } }
end

local function identifier(value)
	return type(value) == "string" and value:match("^[%a_$][%w_$]*$") ~= nil
end

local function qualified_name(value)
	if type(value) ~= "string" or value == "" then
		return false
	end
	for segment in value:gmatch("[^.]+") do
		if not identifier(segment) then
			return false
		end
	end
	return true
end

local function find_body(node)
	for child in node:iter_children() do
		if child:named() and (child:type() == "class_body" or child:type() == "enum_body") then
			return child
		end
	end
end

local function class_context(buffer, language, row)
	local ok, parser = pcall(vim.treesitter.get_parser, buffer, language)
	if not ok or parser == nil then
		return nil, failure("parser_unavailable", language)
	end
	local parsed, trees = pcall(function()
		return parser:parse()
	end)
	if not parsed or trees == nil or trees[1] == nil then
		return nil, failure("parser_unavailable", language)
	end
	local candidates, all_classes = {}, {}
	local function visit(node)
		if CLASS_NODES[node:type()] then
			table.insert(all_classes, node)
			local start_row, _, end_row = node:range()
			if start_row <= row and row <= end_row then
				table.insert(candidates, node)
			end
		end
		for child in node:iter_children() do
			if child:named() then
				visit(child)
			end
		end
	end
	visit(trees[1]:root())
	table.sort(candidates, function(left, right)
		local ls, _, le = left:range()
		local rs, _, re = right:range()
		return (le - ls) < (re - rs)
	end)
	local node = candidates[1] or (#all_classes == 1 and all_classes[1] or nil)
	local body = node and find_body(node) or nil
	if not node or not body then
		return nil, failure("event_class_required")
	end
	return { node = node, body = body }
end

local function annotation(options)
	local platform = options.platform
	if platform == "bukkit" then
		if options.ignore_cancelled ~= nil and type(options.ignore_cancelled) ~= "boolean" then
			return nil, failure("event_option_invalid", tostring(options.ignore_cancelled))
		end
		local priority = options.priority or "NORMAL"
		if not PRIORITIES[priority] then
			return nil, failure("event_option_invalid", priority)
		end
		local attributes = {}
		if priority ~= "NORMAL" then
			table.insert(attributes, "priority = org.bukkit.event.EventPriority." .. priority)
		end
		if options.ignore_cancelled == true then
			table.insert(attributes, "ignoreCancelled = true")
		end
		return "@org.bukkit.event.EventHandler"
			.. (#attributes > 0 and ("(" .. table.concat(attributes, ", ") .. ")") or ""),
			"org.bukkit.event.Listener"
	elseif platform == "bungeecord" then
		local priority = options.priority or "NORMAL"
		if not PRIORITIES[priority] then
			return nil, failure("event_option_invalid", priority)
		end
		local suffix = priority ~= "NORMAL" and ("(priority = net.md_5.bungee.event.EventPriority." .. priority .. ")")
			or ""
		return "@net.md_5.bungee.event.EventHandler" .. suffix, "net.md_5.bungee.api.plugin.Listener"
	elseif platform == "forge" then
		local kind = options.forge_kind or "eventbus"
		if not FORGE_KINDS[kind] then
			return nil, failure("event_option_invalid", kind)
		end
		return kind == "fml" and "@net.minecraftforge.fml.common.Mod.EventHandler"
			or "@net.minecraftforge.eventbus.api.SubscribeEvent"
	elseif platform == "neoforge" then
		return "@net.neoforged.bus.api.SubscribeEvent"
	elseif platform == "velocity" then
		local order = options.order or "NORMAL"
		if not VELOCITY_ORDERS[order] then
			return nil, failure("event_option_invalid", order)
		end
		local suffix = order ~= "NORMAL" and ("(order = com.velocitypowered.api.event.PostOrder." .. order .. ")") or ""
		return "@com.velocitypowered.api.event.Subscribe" .. suffix
	elseif platform == "sponge" then
		local order = options.order or "DEFAULT"
		if not SPONGE_ORDERS[order] then
			return nil, failure("event_option_invalid", order)
		end
		if options.ignore_cancelled ~= nil and type(options.ignore_cancelled) ~= "boolean" then
			return nil, failure("event_option_invalid", tostring(options.ignore_cancelled))
		end
		local suffix = order ~= "DEFAULT" and ("(order = org.spongepowered.api.event.Order." .. order .. ")") or ""
		return "@org.spongepowered.api.event.Listener" .. suffix
	end
	return nil, failure("event_platform_invalid", tostring(platform))
end

local function add_interface(buffer, context, language, interface)
	if not interface then
		return false
	end
	local start_row, start_col = context.node:range()
	local body_row, body_col = context.body:range()
	local header_lines = vim.api.nvim_buf_get_text(buffer, start_row, start_col, body_row, body_col, {})
	local header = table.concat(header_lines, "\n"):gsub("%s+$", "")
	if header:find(interface, 1, true) then
		return false
	end
	local updated
	if language == "java" then
		updated = header:match("%f[%w]implements%f[%W]") and (header .. ", " .. interface)
			or (header .. " implements " .. interface)
	else
		local has_delegation = false
		for child in context.node:iter_children() do
			if child:named() and child:type() == "delegation_specifier" then
				has_delegation = true
				break
			end
		end
		updated = has_delegation and (header .. ", " .. interface) or (header .. " : " .. interface)
	end
	updated = updated .. " "
	vim.api.nvim_buf_set_text(
		buffer,
		start_row,
		start_col,
		body_row,
		body_col,
		vim.split(updated, "\n", { plain = true })
	)
	return true
end

local function method_lines(language, annotation_text, name, event, indent, unit, sponge_cancelled)
	local lines = { "", indent .. annotation_text }
	if sponge_cancelled then
		table.insert(
			lines,
			indent .. "@org.spongepowered.api.event.filter.IsCancelled(org.spongepowered.api.util.Tristate.UNDEFINED)"
		)
	end
	if language == "java" then
		vim.list_extend(lines, {
			indent .. "public void " .. name .. "(" .. event .. " event) {",
			indent .. unit,
			indent .. "}",
		})
	else
		vim.list_extend(lines, {
			indent .. "fun " .. name .. "(event: " .. event .. ") {",
			indent .. unit,
			indent .. "}",
		})
	end
	table.insert(lines, "")
	return lines
end

---@param options { buffer?: integer, row?: integer, platform: string, event: string, name?: string, priority?: string, order?: string, ignore_cancelled?: boolean, forge_kind?: "fml"|"eventbus" }
---@return table
function M.generate(options)
	options = options or {}
	local buffer = options.buffer or 0
	if not vim.api.nvim_buf_is_loaded(buffer) then
		return failure("buffer_unloaded")
	end
	if not vim.bo[buffer].modifiable or vim.bo[buffer].readonly then
		return failure("source_buffer_readonly")
	end
	local language = vim.bo[buffer].filetype
	if language ~= "java" and language ~= "kotlin" then
		return failure("jvm_source_required", language)
	end
	if not qualified_name(options.event) then
		return failure("event_class_invalid", tostring(options.event))
	end
	local name = options.name or "onEvent"
	if not identifier(name) then
		return failure("event_listener_name_invalid", tostring(name))
	end
	local annotation_text, interface_or_error = annotation(options)
	if not annotation_text then
		if type(interface_or_error) == "table" then
			return interface_or_error
		end
		return failure("event_platform_invalid", tostring(options.platform))
	end
	local row = options.row
	if row == nil then
		row = buffer == vim.api.nvim_get_current_buf() and (vim.api.nvim_win_get_cursor(0)[1] - 1) or 0
	end
	local context, context_error = class_context(buffer, language, row)
	if not context then
		return context_error or failure("event_class_required")
	end
	local class_text = vim.treesitter.get_node_text(context.node, buffer)
	if class_text:match("%f[%w_$]" .. vim.pesc(name) .. "%s*%(") then
		return failure("event_listener_duplicate", name)
	end
	local changed_header = add_interface(buffer, context, language, interface_or_error)
	if changed_header then
		local refreshed, refresh_error = class_context(buffer, language, row)
		if not refreshed then
			vim.api.nvim_buf_call(buffer, function()
				vim.cmd("silent undo")
			end)
			return refresh_error or failure("event_class_required")
		end
		context = refreshed
		vim.api.nvim_buf_call(buffer, function()
			vim.cmd("undojoin")
		end)
	end
	local unit = require("minecraft-dev").config.defaults.source_generation.indent
	if type(unit) ~= "string" or unit == "" then
		unit = "    "
	end
	local _, _, body_end_row, body_end_col = context.body:range()
	local closing_line = vim.api.nvim_buf_get_lines(buffer, body_end_row, body_end_row + 1, false)[1] or ""
	local before_closing = closing_line:sub(1, math.max(body_end_col - 1, 0))
	local class_indent = before_closing:match("^(%s*)$") or closing_line:match("^(%s*)") or ""
	local indent = class_indent .. unit
	local lines = method_lines(
		language,
		annotation_text,
		name,
		options.event,
		indent,
		unit,
		options.platform == "sponge" and options.ignore_cancelled == false
	)
	vim.api.nvim_buf_set_text(buffer, body_end_row, body_end_col - 1, body_end_row, body_end_col - 1, lines)
	return { status = "generated", buffer = buffer, line = body_end_row + 1, platform = options.platform, name = name }
end

return M
