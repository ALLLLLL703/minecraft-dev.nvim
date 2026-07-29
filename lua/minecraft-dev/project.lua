local M = {}
local platforms = require("minecraft-dev.platforms")

local required_fields = {
	"platform",
	"build_system",
	"minecraft_version",
	"directory",
	"group_id",
	"artifact_id",
	"package_name",
	"main_class",
	"language",
}

local function validation_error(code, field)
	return { code = code, field = field }
end

local function is_java_identifier(value)
	return type(value) == "string" and value:match("^[%a_$][%w_$]*$") ~= nil
end

local function is_package_name(value)
	if type(value) ~= "string" or value == "" then
		return false
	end
	for segment in value:gmatch("[^.]+") do
		if not is_java_identifier(segment) then
			return false
		end
	end
	return not value:match("^%.") and not value:match("%.$") and not value:match("%.%.")
end

---@param spec table
---@return table?, table?
function M.validate(spec)
	if type(spec) ~= "table" then
		return nil, validation_error("invalid_spec")
	end

	for _, field in ipairs(required_fields) do
		if type(spec[field]) ~= "string" or spec[field] == "" then
			return nil, validation_error("missing_field", field)
		end
	end

	if not platforms.get(spec.platform) then
		return nil, validation_error("unsupported_platform", "platform")
	end
	if not platforms.supports(spec.platform, spec.build_system) then
		return nil, validation_error("unsupported_build", "build_system")
	end
	if not is_package_name(spec.group_id) or not is_package_name(spec.package_name) then
		return nil, validation_error("invalid_package", "package_name")
	end
	if not is_java_identifier(spec.main_class) then
		return nil, validation_error("invalid_main_class", "main_class")
	end
	if not spec.artifact_id:match("^[%w_.-]+$") then
		return nil, validation_error("invalid_artifact_id", "artifact_id")
	end
	if spec.language ~= "java" and spec.language ~= "kotlin" then
		return nil, validation_error("unsupported_language", "language")
	end
	if spec.platform == "fabric" and require("minecraft-dev.version").resolve_family(spec.minecraft_version) ~= "v1_13_plus" then
		return nil, validation_error("unsupported_version", "minecraft_version")
	end
	if spec.platform == "fabric" and spec.language == "kotlin" then
		local fabric_versions = spec.fabric_version_data or {}
		local defaults = require("minecraft-dev").config.defaults.fabric.version_data
		local kotlin_loader = spec.kotlin_loader_version or fabric_versions.kotlin_loader or defaults.kotlin_loader
		if type(kotlin_loader) ~= "string" or not kotlin_loader:match("^[%w_.-]+%+kotlin%.[%w_.-]+$") then
			return nil, validation_error("invalid_version", "kotlin_loader_version")
		end
	end
	if spec.waterfall_version ~= nil and (type(spec.waterfall_version) ~= "string" or spec.waterfall_version == "") then
		return nil, validation_error("invalid_version", "waterfall_version")
	end
	if spec.platform == "forge" or spec.platform == "neoforge" then
		if spec.language ~= "java" then
			return nil, validation_error("unsupported_language", "language")
		end
		if type(spec.loader_version) ~= "string" or spec.loader_version == "" then
			return nil, validation_error("missing_field", "loader_version")
		end
		if not spec.artifact_id:match("^[a-z][a-z0-9_]+$") then
			return nil, validation_error("invalid_mod_id", "artifact_id")
		end
	end
	if spec.platform == "architectury" then
		if spec.language ~= "java" then
			return nil, validation_error("unsupported_language", "language")
		end
		for _, field in ipairs({ "fabric_loader_version", "fabric_api_version", "forge_version", "architectury_api_version" }) do
			if type(spec[field]) ~= "string" or spec[field] == "" then
				return nil, validation_error("missing_field", field)
			end
		end
	end

	return vim.deepcopy(spec), nil
end

