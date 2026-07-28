local M = {}

local function read_owner(path)
	local stat = vim.uv.fs_stat(path)
	if not stat then return nil end
	local owner_path = stat.type == "directory" and path .. "/pid" or path
	local ok, lines = pcall(vim.fn.readfile, owner_path)
	return ok and lines[1] or nil
end

local function owner_is_running(path)
	local owner = read_owner(path)
	local pid = owner and tonumber(owner:match("^(%d+)"))
	if not pid then return nil end
	local ok, result = pcall(vim.uv.kill, pid, 0)
	return ok and result == 0
end

---@param path string
---@return table?, table?
function M.acquire(path)
	local token = string.format("%d:%s", vim.uv.os_getpid(), tostring(vim.uv.hrtime()))
	local pending_path = path .. "." .. token:gsub(":", "-")
	local wrote, write_result = pcall(vim.fn.writefile, { token }, pending_path)
	if not wrote or write_result ~= 0 then
		return nil, { code = "destination_prepare_failed", detail = wrote and "failed to write pending lock" or write_result }
	end
	local created, err = vim.uv.fs_link(pending_path, path)
	vim.fn.delete(pending_path)
	if not created then
		local owner_running = owner_is_running(path)
		local code = owner_running == false and "stale_generation_lock"
			or (vim.uv.fs_stat(path) and "generation_in_progress" or "destination_prepare_failed")
		return nil, { code = code, detail = err }
	end
	local lock = {}
	function lock.release()
		if read_owner(path) ~= token then return nil, "generation lock ownership changed" end
		if vim.fn.delete(path) == 0 then return true end
		return nil, "failed to remove generation lock"
	end
	return lock, nil
end

return M
