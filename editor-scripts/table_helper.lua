---@class TableHelper
local M = {}

-- Shallow copy for single tables; returns {} when source is nil.
---@param source table|nil
---@return table
function M.clone_table(source)
	if not source then
		return {}
	end
	local target = {}
	for key, value in pairs(source) do
		target[key] = value
	end
	return target
end

-- Clones a single list item, leaving non-table values untouched.
---@generic T
---@param item T
---@return T
function M.clone_item(item)
	if type(item) ~= "table" then
		return item
	end
	local copy = {}
	for key, value in pairs(item) do
		copy[key] = value
	end
	return copy
end

-- Clones an array-like table using the provided per-item clone operation.
---@generic T
---@param list T[]|nil
---@param clone_item_fn fun(item:T):T|nil
---@return T[]
function M.clone_list(list, clone_item_fn)
	local clone = {}
	local item_clone = clone_item_fn or M.clone_item
	for index, item in ipairs(list or {}) do
		clone[index] = item_clone(item)
	end
	return clone
end

return M
