local M = {}

function M.setup()
	vim.api.nvim_create_user_command("GmcPro", function(opts)
		require("minecraft-dev.command").dispatch(opts.args)
	end, { nargs = "*", complete = require("minecraft-dev.completion").complete })
end

function M.dispatch(args)
	local argv = vim.split(args, "%s+", { trimempty = true })

	local project = argv[1]
	local build_tool = argv[2]
	local version = argv[3]
	local path = argv[4]

	if project == "paper" then
		require("minecraft-dev.generators.paper").run(build_tool, path, version)
		return
	end
	print("Unsupported project: " .. tostring(project))
end

return M
