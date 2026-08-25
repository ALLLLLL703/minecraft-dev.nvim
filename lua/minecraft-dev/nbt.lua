local M = {}

local uv = vim.uv or vim.loop

local function defaults(options)
	local configured = require("minecraft-dev").config.defaults.nbt or {}
	return vim.tbl_extend("force", {
		python = "python3",
		timeout_ms = 10000,
		max_input_bytes = 32 * 1024 * 1024,
		max_output_bytes = 64 * 1024 * 1024,
		max_depth = 128,
		max_tags = 250000,
		max_array_length = 1000000,
		max_string_bytes = 1024 * 1024,
	}, configured, options or {})
end

local function helper_path(options)
	if options.helper_path then
		return options.helper_path
	end
	local source = debug.getinfo(1, "S").source:gsub("^@", "")
	return vim.fs.joinpath(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source))), "scripts", "minecraft-dev-nbt.py")
end

local function command(mode, options)
	local result = {
		options.python,
		helper_path(options),
		mode,
		"--max-input-bytes",
		tostring(options.max_input_bytes),
		"--max-output-bytes",
		tostring(options.max_output_bytes),
		"--max-depth",
		tostring(options.max_depth),
		"--max-tags",
		tostring(options.max_tags),
		"--max-array-length",
		tostring(options.max_array_length),
		"--max-string-bytes",
		tostring(options.max_string_bytes),
	}
	if mode == "encode" then
		vim.list_extend(result, { "--compression", options.compression })
	end
	return result
end

local function failure(code, detail)
	return { status = "failed", error = { code = code, detail = detail or "" } }
end

local function process_error(result)
	if result.code == 124 then
		return failure("timeout", "NBT codec timed out")
	end
	local ok, decoded = pcall(vim.json.decode, result.stderr or "")
	if ok and type(decoded) == "table" and type(decoded.code) == "string" then
		return failure(decoded.code, decoded.detail)
	end
	return failure("codec_failed", vim.trim(result.stderr or "NBT codec failed"))
end

local function parse_decoded(result)
	if result.code ~= 0 then
		return process_error(result)
	end
	local newline = result.stdout:find("\n", 1, true)
	if not newline then
		return failure("codec_failed", "NBT codec returned invalid output")
	end
	local compression = result.stdout:sub(1, newline - 1)
	if compression ~= "none" and compression ~= "gzip" and compression ~= "zlib" then
		return failure("codec_failed", "NBT codec returned an invalid compression type")
	end
	local text = result.stdout:sub(newline + 1)
	local ok = pcall(vim.json.decode, text)
	if not ok then
		return failure("codec_failed", "NBT codec returned invalid JSON")
	end
	return { status = "decoded", compression = compression, text = text }
end

local function run_sync(mode, input, options)
	if vim.fn.executable(options.python) ~= 1 then
		return failure("python_unavailable", options.python)
	end
	if vim.fn.filereadable(helper_path(options)) ~= 1 then
		return failure("helper_unavailable", helper_path(options))
	end
	local started, job = pcall(vim.system, command(mode, options), { stdin = input })
	if not started then
		return failure("codec_failed", job)
	end
	local result = job:wait(options.timeout_ms)
	if mode == "decode" then
		return parse_decoded(result)
	end
	if result.code ~= 0 then
		return process_error(result)
	end
	return { status = "encoded", bytes = result.stdout }
end

---@param bytes string
---@param options? table
---@return table
function M.decode_bytes(bytes, options)
	options = defaults(options)
	if type(bytes) ~= "string" then
		return failure("invalid_input", "NBT input must be a string")
	end
	if #bytes > options.max_input_bytes then
		return failure("size_limit", tostring(options.max_input_bytes))
	end
	return run_sync("decode", bytes, options)
end

---@param text string
---@param options? table
---@return table
function M.encode_text(text, options)
	options = defaults(options)
	options.compression = options.compression or "none"
	if options.compression ~= "none" and options.compression ~= "gzip" and options.compression ~= "zlib" then
		return failure("invalid_compression", tostring(options.compression))
	end
	if type(text) ~= "string" then
		return failure("invalid_text", "NBT text must be a string")
	end
	return run_sync("encode", text, options)
