local M = {}
local command_args = require("minecraft-dev.command_args")
local notify = require("minecraft-dev.util.notify")
local platforms = require("minecraft-dev.platforms")

function M.setup()
	pcall(vim.api.nvim_del_user_command, "GmcPro")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevNew")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevSortTranslations")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevGotoTranslation")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevFindTranslationUsages")
	vim.api.nvim_create_user_command("GmcPro", function(opts)
		require("minecraft-dev.command").dispatch(opts.args)
	end, { nargs = "*", complete = require("minecraft-dev.completion").complete })
	vim.api.nvim_create_user_command("MinecraftDevNew", function()
		require("minecraft-dev.command").dispatch("")
	end, {})
	vim.api.nvim_create_user_command("MinecraftDevSortTranslations", function(opts)
		local result = require("minecraft-dev").sort_translations({ order = opts.args ~= "" and opts.args or nil })
		if result.status == "sorted" then
			notify.notify(vim.log.levels.INFO, { "translations", "sorted" }, result.order)
			return
		end
		local err = result.error or { code = "failed" }
		notify.notify(vim.log.levels.ERROR, { "translations", err.code }, tostring(err.detail or ""))
	end, {
		nargs = "?",
		complete = function(lead)
			return vim.tbl_filter(function(order)
				return vim.startswith(order, lead)
			end, require("minecraft-dev.translations").orderings())
		end,
	})
	vim.api.nvim_create_user_command("MinecraftDevGotoTranslation", function(opts)
		local result = require("minecraft-dev").goto_translation({ key = opts.args ~= "" and opts.args or nil })
		if result.status == "failed" then
			local err = result.error or { code = "failed" }
			notify.notify(vim.log.levels.ERROR, { "translations", err.code }, tostring(err.detail or ""))
		end
	end, {
		nargs = "?",
		complete = function(lead)
			return require("minecraft-dev").list_translation_keys({ prefix = lead }).keys
		end,
	})
	vim.api.nvim_create_user_command("MinecraftDevFindTranslationUsages", function(opts)
		local result = require("minecraft-dev").find_translation_usages({ key = opts.args ~= "" and opts.args or nil })
		if result.status == "failed" then
			local err = result.error or { code = "failed" }
			notify.notify(vim.log.levels.ERROR, { "translations", err.code }, tostring(err.detail or ""))
		end
	end, {
		nargs = "?",
		complete = function(lead)
			return require("minecraft-dev").list_translation_keys({ prefix = lead }).keys
		end,
	})
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
	if parsed_args.project == "waterfall" then
		local collected = require("minecraft-dev.context").collect()
		local operation = require("minecraft-dev").generate({
			platform = "waterfall",
			build_system = parsed_args.build_tool,
			minecraft_version = parsed_args.version,
			directory = path,
			group_id = collected.groupId,
			artifact_id = collected.artifactId,
			package_name = collected.package,
			main_class = collected.main,
			language = "java",
			plugin_version = "1.0.0",
		})
		return { status = "started", operation = operation }
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
