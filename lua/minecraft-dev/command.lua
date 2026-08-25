local M = {}
local command_args = require("minecraft-dev.command_args")
local notify = require("minecraft-dev.util.notify")
local platforms = require("minecraft-dev.platforms")

local function generation_error(result)
	local err = result.error or { code = "minecraft_class_write_failed" }
	notify.notify(vim.log.levels.ERROR, { "source_generation", err.code }, tostring(err.detail or ""))
end

local function event_options(args)
	local values = vim.split(vim.trim(args), "%s+")
	---@type table<string, any>
	local options = { platform = values[1], event = values[2], name = values[3] }
	for index = 4, #values do
		local key, value = values[index]:match("^([%w_]+)=(.+)$")
		if key == "ignore_cancelled" then
			if value == "true" then
				options[key] = true
			elseif value == "false" then
				options[key] = false
			else
				options[key] = value
			end
		elseif key then
			options[key] = value
		end
	end
	return options
end

local function copy_target(format, member)
	local result = require("minecraft-dev").copy_jvm_target({
		format = format,
		member = member ~= "" and member or nil,
		row = vim.api.nvim_win_get_cursor(0)[1] - 1,
	})
	if result.status == "copied" then
		notify.notify(vim.log.levels.INFO, { "access_rules", "target_copied" }, result.text)
	else
		notify.notify(vim.log.levels.ERROR, { "access_rules", result.error.code }, tostring(result.error.detail or ""))
	end
end

