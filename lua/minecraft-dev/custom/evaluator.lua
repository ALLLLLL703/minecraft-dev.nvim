local M = {}

local function trim(value)
	return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function resolve(properties, reference)
	reference = reference:gsub("^%$", ""):gsub("^%{", ""):gsub("%}$", "")
	local minecraft_constant = reference:match("^mcver%.MC(.+)$")
	if minecraft_constant then return minecraft_constant:gsub("_", ".") end
	local current = properties
	for segment in reference:gmatch("[%w_]+") do
		if type(current) ~= "table" then
			return nil
		end
		current = current[segment]
	end
	return current
end

local function compare_versions(left, right)
	local function parts(value)
		local output = {}
		for part in tostring(value or ""):gmatch("%d+") do table.insert(output, tonumber(part)) end
		return output
	end
	local left_parts, right_parts = parts(left), parts(right)
	for index = 1, math.max(#left_parts, #right_parts) do
		local difference = (left_parts[index] or 0) - (right_parts[index] or 0)
		if difference < 0 then return -1 elseif difference > 0 then return 1 end
	end
	return 0
end

local function find_operator(expression, operator)
	local depth = 0
	local quote = nil
	local index = 1
	while index <= #expression - #operator + 1 do
		local character = expression:sub(index, index)
		if quote then
			if character == quote and expression:sub(index - 1, index - 1) ~= "\\" then quote = nil end
		elseif character == '"' or character == "'" then
			quote = character
		elseif character == "(" then
			depth = depth + 1
		elseif character == ")" then
			depth = depth - 1
		elseif depth == 0 and expression:sub(index, index + #operator - 1) == operator then
			return index
		end
		index = index + 1
	end
end

local function strip_parentheses(expression)
	while expression:sub(1, 1) == "(" and expression:sub(-1) == ")" do
		local depth = 0
		local wraps = true
		for index = 1, #expression do
			local character = expression:sub(index, index)
			if character == "(" then depth = depth + 1 elseif character == ")" then depth = depth - 1 end
			if depth == 0 and index < #expression then wraps = false break end
		end
		if not wraps then break end
		expression = trim(expression:sub(2, -2))
	end
	return expression
end

local evaluate

evaluate = function(properties, expression)
	expression = strip_parentheses(trim(expression))
	for _, operator in ipairs({ "||", "&&", "==", "!=", ">=", "<=", ">", "<" }) do
		local index = find_operator(expression, operator)
		if index then
			local left = evaluate(properties, expression:sub(1, index - 1))
			local right = evaluate(properties, expression:sub(index + #operator))
			if operator == "||" then return not not left or not not right end
			if operator == "&&" then return not not left and not not right end
			if operator == "==" then return left == right end
			if operator == "!=" then return left ~= right end
			if operator == ">=" then return left >= right end
			if operator == "<=" then return left <= right end
			if operator == ">" then return left > right end
			return left < right
		end
	end
	local receiver, argument = expression:match("^(.-)%.compareTo%s*%((.*)%)$")
	if receiver then return compare_versions(evaluate(properties, receiver), evaluate(properties, argument)) end
	receiver, argument = expression:match("^(.-)%.contains%s*%((.*)%)$")
	if receiver then return tostring(evaluate(properties, receiver)):find(tostring(evaluate(properties, argument)), 1, true) ~= nil end
	local semver_method, semver_arguments = expression:match("^%$semver%.([%w_]+)%((.*)%)$")
	if semver_method then
		local values = {}
		for value in semver_arguments:gmatch("[^,]+") do table.insert(values, tostring(evaluate(properties, value))) end
		return table.concat(values, ".")
	end
	if expression:sub(1, 1) == "!" then return not evaluate(properties, expression:sub(2)) end
	if expression == "true" then return true end
	if expression == "false" then return false end
	if expression == "null" or expression == "$null" then return nil end
	if expression:match("^[-+]?%d+%.?%d*$") then return tonumber(expression) end
	local quote = expression:sub(1, 1)
	if (quote == '"' or quote == "'") and expression:sub(-1) == quote then return expression:sub(2, -2) end
	if expression:sub(1, 1) == "$" then return resolve(properties, expression) end
	return expression
end

---@param properties table
---@param expression string
---@return any
function M.expression(properties, expression)
	return evaluate(properties, expression)
end

---@param properties table
---@param content string
---@return string
function M.interpolate(properties, content)
	content = content:gsub("%${([%w_%.]+)}", function(reference)
		local value = resolve(properties, reference)
		return value == nil and "" or tostring(value)
	end)
	content = content:gsub("%$([%a_][%w_%.]*)", function(reference)
		local value = resolve(properties, reference)
		return value == nil and "$" .. reference or tostring(value)
	end)
	return content
end

local function parse_lines(content)
	local lines = {}
	for line, newline in content:gmatch("([^\n]*)(\n?)") do
		if line == "" and newline == "" then break end
		table.insert(lines, { text = line, newline = newline })
	end
	return lines
end

local render_range

local function find_block_end(lines, index)
	local depth = 1
	while index <= #lines do
		local directive = lines[index].text:match("^%s*#([%a]+)")
		if directive == "if" or directive == "foreach" then
			depth = depth + 1
		elseif directive == "end" then
			depth = depth - 1
			if depth == 0 then return index end
		end
		index = index + 1
	end
	return #lines + 1
end

render_range = function(lines, index, properties, stops)
	local output = {}
	while index <= #lines do
		local line = lines[index]
		local directive, argument = line.text:match("^%s*#([%a]+)%s*%((.*)%)%s*$")
		local bare = line.text:match("^%s*#([%a]+)%s*$")
		directive = directive or bare
		if directive and stops and stops[directive] then return table.concat(output), index, directive, argument end
		if directive == "if" then
			local selected = nil
			local matched = false
			local condition = argument
			index = index + 1
			while true do
				local branch, next_index, stop, stop_argument = render_range(lines, index, vim.deepcopy(properties), { ["elseif"] = true, ["else"] = true, ["end"] = true })
				if not matched and M.expression(properties, condition) then selected, matched = branch, true end
				if stop == "elseif" then condition, index = stop_argument, next_index + 1
				elseif stop == "else" then
					local fallback, end_index = render_range(lines, next_index + 1, vim.deepcopy(properties), { ["end"] = true })
					if not matched then selected = fallback end
					index = end_index + 1
					break
				else index = next_index + 1 break end
			end
			table.insert(output, selected or "")
		elseif directive == "foreach" then
			local variable, collection = argument:match("^%s*%${?([%w_]+)}?%s+in%s+%${?([%w_%.]+)}?%s*$")
			local end_index = find_block_end(lines, index + 1)
			if variable and collection then
				local values = resolve(properties, collection) or {}
				local body = {}
				for body_index = index + 1, end_index - 1 do table.insert(body, lines[body_index]) end
				for _, value in ipairs(values) do
					local iteration_properties = vim.deepcopy(properties)
					iteration_properties[variable] = value
					table.insert(output, (render_range(body, 1, iteration_properties)))
				end
			end
			index = end_index + 1
		elseif directive == "set" then
			local name, expression = argument:match("^%s*%$([%w_]+)%s*=%s*(.-)%s*$")
			if name then properties[name] = M.expression(properties, expression) end
			index = index + 1
		else
			table.insert(output, M.interpolate(properties, line.text) .. line.newline)
			index = index + 1
		end
	end
	return table.concat(output), index
end

---@param properties table
---@param content string
---@return string
function M.render(properties, content)
	return (render_range(parse_lines(content), 1, vim.deepcopy(properties)))
end

return M
