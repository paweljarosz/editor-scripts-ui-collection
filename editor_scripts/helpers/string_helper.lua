local M = {}

---@param path string|nil
---@return string
function M.path_with_leading_slash(path)
    if not path or path == "" then
        return ""
    end
    if path:sub(1, 1) ~= "/" then
        return "/" .. path
    end
    return path
end

---@param name string|nil
---@return string
function M.path_remove_extension(name)
    if not name then
        return ""
    end
    return (name:gsub("%.%w+$", ""))
end

---@param path string|nil
---@return string
function M.path_basename(path)
    if not path or path == "" then
        return ""
    end
    return path:match("([^/]+)$") or path
end

---@param path string|nil
---@return string
function M.path_dirname(path)
    if not path or path == "" then
        return ""
    end
    local dir = path:match("(.+)/[^/]+$")
    if dir == nil or dir == "" then
        return "/"
    end
    return dir
end

---@param value any
---@return string
function M.escape_quotes(value)
    local text = tostring(value or "")
    text = text:gsub("\\", "\\\\")
    text = text:gsub("\"", "\\\"")
    return text
end

---@param name string|nil
---@param extension string
---@return string
function M.add_extension(name, extension)
    if not name or name == "" then
        return ""
    end
    if not extension or extension == "" then
        return name
    end
    if extension:sub(1, 1) ~= "." then
        extension = "." .. extension
    end
    if name:sub(-#extension) == extension then
        return name
    end
    return name .. extension
end

---@param name string|nil
---@param extension string
---@return string
function M.ensure_extension(name, extension)
    return M.add_extension(name, extension)
end

---@param path string|nil
---@param new_extension string
---@return string
function M.replace_extension(path, new_extension)
    if not path or path == "" then
        return ""
    end
    return M.ensure_extension(M.path_remove_extension(path), new_extension)
end

---@param value string|nil
---@return string
function M.normalize_directory_path(value)
    if not value or value == "" then
        return ""
    end
    value = value:gsub("\\", "/")
    value = value:gsub("/+", "/")
    if value == "" then
        return ""
    end
    if value ~= "/" and value:sub(-1) == "/" then
        value = value:sub(1, -2)
    end
    return M.path_with_leading_slash(value)
end

local function normalize_child_path(path)
    local value = (path or ""):gsub("\\", "/")
    value = value:gsub("/+", "/")
    if value:sub(1, 1) == "/" then
        return M.path_with_leading_slash(value), true
    end
    value = value:gsub("^/+", "")
    return value, false
end

---@param base_dir string|nil
---@param relative_path string|nil
---@return string
function M.build_resource_path(base_dir, relative_path)
    local normalized_base = M.normalize_directory_path(base_dir or "/")
    if normalized_base == "" then
        normalized_base = "/"
    end

    local cleaned, is_absolute = normalize_child_path(relative_path)
    if is_absolute then
        return cleaned
    end

    if cleaned == "" then
        return normalized_base
    end

    if normalized_base == "/" then
        return "/" .. cleaned
    end

    return normalized_base .. "/" .. cleaned
end

local function split_path(path)
    local segments = {}
    for segment in (path or ""):gmatch("[^/]+") do
        if segment ~= "" then
            segments[#segments + 1] = segment
        end
    end
    return segments
end

---@param base_dir string|nil
---@param relative string|nil
---@return string
function M.resolve_relative_path(base_dir, relative)
    if not relative or relative == "" then
        return M.path_with_leading_slash(base_dir or "/")
    end
    if relative:sub(1, 1) == "/" then
        return relative
    end
    local base_segments = split_path(M.path_with_leading_slash(base_dir or "/"))
    for segment in relative:gmatch("[^/]+") do
        if segment == ".." then
            if #base_segments > 0 then
                table.remove(base_segments)
            end
        elseif segment ~= "." and segment ~= "" then
            base_segments[#base_segments + 1] = segment
        end
    end
    return "/" .. table.concat(base_segments, "/")
end

---@param text string|nil
---@param property_name string
---@param property_value string|nil
---@return string
function M.replace_or_append_property(text, property_name, property_value)
    if not property_name or property_name == "" then
        return text or ""
    end

    local body = text or ""
    local value = property_value or ""
    local escaped_property = property_name:gsub("([^%w])", "%%%1")
    local property_pattern = string.format('%s: ".-"', escaped_property)
    local replacement = string.format('%s: "%s"', property_name, value)

    if body:match(property_pattern) then
        return body:gsub(property_pattern, function()
            return replacement
        end)
    end

    if #body > 0 and body:sub(-1) ~= "\n" then
        body = body .. "\n"
    end

    return body .. replacement .. "\n"
end

return M
