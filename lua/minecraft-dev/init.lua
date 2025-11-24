print("plugin minecraft-dev is successfully loaded")

local _paper = require("minecraft-dev.handle_paper")

local M = {}

local completion_table = {
	{ "fabric", "forge", "paper", "spigot", "bukkit" },
	{ "maven", "gradle" },
}

function M.completion(arg_lead, cmd_line, cursor_pos)
	local args = vim.split(cmd_line, "%s+", { trimempty = true })
	local index = #args -- 参数序号

	local items = completion_table[index]
	if index >= 3 then
		return vim.fn.getcompletion(arg_lead, "file")
	end
	if not items then
		return {}
	end

	return vim.tbl_filter(function(item)
		return item:find("^" .. arg_lead)
	end, items)
end

function M.handle_args(args)
	local argv = vim.split(args, "%s+", { trimempty = true })
	if argv[1] == "paper" then
		_paper.handle_paper(argv[2], argv[3])
	end
end

local function cmd_setup()
	vim.api.nvim_create_user_command("GmcPro", function(opts)
		M.handle_args(opts.args)
	end, {
		nargs = "*",
		complete = M.completion,
	})
end

M.setup = function()
	cmd_setup()
end

M.reload = function()
	package.loaded["minecraft-dev.handle_paper"] = nil
	package.loaded["minecraft-dev.handle_paper"] = nil
	M.setup()
end

return M
