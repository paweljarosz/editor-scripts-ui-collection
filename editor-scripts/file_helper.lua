local M = {}

-- Checks if given file is a supported sound format file
function M.is_sound_file(path)
	return path:lower():match("%.wav$")
	or path:lower():match("%.ogg$")
	or path:lower():match("%.flac$")
	or path:lower():match("%.mp3$")
	or path:lower():match("%.aac")
end

-- Returns the file name without extension
function M.get_file_name_without_extension(path)
	return path:match("([^/\\]+)%.%w+$")
end

-- Returns the file extension
function M.get_file_extension(path)
	return path:match("%.([%w]+)$")
end

-- Returns the directory of a file path
function M.get_directory(path)
	return path:match("(.*/)")
end

-- Checks if given file exists
function M.exists(path)
	local success, output_attrs = pcall(editor.resource_attributes, path)
	if not success or not output_attrs then
		success, output_attrs = pcall(editor.external_file_attributes, path)
	end

	if success and output_attrs then
		return output_attrs.exists
	else
		print("Failed to retrieve attributes for path:", path)
		return false
	end
end


function M.file_exists(path)
	local file = io.open(path, "r")
	if file then
		file:close()
		return true
	else
		return false
	end
end

-- Creates directory at given path if not existing
function M.create_directory(path)
	-- First try to use Defold's editor API for resource paths
	if not (editor.resource_attributes(path) and editor.resource_attributes(path).exists) then
		local success = pcall(editor.create_directory, path)
		if not success then
			-- Fallback to using os.execute if the path isn't a recognized resource path
			local fallback_success, err = os.execute('mkdir "' .. path .. '"')
			if fallback_success then
				print("Directory created using os.execute:", path)
			else
				print("Failed to create directory with os.execute:", path, "Error:", err)
			end
		else
			print("Directory created using editor API:", path)
		end
	end
end

-- Creates a directory at a given path if not existing
function M.create_directory_2(path)
	-- Check if the path exists using Lua's `io` functions
	if not M.file_exists(path) then
		-- Attempt to create the directory using Lua's `os.execute`
		local success, err = os.execute('mkdir "' .. path .. '"')
		if success then
			print("Directory created using os.execute:", path)
		else
			print("Failed to create directory with os.execute:", path, "Error:", err)
		end
	else
		print("Directory already exists:", path)
	end
end

-- Escape double quotes in paths
function M.escape(input_path)
	return input_path:gsub('"', '""')
end

-- Escape leading slash in paths
function M.escape_leading_slash(input_path)
	return ( (input_path:sub(1, 1) == "/") and input_path:sub(2) or input_path )
end

-- Creates a VBscript file in given directory with given command content
function M.create_vbscript(command, temp_dir)
	-- Create a unique temporary filename in temporary directory
	local temp_vbs_filename = 'temp_ffplay_'..tostring(os.time())..'.vbs'
	local vbs_script_full_path = "."..temp_dir..'/'..temp_vbs_filename

	-- Write the VBScript file
	local vbs_file, err = io.open(vbs_script_full_path, "w")
	if not vbs_file then
		error("Failed to create VBScript file: " .. tostring(err))
	end
	vbs_file:write(command)
	vbs_file:close()

	return vbs_script_full_path
end

-- Removes file or directory using standard Lua functions
function M.remove(path)
	local error = os.remove(path)
	if not error then
		print("Removed file/directory:", path)
		return true
	else
		print("Error removing file/directory:", path, "Error:", error)
		return false
	end
end

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

	-- Remove empty catalog
	local remove_dir_success = pcall(editor.delete_resource, path)
	if not remove_dir_success then
		print("Error removing directory:", path)
		return false
	end

	return true
end

return M