local M = {}
---@type MinecraftDevConfig | {}
M.config = {}

---@param opts? MinecraftDevConfigOpt | MinecraftDevConfig
function M.setup(opts)
	M.config = require("minecraft-dev.config").normalize(opts)
	require("minecraft-dev.command").setup()
	require("minecraft-dev.translation_diagnostics").setup()
	require("minecraft-dev.translation_index").setup()
	require("minecraft-dev.translation_source").setup()
end

---@param spec table
---@param callback? fun(result: table)
---@return table
function M.generate(spec, callback)
	return require("minecraft-dev.project").generate(spec, callback)
end

---@param spec table
---@param callback? fun(result: table)
---@return table
function M.generate_async(spec, callback)
	return require("minecraft-dev.project").generate_async(spec, callback)
end

---@param options table
---@return table
function M.generate_template(options)
	return require("minecraft-dev.custom").generate(options)
end

---@param options table
---@return table?, table?
function M.list_templates(options)
	return require("minecraft-dev.custom").list(options)
end

---@param options? { buffer?: integer, order?: string, default_path?: string, template_path?: string, template_content?: string }
---@return table
function M.sort_translations(options)
	return require("minecraft-dev.translations").sort_buffer(options)
end

---@param options? { buffer?: integer, default_path?: string }
---@return table
function M.diagnose_translations(options)
	return require("minecraft-dev.translation_diagnostics").diagnose_buffer(options)
end

---@param options? { buffer?: integer, root?: string, prefix?: string }
---@return table
function M.list_translation_keys(options)
	return require("minecraft-dev.translation_index").list(options)
end

---@param options? { buffer?: integer, root?: string, prefix?: string }
---@return table
function M.complete_translations(options)
	return require("minecraft-dev.translation_index").complete(options)
end

---@param options? { buffer?: integer, root?: string, key?: string, open?: boolean }
---@return table
function M.goto_translation(options)
	return require("minecraft-dev.translation_index").goto_translation(options)
end

---@param options? { buffer?: integer, root?: string, language?: string }
---@return table
function M.diagnose_translation_usages(options)
	return require("minecraft-dev.translation_source").diagnose_buffer(options)
end

---@param options? { buffer?: integer, root?: string, key?: string, open?: boolean, max_files?: integer }
---@return table
function M.find_translation_usages(options)
	return require("minecraft-dev.translation_usages").find(options)
end

function M.reload()
	local cur_config = vim.deepcopy(M.config)
	local notify = require("minecraft-dev.util.notify")
	for module, _ in pairs(package.loaded) do
		if module:match("^minecraft%-dev") then
			if cur_config.logging and cur_config.logging.debug then
				notify.debug({ "reload", "module_reloaded" }, module)
			end

			package.loaded[module] = nil
		end
	end
	require("minecraft-dev").setup(cur_config)

	notify.notify(vim.log.levels.INFO, { "reload", "success" })
end
return M
