local platform = editor.platform or ""

local M = {}

function M.is_windows()
	return platform == "x86_64-win32"
end

function M.is_macos()
	return platform == "x86_64-macos" or platform == "arm64-macos"
end

function M.is_linux()
	return not M.is_windows() and not M.is_macos()
end

function M.platform()
	return platform
end

return M
