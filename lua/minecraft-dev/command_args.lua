local M = {}

---@class MinecraftDevCommandArgs
---@field project string
---@field build_tool string
---@field version string
---@field path string?

---@param args string
---@return MinecraftDevCommandArgs?, string?
function M.parse(args)
	local argv = vim.split(args or "", "%s+", { trimempty = true })
	if #argv < 3 then
		return nil, "invalid_args"
	end

	return {
		project = argv[1],
		build_tool = argv[2],
		version = argv[3],
		path = argv[4],
	}, nil
end

---@param path string?
---@param use_cwd_when_missing boolean
---@return string?
function M.resolve_path(path, use_cwd_when_missing)
	if path ~= nil then
		return vim.fn.expand(path)
	end

	if use_cwd_when_missing then
		return vim.fn.getcwd()
	end

	return nil
end

return M