end

---@param bytes string
---@param options? table
---@param callback fun(result: table)
---@return table
function M.decode_async(bytes, options, callback)
	options = defaults(options)
	if type(callback) ~= "function" then
		return failure("callback_required")
	end
	if type(bytes) ~= "string" or #bytes > options.max_input_bytes then
		local result = failure(type(bytes) == "string" and "size_limit" or "invalid_input")
		vim.schedule(function()
			callback(result)
		end)
		return result
	end
	if vim.fn.executable(options.python) ~= 1 or vim.fn.filereadable(helper_path(options)) ~= 1 then
		local result = failure("python_unavailable", options.python)
		vim.schedule(function()
			callback(result)
		end)
		return result
	end
	local completed = false
	local cancelled = false
	local timed_out = false
	local job
	local timer
	local started
	started, job = pcall(vim.system, command("decode", options), { stdin = bytes }, function(result)
		vim.schedule(function()
			if completed then
				return
			end
			completed = true
			if timer then
				timer:stop()
			end
			if cancelled then
				callback({ status = "cancelled" })
			elseif timed_out then
				callback(failure("timeout", "NBT codec timed out"))
			else
				callback(parse_decoded(result))
			end
		end)
	end)
	if not started then
		local result = failure("codec_failed", job)
		vim.schedule(function()
			callback(result)
		end)
		return result
	end
	timer = vim.defer_fn(function()
		if not completed then
			timed_out = true
			job:kill("sigterm")
		end
	end, options.timeout_ms)
	return {
		status = "pending",
		cancel = function()
			if completed then
				return false
			end
			cancelled = true
			timer:stop()
			job:kill("sigterm")
			return true
		end,
	}
end

local function read_file(path, limit)
	local stat = uv.fs_stat(path)
	if not stat or stat.type ~= "file" then
		return nil, failure("file_unavailable", path)
	end
	if stat.size > limit then
		return nil, failure("size_limit", tostring(limit))
	end
	local fd, open_error = uv.fs_open(path, "r", 438)
	if not fd then
		return nil, failure("read_failed", open_error)
	end
	local bytes, read_error = uv.fs_read(fd, stat.size, 0)
	uv.fs_close(fd)
	if not bytes then
		return nil, failure("read_failed", read_error)
	end
	return bytes
end

local function set_text(buffer, text)
	local lines = vim.split(text, "\n", { plain = true })
	if lines[#lines] == "" then
		table.remove(lines)
	end
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
	vim.bo[buffer].modified = false
end

local function create_buffer(path, decoded)
	local buffer = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(buffer, path .. ".nbtt")
	vim.bo[buffer].buftype = "acwrite"
	vim.bo[buffer].bufhidden = "hide"
	vim.bo[buffer].swapfile = false
	vim.bo[buffer].filetype = "json"
	vim.b[buffer].minecraft_dev_nbt = { path = path, compression = decoded.compression }
	set_text(buffer, decoded.text)
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buffer,
		callback = function(event)
			local result = require("minecraft-dev.nbt").save_buffer({ buffer = event.buf })
			if result.status ~= "saved" then
				require("minecraft-dev.util.notify").notify(
					vim.log.levels.ERROR,
					{ "nbt", result.error.code },
					result.error.detail
				)
			end
		end,
	})
	vim.api.nvim_set_current_buf(buffer)
	return { status = "opened", buffer = buffer, path = path, compression = decoded.compression }
end

