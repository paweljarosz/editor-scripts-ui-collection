local file_helper = require "editor_scripts.helpers.file_helper"
local string_helper = require "editor_scripts.helpers.string_helper"
local os_helper = require "editor_scripts.helpers.os_helper"

local M = {}

local function command_available(command)
	if not command or command == "" then
		return false
	end
	return pcall(function()
		editor.execute(command, "-version", {
			out = "discard",
			err = "discard",
			reload_resources = false,
		})
	end)
end

local function normalize_candidate(path)
	if not path or path == "" then
		return nil
	end
	if path:sub(1, 1) == "/" then
		return "." .. path
	end
	return path
end

local function detect_executable(default_command, candidates)
	if command_available(default_command) then
		return default_command
	end
	for _, candidate in ipairs(candidates or {}) do
		local normalized = normalize_candidate(candidate)
		if normalized and command_available(normalized) then
			return normalized
		end
	end
	return default_command
end

local FFMPEG_CANDIDATES_WIN = {
	"/editor_scripts/bin/win32/ffmpeg.exe",
	"/editor_scripts/bin/win64/ffmpeg.exe",
}

local FFPLAY_CANDIDATES_WIN = {
	"/editor_scripts/bin/win32/ffplay.exe",
	"/editor_scripts/bin/win64/ffplay.exe",
}

local FFPROBE_CANDIDATES_WIN = {
	"/editor_scripts/bin/win32/ffprobe.exe",
	"/editor_scripts/bin/win64/ffprobe.exe",
}

local FFMPEG_CANDIDATES_LINUX = {
	"/editor_scripts/bin/linux/ffmpeg",
}

local FFPLAY_CANDIDATES_LINUX = {
	"/editor_scripts/bin/linux/ffplay",
}

local FFPROBE_CANDIDATES_LINUX = {
	"/editor_scripts/bin/linux/ffprobe",
}

local FFMPEG_CANDIDATES_MAC = {
	"/editor_scripts/bin/macos/ffmpeg",
}

local FFPLAY_CANDIDATES_MAC = {
	"/editor_scripts/bin/macos/ffplay",
}

local FFPROBE_CANDIDATES_MAC = {
	"/editor_scripts/bin/macos/ffprobe",
}

local platform = os_helper.platform()
local IS_WINDOWS = os_helper.is_windows()
local IS_MAC = os_helper.is_macos()
local IS_LINUX = os_helper.is_linux()
local FFMPEG_PATH
local FFPLAY_PATH
local FFPROBE_PATH

if IS_WINDOWS then
	FFMPEG_PATH = detect_executable("ffmpeg.exe", FFMPEG_CANDIDATES_WIN)
	FFPLAY_PATH = detect_executable("ffplay.exe", FFPLAY_CANDIDATES_WIN)
	FFPROBE_PATH = detect_executable("ffprobe.exe", FFPROBE_CANDIDATES_WIN)
elseif IS_MAC then
	FFMPEG_PATH = detect_executable("ffmpeg", FFMPEG_CANDIDATES_MAC)
	FFPLAY_PATH = detect_executable("ffplay", FFPLAY_CANDIDATES_MAC)
	FFPROBE_PATH = detect_executable("ffprobe", FFPROBE_CANDIDATES_MAC)
elseif IS_LINUX then
	FFMPEG_PATH = detect_executable("ffmpeg", FFMPEG_CANDIDATES_LINUX)
	FFPLAY_PATH = detect_executable("ffplay", FFPLAY_CANDIDATES_LINUX)
	FFPROBE_PATH = detect_executable("ffprobe", FFPROBE_CANDIDATES_LINUX)
else
	FFMPEG_PATH = "ffmpeg"
	FFPLAY_PATH = "ffplay"
	FFPROBE_PATH = "ffprobe"
end

local function normalize_resource_path(path)
	if not path or path == "" then
		return ""
	end
	if path:sub(1, 1) == "." then
		return path
	end
	if path:sub(1, 1) == "/" then
		return "." .. path
	end
	local with_slash = string_helper.path_with_leading_slash(path)
	if with_slash == "" then
		return path
	end
	return "." .. with_slash
end

function M.is_windows()
	return IS_WINDOWS
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

function M.play_sound_blocking(sound_path)
	local normalized = normalize_resource_path(sound_path)
	return pcall(function()
		return editor.execute(
			FFPLAY_PATH,
			"-autoexit",
			"-nodisp",
			"-hide_banner",
			normalized,
			{
				reload_resources = false,
				out = "discard",
				err = "discard",
			}
		)
	end)
end

function M.is_ffplay_running()
	local platform = editor.platform
	if platform == "x86_64-win32" then
		-- Windows
		local success, output = pcall(function()
			return editor.execute('tasklist', '/FI', 'IMAGENAME eq ffplay.exe', '/NH', {
				out = "capture",
				err = "stdout",
				reload_resources = false,
			})
		end)
		return success and output and output:find("ffplay.exe") ~= nil
	else
		-- Linux (MacOS?)
		local success, output = pcall(function()
			return editor.execute('pgrep', 'ffplay', {
				out = "capture",
				err = "stdout",
				reload_resources = false,
			})
		end)
		return success and output and output ~= ""
	end
end

-- Execute command to kill FFplay process
function M.execute_kill_ffplay()
	if not M.is_ffplay_running() then
		print("FFplay is not running, no need to kill it.")
		return true
	end

	local result = pcall(function()
		editor.execute('taskkill', '/F', '/IM', 'ffplay.exe')
	end)

	if not result then
		local error_message = "Unknown error occurred while killing ffplay."
		error("Failed to kill ffplay: " .. error_message)
		return false, error_message
	end

	return true
end

-- Function to get the duration of the audio file using ffprobe
function M.get_audio_duration(sound_path)
	sound_path = normalize_resource_path(sound_path)
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
	input_path = normalize_resource_path(input_path)
	output_path = normalize_resource_path(output_path)

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

-- Function to convert audio using FFmpeg
function M.convert_audio(input_path, output_path, output_format)
	input_path = normalize_resource_path(input_path)
	output_path = normalize_resource_path(output_path)

	-- Define FFmpeg parameters for different formats and execute command
	local success, result = pcall(function()
		if output_format == "ogg" then
			-- OGG format conversion with Defold-compatible parameters
			return editor.execute(
				FFMPEG_PATH,
				"-y",
				"-loglevel", "error",
				"-i", input_path,
				"-ar", "44100",  -- Set sample rate to 44100 Hz
				"-ac", "2",      -- Set number of audio channels to 2
				"-b:a", "192k",  -- Set audio bitrate
				output_path,
				{
					reload_resources = true,
					out = "capture",
					err = "stdout"
				}
			)
		elseif output_format == "wav" then
			-- WAV format conversion with Defold-compatible parameters
			return editor.execute(
			FFMPEG_PATH,
				"-y",
				"-loglevel", "error",
				"-i", input_path,
				"-ar", "44100",  -- Set sample rate to 44100 Hz
				"-ac", "2",      -- Set number of audio channels to 2
				output_path,
				{
					reload_resources = true,
					out = "capture",
					err = "stdout"
				}
			)
		else
			-- Unsupported format
			return false, "Unsupported output format: " .. output_format
		end
	end)

	return success, result or "FFmpeg execution failed."
end

return M
