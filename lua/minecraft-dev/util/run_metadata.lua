local fs = require("minecraft-dev.util.fs")

local M = {}

---@param project_root string
---@param runs table[]
function M.write(project_root, runs)
	if #runs == 0 then return end
	local directory = vim.fs.joinpath(project_root, ".nvim")
	fs.mkdir(directory)
	fs.write_file(vim.fs.joinpath(directory, "minecraft-dev-runs.json"), vim.json.encode(runs) .. "\n")
end

return M
