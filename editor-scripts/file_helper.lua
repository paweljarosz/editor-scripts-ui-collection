---@class FileHelper
local M = {}

---@param path string|nil
---@return string
local function normalize_path(path)
	if not path or path == "" then
		return ""
	end
	if path:sub(1, 1) == "/" then
		return "." .. path
	end
	return path
end

-- Checks if given file is a supported sound format file
---@param path string
---@return boolean
function M.is_sound_file(path)
	local lower = path:lower()
	return lower:match("%.wav$") ~= nil
	or lower:match("%.ogg$") ~= nil
	or lower:match("%.flac$") ~= nil
	or lower:match("%.mp3$") ~= nil
	or lower:match("%.aac$") ~= nil
end

-- Returns the file name without extension
---@param path string
---@return string|nil
function M.get_file_name_without_extension(path)
	return path:match("([^/\\]+)%.%w+$")
end

-- Returns the file extension
---@param path string
---@return string|nil
function M.get_file_extension(path)
	return path:match("%.([%w]+)$")
end

-- Returns the directory of a file path
---@param path string
---@return string|nil
function M.get_directory(path)
	return path:match("(.*/)")
end

-- Checks if given file exists (resource-aware)
---@param path string
---@return boolean
function M.exists(path)
	local success, output_attrs = pcall(editor.resource_attributes, path)
	if not success or not output_attrs then
		success, output_attrs = pcall(editor.external_file_attributes, path)
	end

	if success and output_attrs then
		return output_attrs.exists == true
	else
		print("Failed to retrieve attributes for path:", path)
		return false
	end
end

-- Checks if a file exists on disk using io.open (after normalization)
---@param path string
---@return boolean
function M.file_exists(path)
	local normalized = normalize_path(path)
	local file = io.open(normalized, "r")
	if file then
		file:close()
		return true
	end
	return false
end

-- Reads entire file contents (binary)
---@param path string
---@return string|nil data
---@return string? err
function M.read_all(path)
	local normalized = normalize_path(path)
	local file, err = io.open(normalized, "rb")
	if not file then
		return nil, err
	end
	local data = file:read("*a")
	file:close()
	return data
end

-- Writes entire content to file (binary)
---@param path string
---@param content string
---@return boolean success
---@return string? err
function M.write_all(path, content)
	local normalized = normalize_path(path)
	local file, err = io.open(normalized, "wb")
	if not file then
		return false, err
	end
	file:write(content)
	file:close()
	return true
end

-- Creates directory at given path if not existing
---@param path string
---@return boolean
function M.create_directory(path)
	local attrs_ok, attrs = pcall(editor.resource_attributes, path)
	if attrs_ok and attrs and attrs.exists then
		return true
	end

	local success, err = pcall(editor.create_directory, path)
	if success then
		print("Directory created using editor API:", path)
		return true
	end

	local fallback_success, fallback_err = os.execute('mkdir "' .. path .. '"')
	if fallback_success then
		print("Directory created using os.execute:", path)
		return true
	end

	print("Failed to create directory with os.execute:", path, "Error:", fallback_err or err)
	return false
end

-- Creates a directory at a given path if not existing (OS only)
---@param path string
---@return boolean
function M.create_directory_2(path)
	if not M.file_exists(path) then
		local success, err = os.execute('mkdir "' .. path .. '"')
		if success then
			print("Directory created using os.execute:", path)
			return true
		else
			print("Failed to create directory with os.execute:", path, "Error:", err)
			return false
		end
	end

	print("Directory already exists:", path)
	return true
end

-- Escape double quotes in paths
---@param input_path string
---@return string
function M.escape(input_path)
	return input_path:gsub('"', '""')
end

-- Escape leading slash in paths
---@param input_path string
---@return string
function M.escape_leading_slash(input_path)
	if input_path:sub(1, 1) == "/" then
		return input_path:sub(2)
	end
	return input_path
end

-- Creates a VBscript file in given directory with given command content
---@param command string
---@param temp_dir string
---@return string
function M.create_vbscript(command, temp_dir)
	local temp_vbs_filename = "temp_ffplay_" .. tostring(os.time()) .. ".vbs"
	local normalized_dir = normalize_path(temp_dir)
	if normalized_dir == "" then
		normalized_dir = "."
	end
	local vbs_script_full_path = normalized_dir .. "/" .. temp_vbs_filename

	local vbs_file, err = io.open(vbs_script_full_path, "w")
	if not vbs_file then
		error("Failed to create VBScript file: " .. tostring(err))
	end
	vbs_file:write(command)
	vbs_file:close()

	return vbs_script_full_path
end

-- Removes file or directory using standard Lua functions
---@param path string
---@return boolean
function M.remove(path)
	local success, err = os.remove(path)
	if success then
		print("Removed file/directory:", path)
		return true
	else
		print("Error removing file/directory:", path, "Error:", err)
		return false
	end
end

---@param path string
---@return boolean
function M.remove_directory_recursive(path)
	if not M.exists(path) then
		return true
	end

	local success, files = pcall(editor.list_files, path)
	if not success then
		print("Error listing files in directory:", path)
		return false
	end

		for _, file in ipairs(files) do
			local file_path = path .. "/" .. file
			local attr = editor.resource_attributes(file_path)

			if attr.type == "directory" then
				if not M.remove_directory_recursive(file_path) then
					return false
				end
			else
				local remove_success = pcall(editor.delete_resource, file_path)
				if not remove_success then
					print("Error removing file:", file_path)
					return false
				end
			end
		end

	local remove_dir_success = pcall(editor.delete_resource, path)
	if not remove_dir_success then
		print("Error removing directory:", path)
		return false
	end

	return true
end

-- Ensures a resource directory exists (uses editor.create_directory)
---@param path string
---@return boolean success
---@return string|nil err
function M.ensure_directory(path)
	if not path or path == "" or path == "." then
		return true
	end

	local resource_path = path
	if resource_path:sub(1, 1) ~= "/" then
		resource_path = "/" .. resource_path
	end

	local success, err = pcall(editor.create_directory, resource_path)
	if not success then
		return false, err
	end

	return true
end

-- Normalizes a project-relative path
---@param path string|nil
---@return string
function M.normalize(path)
	return normalize_path(path)
end

return M
