local DEFAULT_CONTENT = [[
function init(self)
	msg.post(".", "acquire_input_focus")
end

function final(self)
	msg.post(".", "release_input_focus")
end

function update(self, dt)
end

function on_message(self, message_id, message, sender)
end

function on_input(self, action_id, action)
end

function on_reload(self)
end
]]

local M = {}

function M.default_content()
	return DEFAULT_CONTENT
end

return M