---@param options? { path?: string, sync?: boolean, callback?: fun(result: table) }
---@return table
function M.open(options)
	options = defaults(options)
	local path = options.path or vim.api.nvim_buf_get_name(0)
	if type(path) ~= "string" or path == "" then
		return failure("path_required")
	end
	path = vim.fs.normalize(path)
	local existing = vim.fn.bufnr(path .. ".nbtt")
	if existing >= 0 and vim.api.nvim_buf_is_loaded(existing) then
		vim.api.nvim_set_current_buf(existing)
		local state = vim.b[existing].minecraft_dev_nbt or {}
		return { status = "opened", buffer = existing, path = path, compression = state.compression }
	end
	local bytes, read_error = read_file(path, options.max_input_bytes)
	if not bytes then
		return read_error or failure("read_failed", path)
	end
	if options.sync then
		local decoded = M.decode_bytes(bytes, options)
		return decoded.status == "decoded" and create_buffer(path, decoded) or decoded
	end
	return M.decode_async(bytes, options, function(decoded)
		local result = decoded.status == "decoded" and create_buffer(path, decoded) or decoded
		if options.callback then
			options.callback(result)
		elseif result.status == "failed" then
			require("minecraft-dev.util.notify").notify(
				vim.log.levels.ERROR,
				{ "nbt", result.error.code },
				result.error.detail
			)
		end
	end)
end

local function atomic_write(path, bytes)
	local suffix = string.format(".minecraft-dev.%d.%d.tmp", uv.os_getpid(), uv.hrtime())
	local temporary = path .. suffix
	local stat = uv.fs_stat(path)
	local mode = stat and bit.band(stat.mode, 511) or 420
	local fd, open_error = uv.fs_open(temporary, "wx", mode)
	if not fd then
		return failure("write_failed", open_error)
	end
	local written, write_error = uv.fs_write(fd, bytes, 0)
	local synced, sync_error
	if written then
		synced, sync_error = uv.fs_fsync(fd)
	end
	uv.fs_close(fd)
	if not written or written ~= #bytes or not synced then
		uv.fs_unlink(temporary)
		return failure("write_failed", write_error or sync_error or "short write")
	end
	local renamed, rename_error = uv.fs_rename(temporary, path)
	if not renamed then
		uv.fs_unlink(temporary)
		return failure("write_failed", rename_error)
	end
	return { status = "saved", path = path }
end

---@param options? { buffer?: integer }
---@return table
function M.save_buffer(options)
	options = defaults(options)
	local buffer = options.buffer or 0
	local state = vim.b[buffer].minecraft_dev_nbt
	if type(state) ~= "table" or type(state.path) ~= "string" then
		return failure("not_nbt_buffer")
	end
	local text = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n") .. "\n"
	local encoded = M.encode_text(text, vim.tbl_extend("force", options, { compression = state.compression }))
	if encoded.status ~= "encoded" then
		return encoded
	end
	local saved = atomic_write(state.path, encoded.bytes)
	if saved.status == "saved" then
		vim.bo[buffer].modified = false
	end
	return saved
end

---@param options? { buffer?: integer, sync?: boolean, callback?: fun(result: table) }
---@return table
function M.reload_buffer(options)
	options = defaults(options)
	local buffer = options.buffer or 0
	local state = vim.b[buffer].minecraft_dev_nbt
	if type(state) ~= "table" or type(state.path) ~= "string" then
		return failure("not_nbt_buffer")
	end
	if vim.bo[buffer].modified and not options.force then
		return failure("modified_buffer")
	end
	local bytes, read_error = read_file(state.path, options.max_input_bytes)
	if not bytes then
		return read_error or failure("read_failed", state.path)
	end
	local function apply(decoded)
		if decoded.status ~= "decoded" then
			return decoded
		end
		set_text(buffer, decoded.text)
		vim.b[buffer].minecraft_dev_nbt = { path = state.path, compression = decoded.compression }
		return { status = "reloaded", buffer = buffer, compression = decoded.compression }
	end
	if options.sync then
		return apply(M.decode_bytes(bytes, options))
	end
	return M.decode_async(bytes, options, function(decoded)
		local result = apply(decoded)
		if options.callback then
			options.callback(result)
		elseif result.status == "failed" then
			require("minecraft-dev.util.notify").notify(
				vim.log.levels.ERROR,
				{ "nbt", result.error.code },
				result.error.detail
			)
		end
	end)
end

return M
