local M = {}

local function error_result(callback, code, detail)
	callback(nil, { code = code, detail = detail })
end

local function operation()
	local state = { handle = nil, cancelled = false }
	return {
		set_handle = function(_, handle) state.handle = handle end,
		cancel = function()
			state.cancelled = true
			if state.handle then state.handle:kill(15) end
		end,
		is_cancelled = function() return state.cancelled end,
	}
end

local function unsafe_archive_entry(entry)
	entry = entry:gsub("\\", "/")
	return entry:match("^/") ~= nil
		or entry:match("^%a:/") ~= nil
		or entry == ".."
		or entry:match("^%.%./") ~= nil
		or entry:match("/%.%./") ~= nil
		or entry:match("/%.%.$") ~= nil
end

local function prepare_archive(options, callback)
	if vim.fn.executable("unzip") ~= 1 then return nil, { code = "unzip_missing" } end
	local op = operation()
	local root = vim.fn.tempname()
	local list_handle = vim.system({ "unzip", "-Z1", options.source }, { text = true }, vim.schedule_wrap(function(result)
		if op:is_cancelled() then return end
		if result.code ~= 0 then return error_result(callback, "archive_list_failed", result.stderr) end
		for _, entry in ipairs(vim.split(result.stdout or "", "\n", { trimempty = true })) do
			if unsafe_archive_entry(entry) then return error_result(callback, "unsafe_archive_entry", entry) end
		end
		vim.fn.mkdir(root, "p")
		local extract_handle = vim.system({ "unzip", "-qq", options.source, "-d", root }, { text = true }, vim.schedule_wrap(function(extract_result)
			if op:is_cancelled() then return end
			if extract_result.code ~= 0 then return error_result(callback, "archive_extract_failed", extract_result.stderr) end
			callback(root, nil, function() vim.fn.delete(root, "rf") end)
		end))
		op:set_handle(extract_handle)
	end))
	op:set_handle(list_handle)
	return op, nil
end

local function prepare_remote(options, callback)
	if vim.fn.executable("git") ~= 1 then return nil, { code = "git_missing" } end
	local source = options.source
	if options.provider == "builtin" then source = source or "https://github.com/minecraft-dev/templates.git" end
	if type(source) ~= "string" or source == "" then return nil, { code = "source_missing" } end
	local root = vim.fs.joinpath(vim.fn.stdpath("cache"), "minecraft-dev", "templates", vim.fn.sha256(source))
	vim.fn.mkdir(vim.fs.dirname(root), "p")
	local exists = vim.fn.isdirectory(vim.fs.joinpath(root, ".git")) == 1
	local command = exists and { "git", "-C", root, "pull", "--ff-only" } or { "git", "clone", "--depth", "1", source, root }
	local op = operation()
	local handle = vim.system(command, { text = true }, vim.schedule_wrap(function(result)
		if op:is_cancelled() then return end
		if result.code ~= 0 then return error_result(callback, "remote_update_failed", result.stderr) end
		callback(root, nil)
	end))
	op:set_handle(handle)
	return op, nil
end

---@param options table
---@param callback fun(root: string?, err: table?, cleanup: function?)
---@return table?, table?
function M.prepare(options, callback)
	if options.provider == "archive" then return prepare_archive(options, callback) end
	if options.provider == "remote" or options.provider == "builtin" then return prepare_remote(options, callback) end
	return nil, { code = "unsupported_provider" }
end

return M
