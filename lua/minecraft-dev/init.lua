local M = {}
---@type MinecraftDevConfig | {}
M.config = {}

---@param opts? MinecraftDevConfigOpt | MinecraftDevConfig
function M.setup(opts)
	-- Setup function for minecraft-dev.nvim

	M.config = vim.tbl_deep_extend("force", require("minecraft-dev.config").default_config, opts or {})
	require("minecraft-dev.command").setup()
end

function M.reload()
	local cur_config = vim.deepcopy(M.config)
	for module, _ in pairs(package.loaded) do
		if module:match("^minecraft%-dev") then
			if cur_config.debug then
				print(module .. " reloaded")
			end

			package.loaded[module] = nil
		end
	end
	require("minecraft-dev").setup(cur_config)

	vim.notify("Successfully reload minecraft-dev!")
end
return M
