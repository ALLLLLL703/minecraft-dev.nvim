local M = {}
---@type MinecraftDevConfig | {}
M.config = {}

---@param opts? MinecraftDevConfigOpt | MinecraftDevConfig
function M.setup(opts)
	-- Setup function for minecraft-dev.nvim
	vim.tbl_deep_extend("force", require("minecraft-dev.config").default_config, opts or {})
	require("minecraft-dev.command").setup()
end

function M.reload()
	for _, module in ipairs(package.loaded) do
		if module:match("^minecraft%-dev") then
			package.loaded[module] = nil
		end
	end
	M.setup(M.config)
	vim.notify("Successfully reload minecraft-dev!")
end
M.reload()
return M
