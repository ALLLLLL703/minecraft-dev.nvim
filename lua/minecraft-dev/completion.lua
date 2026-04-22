local M = {}

---@type table[]
local completions = { paper = { "maven", "gradle" }, fabric = { "gradle" } }

---comment
---@param arg_lead string
---@param cmd_line string
---@return table
function M.complete(arg_lead, cmd_line)
	local args = vim.split(cmd_line, "%s+", { trimempty = true })
	local index = #args
	if index == 1 then
		return vim.tbl_map(tostring, vim.tbl_keys(completions))
	elseif index == 2 and M.group_equals(vim.tbl_keys(completions), args[2]) then
		return vim.tbl_values(completions[args[index]])
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
