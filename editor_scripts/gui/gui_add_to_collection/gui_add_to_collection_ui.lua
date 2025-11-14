local M = {}

local dialog = editor.ui.component(function(props)
	local initial_value = props.initial_value or ""
	local name, set_name = editor.ui.use_state(initial_value)

	return editor.ui.dialog({
		title = props.title or "Enter GUI Name",
		content = editor.ui.vertical({
			padding = editor.ui.PADDING.LARGE,
			children = {
				editor.ui.string_field({
					value = name,
					on_value_changed = set_name,
					label = props.label or "GUI Name",
				})
			}
		}),
		buttons = {
			editor.ui.dialog_button({
				text = "Cancel",
				cancel = true
			}),
			editor.ui.dialog_button({
				text = props.confirm_text or "Create",
				enabled = name ~= "",
				default = true,
				result = name
			}),
		}
	})
end)

function M.prompt_for_gui_name(props)
	return editor.ui.show_dialog(dialog(props or {}))
end

return M
