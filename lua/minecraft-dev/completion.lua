local M = {}

local platforms = require("minecraft-dev.platforms")

---comment
---@param arg_lead string
---@param cmd_line string
---@return table
function M.complete(arg_lead, cmd_line)
	local args = vim.split(cmd_line, "%s+", { trimempty = true })
	local index = #args
	if index == 1 then
		return platforms.names()
	elseif index == 2 and platforms.get(args[2]) then
		return platforms.build_systems(args[2])
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
