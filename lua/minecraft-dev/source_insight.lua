local jvm_index = require("minecraft-dev.jvm_index")

local M = {}
local highlight_namespace = vim.api.nvim_create_namespace("minecraft-dev.source-colors")
local diagnostic_namespace = vim.api.nvim_create_namespace("minecraft-dev.event-listeners")
local listed_highlights, current_highlights = pcall(vim.api.nvim_get_hl, 0, {})
local highlight_budget_available = not listed_highlights or vim.tbl_count(current_highlights) < 19000

local COLORS = {
	DARK_RED = "#AA0000",
	RED = "#FF5555",
	GOLD = "#FFAA00",
	YELLOW = "#FFFF55",
	DARK_GREEN = "#00AA00",
	GREEN = "#55FF55",
	AQUA = "#55FFFF",
	DARK_AQUA = "#00AAAA",
	DARK_BLUE = "#0000AA",
	BLUE = "#5555FF",
	LIGHT_PURPLE = "#FF55FF",
	DARK_PURPLE = "#AA00AA",
	WHITE = "#FFFFFF",
	GRAY = "#AAAAAA",
	DARK_GRAY = "#555555",
	BLACK = "#000000",
}

local COLOR_CLASSES = {
	["org.bukkit.ChatColor"] = true,
	["net.md_5.bungee.api.ChatColor"] = true,
	["org.spongepowered.api.text.format.TextColors"] = true,
	["net.kyori.text.format.TextColor"] = true,
	["net.kyori.adventure.text.format.NamedTextColor"] = true,
	["net.minecraft.ChatFormatting"] = true,
	["net.minecraft.util.text.TextFormatting"] = true,
}

local HANDLERS = {
	["org.bukkit.event.EventHandler"] = { platform = "bukkit", listener = "org.bukkit.event.Listener" },
	["net.md_5.bungee.event.EventHandler"] = {
		platform = "bungeecord",
		listener = "net.md_5.bungee.api.plugin.Listener",
	},
}

local CLASS_NODES = {
	class_declaration = true,
	enum_declaration = true,
	record_declaration = true,
	object_declaration = true,
}

local function failure(code, detail)
	return { status = "failed", error = { code = code, detail = detail or "" } }
end

local function source_language(buffer)
	local language = vim.bo[buffer].filetype
	return (language == "java" or language == "kotlin") and language or nil
end

local function imports(buffer)
	local result = { colors = {}, handlers = {} }
	for _, line in ipairs(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)) do
		local fqn, alias = line:match("^%s*import%s+([%w_.$]+)%s+as%s+([%w_$]+)%s*;?%s*$")
		if not fqn then
			fqn = line:match("^%s*import%s+([%w_.$]+)%s*;?%s*$")
		end
		if fqn then
			local simple = alias or fqn:match("([%w_$]+)$")
			if COLOR_CLASSES[fqn] then
				result.colors[simple] = fqn
			end
			if HANDLERS[fqn] then
				result.handlers[simple] = HANDLERS[fqn]
			end
		end
	end
	return result
end

