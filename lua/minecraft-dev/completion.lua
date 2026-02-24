local M = {}

local completions = { project = { "paper", "fabric", "forge", "spigot", "bukkit" }, build = { "maven", "gradle" } }

---comment
---@param arg_lead string
---@param cmd_line string
---@return table
function M.complete(arg_lead, cmd_line)
	local args = vim.split(cmd_line, "%s+", { trimempty = true })
	local index = #args
	if index == 1 then
		return completions.project
	elseif index == 2 and args[2] == "fabric" then
		return { "gradle" }
	elseif index == 2 and M.group_equals(completions.project, args[2]) then
		return completions.build
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
