local M = {}

-- Creates a window popup with just a title and a single button to exit.
function M.show_dialog_single_button(title_text, button_text, callback)
	-- Create dialog popup:
	local dialog = editor.ui.dialog({
		title = title_text,
		buttons = {
			editor.ui.dialog_button({
				text = button_text,
				default = true,
				result = true
			})
		}
	})

	-- Show popup and handle result
	local result = editor.ui.show_dialog(dialog)
	if result and callback then
		callback()
	end
end

-- Creates a window popup with just a title and a single button to exit.
function M.show_dialog_single_text_and_button(title_text, content_text, button_text)
	-- Create dialog popup:
	local dialog = editor.ui.dialog({
		title = title_text,
		content = editor.ui.vertical({
			padding = editor.ui.PADDING.LARGE,
			children = {
				editor.ui.text_box({
					text = content_text,
					read_only = true,
					width = 600,
					height = 300,
				}),
			},
		}),
		buttons = {
			editor.ui.dialog_button({
				text = button_text,
				default = true,
				result = true
			})
		}
	})

	-- Show popup
	editor.ui.show_dialog(dialog)
end

-- Creates a window popup with just a title, a text in content and a single button to exit.
function M.show_error(error_text)
	-- Create dialog popup:
	local dialog = editor.ui.dialog({
		title = "Error",
		content = editor.ui.label({
			text = error_text,
			alignment = editor.ui.ALIGNMENT.LEFT,
			word_wrap = true,
		}),
		buttons = {
			editor.ui.dialog_button({
				text = "Exit",
				default = true,
				result = true,
			}),
		}
	})

	-- Show popup
	editor.ui.show_dialog(dialog)
end

-- Creates a window popup with just a title and a single button to exit.
function M.show_dialog_with_confirm_and_cancel(title_text, confirm_button_text)
	-- Create dialog popup:
	local dialog = editor.ui.dialog({
		title = title_text,
		buttons = {
			editor.ui.dialog_button({
				text = "Cancel",
				default = false,
				result = false,
				cancel = true,
			}),
			editor.ui.dialog_button({
				text = confirm_button_text,
				default = true,
				result = true
			})
		}
	})

	-- Show popup and return user input
	return editor.ui.show_dialog(dialog)
end

return M