local function fully_qualified_before(line, start_col, class_name)
	local through_class = line:sub(1, start_col + #class_name - 1)
	for fqn in pairs(COLOR_CLASSES) do
		if fqn:match("([%w_$]+)$") == class_name and through_class:sub(-#fqn) == fqn then
			return true
		end
	end
	return false
end

---@param options? { buffer?: integer }
---@return table
function M.highlight_colors(options)
	options = options or {}
	local buffer = options.buffer or 0
	if not vim.api.nvim_buf_is_loaded(buffer) then
		return failure("buffer_unloaded")
	end
	if not source_language(buffer) then
		return { status = "skipped", highlights = {} }
	end
	vim.api.nvim_buf_clear_namespace(buffer, highlight_namespace, 0, -1)
	local imported = imports(buffer).colors
	local highlights, warnings = {}, {}
	for row, line in ipairs(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)) do
		local offset = 1
		while true do
			local start_col, end_col, class_name, color_name = line:find("([%a_$][%w_$]*)%.([A-Z][A-Z_]*)", offset)
			if not start_col then
				break
			end
			local color = COLORS[color_name]
			if color and (imported[class_name] or fully_qualified_before(line, start_col, class_name)) then
				local group = "MinecraftDevColor" .. color_name
				local color_start = end_col - #color_name
				local applied = vim.fn.hlID(group) > 0
				if not applied and highlight_budget_available then
					applied = pcall(vim.api.nvim_set_hl, 0, group, { fg = color })
					if not applied then
						highlight_budget_available = false
					end
				end
				if applied then
					vim.api.nvim_buf_set_extmark(buffer, highlight_namespace, row - 1, color_start, {
						end_col = end_col,
						hl_group = group,
						priority = 120,
					})
				elseif #warnings == 0 then
					table.insert(warnings, { code = "highlight_group_limit" })
				end
				table.insert(highlights, {
					lnum = row - 1,
					col = color_start,
					end_col = end_col,
					name = color_name,
					color = color,
					applied = applied,
				})
			end
			offset = end_col + 1
		end
	end
	return { status = "highlighted", buffer = buffer, highlights = highlights, warnings = warnings }
end

local function class_body(node)
	for child in node:iter_children() do
		if child:named() and (child:type() == "class_body" or child:type() == "enum_body") then
			return child
		end
	end
end

local function direct_handler(body, buffer, imported_handlers)
	for child in body:iter_children() do
		if child:named() and (child:type() == "method_declaration" or child:type() == "function_declaration") then
			local text = vim.treesitter.get_node_text(child, buffer)
			for alias, handler in pairs(imported_handlers) do
				if text:match("@" .. vim.pesc(alias) .. "%f[%W]") then
					return handler
				end
			end
			for fqn, handler in pairs(HANDLERS) do
				if text:find("@" .. fqn, 1, true) then
					return handler
				end
			end
		end
	end
end

local function class_nodes(root)
	local result = {}
	local function visit(node)
		if CLASS_NODES[node:type()] then
			table.insert(result, node)
		end
		for child in node:iter_children() do
			if child:named() then
				visit(child)
			end
		end
	end
	visit(root)
	return result
end

---@param options? { buffer?: integer, root?: string, max_files?: integer }
---@return table
function M.diagnose_event_listeners(options)
	options = options or {}
	local buffer = options.buffer or 0
	if not vim.api.nvim_buf_is_loaded(buffer) then
		return failure("buffer_unloaded")
	end
	local language = source_language(buffer)
	if not language then
		return { status = "skipped", diagnostics = {} }
	end
	local ok, parser = pcall(vim.treesitter.get_parser, buffer, language)
	if not ok or parser == nil then
		return failure("parser_unavailable", language)
	end
	local parsed, trees = pcall(function()
		return parser:parse()
	end)
	if not parsed or trees == nil or trees[1] == nil then
		return failure("parser_unavailable", language)
	end
	local indexed = jvm_index.list({ buffer = buffer, root = options.root, max_files = options.max_files })
	local path = vim.fs.normalize(vim.api.nvim_buf_get_name(buffer))
	local by_line = {}
	for _, entry in ipairs(indexed.entries) do
		if vim.fs.normalize(entry.path) == path then
			by_line[entry.declaration_lnum] = entry
		end
	end
	local imported_handlers = imports(buffer).handlers
	local diagnostics = {}
	for _, node in ipairs(class_nodes(trees[1]:root())) do
		local body = class_body(node)
		local handler = body and direct_handler(body, buffer, imported_handlers) or nil
		if handler then
			local start_row = select(1, node:range())
			local entry = by_line[start_row]
			local inheritance
			if entry then
				inheritance = jvm_index.inherits(indexed, entry, handler.listener)
			end
			if inheritance == false then
				table.insert(diagnostics, {
					lnum = entry.lnum,
					col = entry.col,
					end_lnum = entry.end_lnum,
					end_col = entry.end_col,
					severity = vim.diagnostic.severity.WARN,
					code = "listener_interface_missing",
					platform = handler.platform,
					message = require("minecraft-dev").config.messages.source_insight.listener_interface_missing:format(
						handler.platform,
						handler.listener
					),
				})
			end
		end
	end
	vim.diagnostic.set(diagnostic_namespace, buffer, diagnostics, {})
	return { status = "diagnosed", buffer = buffer, diagnostics = diagnostics, warnings = indexed.warnings }
end

---@param options? { buffer?: integer, root?: string, max_files?: integer }
---@return table
function M.refresh(options)
	options = options or {}
	local highlights = M.highlight_colors(options)
	if highlights.status == "failed" then
		return highlights
	end
	local diagnosed = M.diagnose_event_listeners(options)
	if diagnosed.status == "failed" then
		return diagnosed
	end
	return {
		status = "refreshed",
		buffer = options.buffer or 0,
		highlights = highlights.highlights or {},
		diagnostics = diagnosed.diagnostics or {},
		warnings = vim.list_extend(vim.deepcopy(highlights.warnings or {}), diagnosed.warnings or {}),
	}
end

function M.setup()
	local group = vim.api.nvim_create_augroup("MinecraftDevSourceInsight", { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = { "java", "kotlin" },
		callback = function(args)
			local config = require("minecraft-dev").config.defaults.source_insight
			if config.colors then
				M.highlight_colors({ buffer = args.buf })
			end
		end,
	})
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		pattern = { "*.java", "*.kt" },
		callback = function(args)
			local config = require("minecraft-dev").config.defaults.source_insight
			if config.colors then
				M.highlight_colors({ buffer = args.buf })
			end
			if config.event_diagnostics then
				M.diagnose_event_listeners({ buffer = args.buf })
			end
		end,
	})
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = group,
		pattern = { "*.java", "*.kt" },
		callback = function(args)
			if require("minecraft-dev").config.defaults.source_insight.colors then
				M.highlight_colors({ buffer = args.buf })
			end
		end,
	})
	vim.api.nvim_create_autocmd("BufDelete", {
		group = group,
		pattern = { "*.java", "*.kt" },
		callback = function(args)
			vim.diagnostic.reset(diagnostic_namespace, args.buf)
		end,
	})
end

return M
