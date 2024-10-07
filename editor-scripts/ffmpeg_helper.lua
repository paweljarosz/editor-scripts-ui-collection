local M = {}

-- Adjust the paths if needed
local FFMPEG_PATH = "C:/ffmpeg/bin/ffmpeg.exe"
local FFPLAY_PATH = "C:/ffmpeg/bin/ffplay.exe"
local FFPROBE_PATH = "C:/ffmpeg/bin/ffprobe.exe"

if editor.platform == "x86_64-win32" then
	FFMPEG_PATH = "C:/ffmpeg/bin/ffmpeg.exe"
	FFPLAY_PATH = "C:/ffmpeg/bin/ffplay.exe"
	FFPROBE_PATH = "C:/ffmpeg/bin/ffprobe.exe"
elseif editor.platform == "x86_64-macos" or editor.platform == "arm64-macos" then
	FFMPEG_PATH = "/usr/local/bin/ffmpeg"
	FFPLAY_PATH = "/usr/local/bin/ffplay"
	FFPROBE_PATH = "/usr/local/bin/ffprobe"
elseif editor.platform == "x86_64-linux" then
	FFMPEG_PATH = "/usr/bin/ffmpeg"
	FFPLAY_PATH = "/usr/bin/ffplay"
	FFPROBE_PATH = "/usr/bin/ffprobe"
end

-- Checks if selected resource is a supported sound format file
function M.execute_play_sound_in_window(sound_path, window_title)
	local sound_file_path = "." .. sound_path -- Assuming project root is current directory
	-- Build the command to start ffplay in a unique window title:
	local command = 'start "'..window_title..'" "'..FFPLAY_PATH..'" "'..sound_file_path..'" -autoexit -nodisp -hide_banner'

	editor.execute('cmd.exe', '/C', command)
end

-- Escape double quotes in paths
local function escape(s)
	return s:gsub('"', '""')
end

-- Create content of a VBScript to run given sound in backgorund using FFplay
function M.create_vbscript_command_ffplay(sound_path)
	return string.format([[
	Set WshShell = CreateObject("WScript.Shell")
	WshShell.Run """%s"" ""%s"" -autoexit -nodisp -hide_banner", 0, False
	]], escape(FFPLAY_PATH), escape(sound_path))
end

-- Execute command to kill FFplay process
function M.execute_kill_ffplay()
	local success, result = pcall(function()
		editor.execute('taskkill', '/F', '/IM', 'ffplay.exe')
	end)

	if not success then
		local error_message = result and result.err or "Unknown error occurred while killing ffplay."
		error("Failed to kill ffplay: " .. tostring(error_message))
		return nil, "Failed to kill ffplay: " .. tostring(error_message)
	end
end

-- Function to get the duration of the audio file using ffprobe
function M.get_audio_duration(sound_path)
	sound_path = sound_path:sub(2)  -- Remove leading slash
	-- Use FFprobe to get the duration
	local success, result = pcall(function()
		return editor.execute(
			FFPROBE_PATH,
			"-v", "error",
			"-show_entries", "format=duration",
			"-of", "default=noprint_wrappers=1:nokey=1",
			sound_path,
			{
				reload_resources = true,
				out = "capture",
				err = "stdout"
			}
		)
	end)

	if not success then
		local error_message = result and result.err or "Unknown error occurred while executing ffprobe."
		return nil, "Failed to get audio duration: " .. tostring(error_message)
	end

	-- The duration should be in result
	if not result then
		return nil, "FFprobe did not return any duration information."
	end

	-- Trim any whitespace
	result = result:match("^%s*(.-)%s*$")

	-- Convert duration to number
	local duration = tonumber(result)
	if not duration then
		return nil, "Failed to parse audio duration: " .. tostring(result)
	end

	return duration, nil
end

-- Function to extract a subtrack using FFmpeg
function M.extract_subtrack(input_path, output_path, start_time, end_time)
	input_path = input_path:sub(2)  -- Remove leading slash
	-- Remove leading slash from input_path and output_path if present
	input_path = input_path:gsub("^/", "")
	output_path = output_path:gsub("^/", "")

	print("Executing FFmpeg command")
	print("FFMPEG_PATH:", FFMPEG_PATH)
	print("Input:", input_path)
	print("Output:", output_path)
	print("Start time:", start_time)
	print("End time:", end_time)

	-- Execute the FFmpeg command
	local success, result = pcall(function()
		return editor.execute(FFMPEG_PATH,
			"-y",
			"-i", input_path,
			"-ss", tostring(start_time),
			"-to", tostring(end_time),
			"-c", "copy",
			output_path,
			{
				reload_resources = true,
				out = "discard",
				err = "discard"
			}
		)
	end)

	print("FFmpeg execution result:", success, result)

	if success then
		if result then  -- Check if result is not nil
			return true, result
		else
			return true, "FFmpeg executed successfully, but no output was captured."
		end
	else
		local error_message = "FFmpeg execution failed.\n"
		error_message = error_message .. "Error: " .. tostring(result) .. "\n"
		return false, error_message
	end
end


-- Check if a process is running
function M.is_process_running(process_name)
	local platform = editor.platform
	if platform == "x86_64-win32" then
		-- Use tasklist and findstr to check for process on Windows
		local success, output = pcall(function()
			return editor.execute('cmd.exe', '/C', 'tasklist | findstr ' .. process_name, {
				out = "capture",
				err = "stdout",
				reload_resources = false,
			})
		end)
		return success and output and output:find(process_name) ~= nil
	else
		-- Use pgrep for Unix-based systems
		local success, output = pcall(function()
			return editor.execute('pgrep', process_name, {
				out = "capture",
				err = "stdout",
				reload_resources = false,
			})
		end)
		return success and output and output ~= ""
	end
end


return M