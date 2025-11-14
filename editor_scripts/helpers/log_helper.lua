local INFO_PREFIX = "INFO:EDITOR_SCRIPT: "
local ERROR_PREFIX = "ERROR:EDITOR_SCRIPT: "

local function build_message(prefix, message, path)
	local text = string.format("%s%s", prefix, message or "")
	if path and path ~= "" then
		text = string.format("%s: %s", text, path)
	end
	return text
end

local function normalize_reason(err)
	if err == nil or err == "" then
		return "-"
	end
	return tostring(err)
end

local function info(message, path)
	print(build_message(INFO_PREFIX, message, path))
end

local function error(message, path, err)
	local text = build_message(ERROR_PREFIX, message, path)
	print(string.format("%s Reason: %s", text, normalize_reason(err)))
end

return {
	info = info,
	error = error,
}
