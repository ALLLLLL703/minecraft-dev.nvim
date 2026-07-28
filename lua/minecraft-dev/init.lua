local M = {}
---@type MinecraftDevConfig | {}
M.config = {}

---@param opts? MinecraftDevConfigOpt | MinecraftDevConfig
function M.setup(opts)
	M.config = require("minecraft-dev.config").normalize(opts)
	require("minecraft-dev.command").setup()
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
