local M = {}

local platforms = require("minecraft-dev.platforms")

---comment
---@param arg_lead string
---@param cmd_line string
---@param cursor_pos? integer
---@return table
function M.complete(arg_lead, cmd_line, cursor_pos)
	local before_cursor = cmd_line:sub(1, cursor_pos or #cmd_line)
	local prefix = before_cursor:sub(1, math.max(0, #before_cursor - #arg_lead))
	local args = vim.split(prefix, "%s+", { trimempty = true })
	local index = #args
	local function filter(candidates)
		return vim.tbl_filter(function(candidate) return vim.startswith(candidate, arg_lead) end, candidates)
	end
	if index == 1 then
		return filter(platforms.command_names())
	elseif index == 2 and platforms.supports_command(args[2]) then
		return filter(platforms.build_systems(args[2]))
	elseif index >= 4 then
		return vim.fn.getcompletion(arg_lead, "file")
	end
	return {}
end

---@param arr table
---@param str string
---@return boolean
function M.group_equals(arr, str)
	for i, value in ipairs(arr) do
		if value == str then
			return true
		end
	end
	return false
end
return M
