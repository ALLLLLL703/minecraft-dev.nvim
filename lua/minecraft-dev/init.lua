local M = {}
---@type MinecraftDevConfig | {}
M.config = {}

---@param opts? MinecraftDevConfigOpt | MinecraftDevConfig
function M.setup(opts)
	M.config = require("minecraft-dev.config").normalize(opts)
	require("minecraft-dev.command").setup()
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
