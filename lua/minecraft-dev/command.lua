local M = {}
local command_args = require("minecraft-dev.command_args")
local notify = require("minecraft-dev.util.notify")

function M.setup()
	pcall(vim.api.nvim_del_user_command, "GmcPro")
	vim.api.nvim_create_user_command("GmcPro", function(opts)
		require("minecraft-dev.command").dispatch(opts.args)
	end, { nargs = "*", complete = require("minecraft-dev.completion").complete })
end

function M.dispatch(args)
	local parsed_args, err = command_args.parse(args)
	if err ~= nil then
		notify.notify(vim.log.levels.ERROR, { "command", "invalid_args" })
		return
	end
	local config = require("minecraft-dev").config
	local path = command_args.resolve_path(parsed_args.path, config.defaults.command.use_cwd_when_path_missing)

	if parsed_args.project == "paper" then
		require("minecraft-dev.generators.paper").run(parsed_args.build_tool, path, parsed_args.version)
		return
	elseif parsed_args.project == "fabric" then
		require("minecraft-dev.generators.fabric").run(parsed_args.build_tool, path, parsed_args.version)
		return
	end

	notify.notify(vim.log.levels.ERROR, { "command", "unsupported_project" }, tostring(parsed_args.project))
end

return M
