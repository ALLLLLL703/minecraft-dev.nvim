local M = {}
local command_args = require("minecraft-dev.command_args")
local notify = require("minecraft-dev.util.notify")
local platforms = require("minecraft-dev.platforms")

function M.setup()
	pcall(vim.api.nvim_del_user_command, "GmcPro")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevNew")
	vim.api.nvim_create_user_command("GmcPro", function(opts)
		require("minecraft-dev.command").dispatch(opts.args)
	end, { nargs = "*", complete = require("minecraft-dev.completion").complete })
	vim.api.nvim_create_user_command("MinecraftDevNew", function()
		require("minecraft-dev.command").dispatch("")
	end, {})
end

function M.dispatch(args)
	if type(args) ~= "string" or vim.trim(args) == "" then
		return require("minecraft-dev.custom.wizard").run()
	end
	local parsed_args, err = command_args.parse(args)
	if err ~= nil then
		notify.notify(vim.log.levels.ERROR, { "command", "invalid_args" })
		return { status = "failed", error = { code = "invalid_args" } }
	end
	local config = require("minecraft-dev").config
	local path = command_args.resolve_path(parsed_args.path, config.defaults.command.use_cwd_when_path_missing)

	local platform = platforms.get(parsed_args.project)
	if not platform then
		notify.notify(vim.log.levels.ERROR, { "command", "unsupported_project" }, tostring(parsed_args.project))
		return { status = "failed", error = { code = "unsupported_project" } }
	end
	if not platforms.supports_command(parsed_args.project) then
		notify.notify(vim.log.levels.ERROR, { "command", "interactive_only" }, parsed_args.project)
		return { status = "failed", error = { code = "interactive_only", platform = parsed_args.project } }
	end
	if not platforms.supports(parsed_args.project, parsed_args.build_tool) then
		notify.notify(vim.log.levels.ERROR, { "command", "unsupported_build" }, tostring(parsed_args.build_tool))
		return { status = "failed", error = { code = "unsupported_build" } }
	end

	local ok, operation = pcall(
		require(platform.generator).run,
		parsed_args.build_tool,
		path,
		parsed_args.version,
		nil,
		parsed_args.project
	)
	if not ok then
		notify.notify(vim.log.levels.ERROR, { "command", "generation_failed" }, tostring(operation))
		return { status = "failed", error = { code = "generation_failed", detail = operation } }
	end
	return { status = "started", operation = operation }
end

return M