function M.setup()
	pcall(vim.api.nvim_del_user_command, "GmcPro")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevNew")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevSortTranslations")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevGotoTranslation")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevFindTranslationUsages")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevGotoBukkitMain")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevGotoForgeMod")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevGotoForgeLogo")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevGotoFabricEntrypoint")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevGotoFabricResource")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevGotoMixinReference")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevEditNbt")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevSaveNbt")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevReloadNbt")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevLookupMapping")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevGotoAccessTarget")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevCopyAt")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevCopyAw")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevCopyCoremodTarget")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevCopyMixinTarget")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevFindMixins")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevGenerateMixinMember")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevGenerateEventListener")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevGenerateMinecraftClass")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevRefreshSourceInsight")
	pcall(vim.api.nvim_del_user_command, "MinecraftDevDiagnoseEventListeners")
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
	vim.api.nvim_create_user_command("MinecraftDevGotoBukkitMain", function(opts)
		local result = require("minecraft-dev").goto_bukkit_main({ main = opts.args ~= "" and opts.args or nil })
		if result.status == "failed" then
			local err = result.error or { code = "main_unresolved" }
			notify.notify(vim.log.levels.ERROR, { "metadata", err.code }, tostring(err.detail or ""))
		end
	end, {
		nargs = "?",
		complete = function(lead)
			return vim.tbl_map(function(item)
				return item.word
			end, require("minecraft-dev").complete_bukkit_main({ prefix = lead }).items)
		end,
	})
	vim.api.nvim_create_user_command("MinecraftDevGotoForgeMod", function(opts)
		local result = require("minecraft-dev").goto_forge_mod({ mod_id = opts.args ~= "" and opts.args or nil })
		if result.status == "failed" then
			local err = result.error or { code = "toml_mod_id_unresolved" }
			notify.notify(vim.log.levels.ERROR, { "metadata", err.code }, tostring(err.detail or ""))
		end
	end, { nargs = "?" })
	vim.api.nvim_create_user_command("MinecraftDevGotoForgeLogo", function()
		local result = require("minecraft-dev").goto_forge_logo()
		if result.status == "failed" then
			local err = result.error or { code = "toml_logo_unresolved" }
			notify.notify(vim.log.levels.ERROR, { "metadata", err.code }, tostring(err.detail or ""))
		end
	end, {})
	vim.api.nvim_create_user_command("MinecraftDevGotoFabricEntrypoint", function(opts)
		local result = require("minecraft-dev").goto_fabric_entrypoint({ value = opts.args ~= "" and opts.args or nil })
		if result.status == "failed" then
			local err = result.error or { code = "fabric_entrypoint_unresolved" }
			notify.notify(vim.log.levels.ERROR, { "metadata", err.code }, tostring(err.detail or ""))
		end
	end, { nargs = "?" })
	vim.api.nvim_create_user_command("MinecraftDevGotoFabricResource", function()
		local result = require("minecraft-dev").goto_fabric_resource()
		if result.status == "failed" then
			local err = result.error or { code = "fabric_resource_unresolved" }
			notify.notify(vim.log.levels.ERROR, { "metadata", err.code }, tostring(err.detail or ""))
		end
	end, {})
	vim.api.nvim_create_user_command("MinecraftDevGotoMixinReference", function(opts)
		local result = require("minecraft-dev").goto_mixin_reference({ value = opts.args ~= "" and opts.args or nil })
		if result.status == "failed" then
			local err = result.error or { code = "mixin_reference_unresolved" }
			notify.notify(vim.log.levels.ERROR, { "metadata", err.code }, tostring(err.detail or ""))
		end
	end, { nargs = "?" })
	vim.api.nvim_create_user_command("MinecraftDevEditNbt", function(opts)
		local path = opts.args ~= "" and opts.args or vim.api.nvim_buf_get_name(0)
		local result = require("minecraft-dev").open_nbt({ path = path })
		if result.status == "failed" then
			notify.notify(vim.log.levels.ERROR, { "nbt", result.error.code }, tostring(result.error.detail or ""))
		end
	end, { nargs = "?", complete = "file" })
	vim.api.nvim_create_user_command("MinecraftDevSaveNbt", function()
		local result = require("minecraft-dev").save_nbt()
		if result.status == "saved" then
			notify.notify(vim.log.levels.INFO, { "nbt", "saved" }, result.path)
		else
			notify.notify(vim.log.levels.ERROR, { "nbt", result.error.code }, tostring(result.error.detail or ""))
		end
	end, {})
	vim.api.nvim_create_user_command("MinecraftDevReloadNbt", function(opts)
		local result = require("minecraft-dev").reload_nbt({ force = opts.bang })
		if result.status == "failed" then
			notify.notify(vim.log.levels.ERROR, { "nbt", result.error.code }, tostring(result.error.detail or ""))
		end
	end, { bang = true })
	vim.api.nvim_create_user_command("MinecraftDevLookupMapping", function(opts)
		local result = require("minecraft-dev").lookup_mapping({ query = opts.args })
		if result.status == "failed" then
			notify.notify(vim.log.levels.ERROR, { "mappings", result.error.code }, tostring(result.error.detail or ""))
		elseif #result.matches == 0 then
			notify.notify(vim.log.levels.WARN, { "mappings", "mapping_not_found" }, opts.args)
		elseif #result.matches == 1 then
			local item = result.matches[1]
			notify.notify(
				vim.log.levels.INFO,
				{ "mappings", "mapping_found" },
				item.source_name or item.source_owner,
				item.target_name or item.target_owner
			)
		else
			local config = require("minecraft-dev").config
			vim.ui.select(result.matches, {
				prompt = config.prompts.mappings.select_mapping,
				format_item = function(item)
					return string.format(
						"%s -> %s",
						item.source_name or item.source_owner,
						item.target_name or item.target_owner
					)
				end,
			}, function() end)
		end
	end, { nargs = 1 })
	vim.api.nvim_create_user_command("MinecraftDevGotoAccessTarget", function()
		local result = require("minecraft-dev").goto_access_target()
		if result.status == "failed" then
			notify.notify(
				vim.log.levels.ERROR,
				{ "access_rules", result.error.code },
				tostring(result.error.detail or "")
			)
		end
	end, {})
	vim.api.nvim_create_user_command("MinecraftDevCopyAt", function(opts)
		copy_target("at", opts.args)
	end, { nargs = "?" })
	vim.api.nvim_create_user_command("MinecraftDevCopyAw", function(opts)
		copy_target("aw", opts.args)
	end, { nargs = "?" })
	vim.api.nvim_create_user_command("MinecraftDevCopyCoremodTarget", function(opts)
		copy_target("coremod", opts.args)
	end, { nargs = "?" })
	vim.api.nvim_create_user_command("MinecraftDevCopyMixinTarget", function(opts)
		copy_target("mixin", opts.args)
	end, { nargs = "?" })
	vim.api.nvim_create_user_command("MinecraftDevFindMixins", function(opts)
		local result = require("minecraft-dev").find_mixins({ target = opts.args ~= "" and opts.args or nil })
		if result.status == "failed" then
			notify.notify(
				vim.log.levels.ERROR,
				{ "mixin_actions", result.error.code },
				tostring(result.error.detail or "")
			)
		end
	end, { nargs = "?" })
	vim.api.nvim_create_user_command("MinecraftDevGenerateMixinMember", function(opts)
		local args = vim.split(vim.trim(opts.args), "%s+")
		local result = require("minecraft-dev").generate_mixin_member({
			kind = args[1],
			member = args[2],
			prefix = args[3],
		})
		if result.status == "generated" then
			vim.api.nvim_set_current_buf(result.buffer)
			vim.api.nvim_win_set_cursor(0, { result.line + 1, 0 })
			notify.notify(vim.log.levels.INFO, { "mixin_actions", "mixin_generated" }, result.name)
		else
			notify.notify(
				vim.log.levels.ERROR,
				{ "mixin_actions", result.error.code },
				tostring(result.error.detail or "")
			)
		end
	end, {
		nargs = "+",
		complete = function(lead, command_line)
			if #vim.split(vim.trim(command_line), "%s+") <= 2 then
				return vim.tbl_filter(function(kind)
					return vim.startswith(kind, lead)
				end, { "accessor_getter", "accessor_setter", "invoker", "shadow", "overwrite", "soft_implements" })
			end
			return {}
		end,
	})
	vim.api.nvim_create_user_command("MinecraftDevGenerateEventListener", function(opts)
		local result = require("minecraft-dev").generate_event_listener(event_options(opts.args))
		if result.status == "generated" then
			vim.api.nvim_win_set_cursor(0, { result.line + 1, 0 })
			notify.notify(vim.log.levels.INFO, { "source_generation", "event_listener_generated" }, result.name)
		else
			generation_error(result)
		end
	end, {
		nargs = "+",
		complete = function(lead, command_line)
			local count = #vim.split(vim.trim(command_line), "%s+")
			if count <= 2 then
				return vim.tbl_filter(function(value)
					return vim.startswith(value, lead)
				end, { "bukkit", "bungeecord", "forge", "neoforge", "velocity", "sponge" })
			end
			return {}
		end,
	})
	vim.api.nvim_create_user_command("MinecraftDevGenerateMinecraftClass", function(opts)
		local args = vim.split(vim.trim(opts.args), "%s+")
		local result = require("minecraft-dev").generate_minecraft_class({
			platform = args[1],
			kind = args[2],
			class_name = args[3],
			minecraft_version = args[4],
		})
		if result.status == "generated" then
			notify.notify(vim.log.levels.INFO, { "source_generation", "minecraft_class_generated" }, result.path)
		else
			generation_error(result)
		end
	end, {
		nargs = "+",
		complete = function(lead, command_line)
			local args = vim.split(vim.trim(command_line), "%s+")
			local values = {}
			if #args <= 2 then
				values = { "forge", "neoforge", "fabric" }
			elseif #args == 3 then
				values = args[2] == "fabric" and { "block", "item", "enchantment", "status_effect" }
					or { "block", "item", "enchantment", "mob_effect", "packet" }
			end
			return vim.tbl_filter(function(value)
				return vim.startswith(value, lead)
			end, values)
		end,
	})
	vim.api.nvim_create_user_command("MinecraftDevRefreshSourceInsight", function()
		local result = require("minecraft-dev").refresh_source_insight()
		if result.status == "refreshed" then
			notify.notify(
				vim.log.levels.INFO,
				{ "source_insight", "refreshed" },
				string.format("%d colors, %d diagnostics", #result.highlights, #result.diagnostics)
			)
		else
			generation_error(result)
		end
	end, {})
	vim.api.nvim_create_user_command("MinecraftDevDiagnoseEventListeners", function()
		local result = require("minecraft-dev").diagnose_event_listeners()
		if result.status == "failed" then
			generation_error(result)
		end
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
