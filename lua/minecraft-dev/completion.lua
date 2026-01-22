local M = {}

local completions = { project = { "paper", "fabric", "forge", "spigot", "bukkit" }, build = { "maven", "gradle" } }

function M.complete(arg_lead, cmd_line)
	local args = vim.split(cmd_line, "%s+", { trimempty = true })
	local index = #args
	if index == 1 then
		return completions.project
	elseif index == 2 then
		return completions.build
	elseif index == 3 then
		return vim.fn.getcompletion(arg_lead, "file")
	end
end

return M
