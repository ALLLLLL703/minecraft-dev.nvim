local M = {}

function M.setup()
	-- Setup function for minecraft-dev.nvim
	require("minecraft-dev.command").setup()
end

-- function M.reload()
-- 	for _, module in ipairs(package.loaded) do
-- 		if module:match("^minecraft%-dev") then
-- 			package.loaded[module] = nil
-- end
-- end
-- 	M.setup()
-- end

return M