local function directory_is_empty(path)
	local scan = vim.uv.fs_scandir(path)
	return scan ~= nil and vim.uv.fs_scandir_next(scan) == nil
end

---@param spec table
---@param callback? fun(result: table)
---@return table
function M.generate(spec, callback)
	return M.generate_async(spec, callback)
end

---@param spec table
---@param callback? fun(result: table)
---@return table
function M.generate_async(spec, callback)
	local operation = { status = "pending" }
	local normalized, validation_err = M.validate(spec)
	local staging_path
	local lock_path
	local generation_lock
	local child
	local function finish(result)
		if operation.status ~= "pending" then return end
		operation.status = result.status
		operation.result = result
		if staging_path and result.status ~= "generated" then vim.fn.delete(staging_path, "rf") end
		if generation_lock then
			local released, release_err = generation_lock.release()
			generation_lock = nil
			if not released then result.cleanup_error = { code = "lock_cleanup_failed", detail = release_err } end
		end
		if callback then vim.schedule(function() callback(result) end) end
	end
	function operation.cancel()
		if operation.status ~= "pending" or operation.cancel_requested then return end
		operation.cancel_requested = true
		if child and child.on_complete then child.on_complete(function() finish({ status = "cancelled" }) end) end
		if child and child.cancel then
			child.cancel()
		elseif not child or not child.on_complete then
			finish({ status = "cancelled" })
		end
	end

	if not normalized then
		finish({ status = "failed", error = validation_err })
		return operation
	end
	local target = vim.fs.normalize(normalized.directory)
	local target_lstat = vim.uv.fs_lstat(target)
	if target_lstat and target_lstat.type == "link" then
		finish({ status = "failed", error = { code = "destination_symlink", field = "directory" } })
		return operation
	end
	local prepared, prepare_err = pcall(vim.fn.mkdir, vim.fs.dirname(target), "p")
	if not prepared then
		finish({ status = "failed", error = { code = "destination_prepare_failed", detail = prepare_err } })
		return operation
	end
	local real_parent = vim.uv.fs_realpath(vim.fs.dirname(target))
	if not real_parent then
		finish({ status = "failed", error = { code = "destination_prepare_failed" } })
		return operation
	end
	target = vim.fs.joinpath(real_parent, vim.fs.basename(target))
	local target_stat = vim.uv.fs_stat(target)
	local target_existed = target_stat ~= nil
	if target_existed and not directory_is_empty(target) then
		finish({ status = "failed", error = { code = "destination_not_empty", field = "directory" } })
		return operation
	end
	lock_path = target .. ".minecraft-dev.lock"
	local lock_error
	generation_lock, lock_error = require("minecraft-dev.util.lock").acquire(lock_path)
	if not generation_lock then
		finish({ status = "failed", error = lock_error })
		return operation
	end
	staging_path = target .. ".minecraft-dev-" .. tostring(vim.uv.hrtime())
	prepared, prepare_err = pcall(vim.fn.mkdir, staging_path, "p")
	if not prepared then
		finish({ status = "failed", error = { code = "destination_prepare_failed", detail = prepare_err } })
		return operation
	end

	local function commit(warnings)
		if operation.status ~= "pending" or operation.cancel_requested then return end
		local target_lstat_now = vim.uv.fs_lstat(target)
		local target_stat_now = vim.uv.fs_stat(target)
		local target_exists_now = target_stat_now ~= nil
		local identity_changed = target_existed and target_stat_now and target_stat
			and ((target_stat.dev and target_stat_now.dev and target_stat.dev ~= target_stat_now.dev)
				or (target_stat.ino and target_stat_now.ino and target_stat.ino ~= target_stat_now.ino))
		if (target_lstat_now and target_lstat_now.type == "link")
			or target_exists_now ~= target_existed
			or identity_changed
			or (target_exists_now and not directory_is_empty(target))
		then
			finish({ status = "failed", error = { code = "destination_changed" } })
			return
		end
		local backup_path
		if target_exists_now then
			backup_path = staging_path .. ".previous"
			local moved, backup_err = vim.uv.fs_rename(target, backup_path)
			if not moved then
				finish({ status = "failed", error = { code = "destination_commit_failed", detail = backup_err } })
				return
			end
			if not directory_is_empty(backup_path) then
				local restored, restore_err = vim.uv.fs_rename(backup_path, target)
				if not restored then finish({ status = "failed", error = { code = "destination_rollback_failed", detail = restore_err } }); return end
				finish({ status = "failed", error = { code = "destination_changed" } })
				return
			end
		end
		local ok, rename_err = vim.uv.fs_rename(staging_path, target)
		if not ok then
			if backup_path then
				local restored, restore_err = vim.uv.fs_rename(backup_path, target)
				if not restored then
					finish({ status = "failed", error = { code = "destination_rollback_failed", detail = { commit = rename_err, rollback = restore_err } } })
					return
				end
			end
			finish({ status = "failed", error = { code = "destination_commit_failed", detail = rename_err } })
			return
		end
		if backup_path and vim.fn.delete(backup_path, "rf") ~= 0 then
			local displaced = vim.uv.fs_rename(target, staging_path)
			local restored, restore_err = vim.uv.fs_rename(backup_path, target)
			if not displaced or not restored then
				finish({ status = "failed", error = { code = "destination_rollback_failed", detail = restore_err } })
				return
			end
			finish({ status = "failed", error = { code = "destination_backup_cleanup_failed" } })
			return
		end
		staging_path = nil
		require("minecraft-dev.util.notify").notify(vim.log.levels.INFO, { "project", "generated" }, target)
		finish({ status = "generated", path = target, warnings = warnings })
	end

	local function run_generator(warnings)
		normalized.directory = staging_path
		local platform = assert(platforms.get(normalized.platform))
		local ok, result = pcall(
			require(platform.generator).run,
			normalized.build_system,
			staging_path,
			normalized.minecraft_version,
			normalized,
			normalized.platform
		)
		if not ok then
			finish({ status = "failed", error = { code = "generation_failed", detail = result } })
			return
		end
		child = result
		if type(result) == "table" and result.on_complete then
			result.on_complete(function(wrapper_result)
				if wrapper_result.status == "generated" then commit(warnings) else finish(wrapper_result) end
			end)
			return
		end
		if result == true then
			commit(warnings)
		else
			finish({ status = "failed", error = { code = "invalid_generator_result" } })
		end
	end

	if normalized.platform == "fabric" and not normalized.fabric_version_data then
		local started, fetch_operation = pcall(require("minecraft-dev.generators.fabric.version_data").resolve, normalized.minecraft_version, function(data, fetch_error)
			normalized.fabric_version_data = data
			run_generator(fetch_error and { fetch_error } or nil)
		end)
		if not started then
			finish({ status = "failed", error = { code = "version_resolution_failed", detail = fetch_operation } })
			return operation
		end
		if operation.status == "pending" and not child then child = fetch_operation end
	elseif normalized.platform == "waterfall" and not normalized.waterfall_version then
		local started, fetch_operation, fetch_error = pcall(
			require("minecraft-dev.generators.plugin.version_data").resolve_waterfall_version,
			normalized.minecraft_version,
			function(version, fetch_error)
				if not version then
					if fetch_error and fetch_error.code == "cancelled" then finish({ status = "cancelled" })
					else finish({ status = "failed", error = { code = "version_resolution_failed", detail = fetch_error } }) end
					return
				end
				normalized.waterfall_version = version
				run_generator()
			end
		)
		if not started or not fetch_operation then
			finish({ status = "failed", error = { code = "version_resolution_failed", detail = started and fetch_error or fetch_operation } })
			return operation
		end
		if operation.status == "pending" and not child then child = fetch_operation end
	else
		run_generator()
	end
	return operation
end

return M
