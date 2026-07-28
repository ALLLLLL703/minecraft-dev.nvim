local M = {}

local function error_result(callback, code, detail)
	callback(nil, { code = code, detail = detail })
end

local function operation()
	local state = { handle = nil }
	local op = { status = "pending", callbacks = {} }
	function op.set_handle(handle) state.handle = handle end
	function op.on_complete(callback)
		if op.result then callback(op.result) else table.insert(op.callbacks, callback) end
		return op
	end
	function op.finish(result)
		if op.status ~= "pending" then return end
		op.status = result.status
		op.result = result
		for _, callback in ipairs(op.callbacks) do callback(result) end
		op.callbacks = {}
	end
	function op.cancel()
		if op.status ~= "pending" or op.cancel_requested then return end
		op.cancel_requested = true
		if state.handle then state.handle:kill(15) else op.finish({ status = "cancelled" }) end
	end
	function op.is_cancelled() return op.cancel_requested == true end
	return op
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
	if type(options.source) ~= "string" or options.source == "" then return nil, { code = "source_missing" } end
	local op = operation()
	local root = vim.fn.tempname()
	local list_handle = vim.system({ "unzip", "-Z1", options.source }, { text = true }, vim.schedule_wrap(function(result)
		if op.is_cancelled() then op.finish({ status = "cancelled" }) return end
		if result.code ~= 0 then error_result(callback, "archive_list_failed", result.stderr); op.finish({ status = "failed" }) return end
		for _, entry in ipairs(vim.split(result.stdout or "", "\n", { trimempty = true })) do
			if unsafe_archive_entry(entry) then error_result(callback, "unsafe_archive_entry", entry); op.finish({ status = "failed" }); return end
		end
		vim.fn.mkdir(root, "p")
		local extract_handle = vim.system({ "unzip", "-qq", options.source, "-d", root }, { text = true }, vim.schedule_wrap(function(extract_result)
			if op.is_cancelled() then vim.fn.delete(root, "rf"); op.finish({ status = "cancelled" }); return end
			if extract_result.code ~= 0 then vim.fn.delete(root, "rf"); error_result(callback, "archive_extract_failed", extract_result.stderr); op.finish({ status = "failed" }); return end
			callback(root, nil, function() vim.fn.delete(root, "rf") end)
			op.finish({ status = "generated" })
		end))
		op.set_handle(extract_handle)
	end))
	op.set_handle(list_handle)
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
	local clone_root = root .. ".clone-" .. tostring(vim.uv.os_getpid()) .. "-" .. tostring(vim.uv.hrtime())
	local command = exists and { "git", "-C", root, "pull", "--ff-only" }
		or { "git", "clone", "--depth", "1", source, clone_root }
	local op = operation()
	local handle = vim.system(command, { text = true }, vim.schedule_wrap(function(result)
		if op.is_cancelled() then
			if not exists then vim.fn.delete(clone_root, "rf") end
			op.finish({ status = "cancelled" })
			return
		end
		if result.code ~= 0 then
			if not exists then vim.fn.delete(clone_root, "rf") end
			error_result(callback, "remote_update_failed", result.stderr)
			op.finish({ status = "failed" })
			return
		end
		if not exists then
			if vim.fn.isdirectory(vim.fs.joinpath(root, ".git")) == 1 then
				vim.fn.delete(clone_root, "rf")
			else
				local published, publish_err = vim.uv.fs_rename(clone_root, root)
				if not published then
					vim.fn.delete(clone_root, "rf")
					error_result(callback, "remote_publish_failed", publish_err)
					op.finish({ status = "failed" })
					return
				end
			end
		end
		callback(root, nil)
		op.finish({ status = "generated" })
	end))
	op.set_handle(handle)
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
