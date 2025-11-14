local table_helper = require "editor_scripts.helpers.table_helper"

---@class UIHelperChecklistItem
---@field label? string
---@field checked? boolean
---@field enabled? boolean
---@field on_toggle fun(value:boolean, item:UIHelperChecklistItem)|nil

---@class UIHelperChecklistOptions
---@field spacing? number

---@class UIHelperLabelOptions
---@field alignment? number
---@field grow? boolean

---@class UIHelperParagraphOptions
---@field word_wrap? boolean
---@field grow? boolean

---@class UIHelperWrapContentOptions
---@field grow? boolean
---@field height? number
---@field padding? number
---@field spacing? number
---@field content_grow? boolean

---@class UIHelperButtonProps
---@field text string|nil
---@field on_pressed fun()|nil
---@field enabled? boolean
---@field alignment? number
---@field grow? boolean

---@class UIHelperButtonRowOptions
---@field spacing? number

---@class UIHelperDialogProps
---@field width? number
---@field resizable? boolean
---@field buttons? table

---@class LazyScrollOptions
---@field container table
---@field key? string
---@field list table|nil
---@field max_visible? integer
---@field commit fun(list:table)|nil
---@field clone_item fun(item:any):any|nil
---@field clone_list fun(list:table):table|nil
---@field on_flush fun(list:table)|nil

---@class UIHelper
local M = {}

---@param text string
---@param style? number
---@return table
function M.heading(text, style)
	return editor.ui.heading({
		text = text,
		style = style or editor.ui.HEADING_STYLE.DIALOG,
		alignment = editor.ui.ALIGNMENT.LEFT,
	})
end

---@param text string
---@param opts UIHelperParagraphOptions|nil
---@return table
function M.paragraph(text, opts)
	opts = opts or {}
	return editor.ui.paragraph({
		text = text,
		alignment = editor.ui.TEXT_ALIGNMENT.LEFT,
		word_wrap = opts.word_wrap ~= false,
		grow = opts.grow == true,
	})
end

---@param text string
---@param opts UIHelperLabelOptions|nil
---@return table
function M.label(text, opts)
	opts = opts or {}
	return editor.ui.label({
		text = text,
		alignment = opts.alignment or editor.ui.ALIGNMENT.LEFT,
		grow = opts.grow == true,
	})
end

---@param children table|nil
---@param opts UIHelperWrapContentOptions|nil
---@return table
function M.wrap_content(children, opts)
	opts = opts or {}
	return editor.ui.scroll({
		grow = opts.grow ~= false,
		height = opts.height,
		content = editor.ui.vertical({
			padding = opts.padding or editor.ui.PADDING.LARGE,
			spacing = opts.spacing or editor.ui.SPACING.MEDIUM,
			grow = opts.content_grow ~= false,
			children = children or {},
		}),
	})
end

local function build_checklist_row(item)
	return editor.ui.horizontal({
		spacing = editor.ui.SPACING.SMALL,
		children = {
			editor.ui.check_box({
				value = item.checked or false,
				enabled = item.enabled ~= false,
				on_value_changed = function(value)
					if item.on_toggle then
						item.on_toggle(value, item)
					end
				end,
			}),
			editor.ui.label({
				text = item.label or "",
				alignment = editor.ui.ALIGNMENT.LEFT,
				grow = true,
			}),
		},
	})
end

---@param items UIHelperChecklistItem[]|nil
---@param opts UIHelperChecklistOptions|nil
---@return table
function M.checklist(items, opts)
	opts = opts or {}
	local rows = {}
	for index, item in ipairs(items or {}) do
		rows[index] = build_checklist_row(item)
	end
	return editor.ui.vertical({
		spacing = opts.spacing or editor.ui.SPACING.SMALL,
		children = rows,
	})
end

---@return table
function M.separator()
	return editor.ui.separator({
		grow = true,
	})
end

---@param props UIHelperButtonProps|nil
---@return table
function M.button(props)
	props = props or {}
	props.enabled = props.enabled ~= false
	props.alignment = props.alignment or editor.ui.ALIGNMENT.RIGHT
	props.grow = props.grow or false
	return editor.ui.button(props)
end

---@param buttons table|nil
---@param opts UIHelperButtonRowOptions|nil
---@return table
function M.button_row(buttons, opts)
	opts = opts or {}
	return editor.ui.horizontal({
		spacing = opts.spacing or editor.ui.SPACING.SMALL,
		children = buttons or {},
	})
end

---@param props table|nil
---@return table
function M.labeled_checkbox(props)
	props = props or {}
	local label = props.label or ""
	return editor.ui.horizontal({
		spacing = props.spacing or editor.ui.SPACING.SMALL,
		alignment = props.alignment or editor.ui.ALIGNMENT.LEFT,
		grow = props.grow == true,
		children = {
			editor.ui.check_box({
				value = props.value == true,
				enabled = props.enabled ~= false,
				on_value_changed = function(value)
					if props.on_value_changed then
						props.on_value_changed(value)
					end
				end,
			}),
			editor.ui.label({
				text = label,
				alignment = editor.ui.ALIGNMENT.LEFT,
				grow = false,
			}),
		},
	})
end

---@param props UIHelperDialogProps|nil
---@return table
function M.dialog(props)
	props = props or {}
	props.width = props.width or 520
	props.resizable = props.resizable ~= false
	props.buttons = props.buttons or {}
	return editor.ui.dialog(props)
end

---Caps the number of rendered list items on the first frame to avoid oversized dialogs,
---then restores the remaining items on a subsequent render pass.
---@param opts LazyScrollOptions
function M.apply_lazy_scroll(opts)
	assert(opts and opts.container, "apply_lazy_scroll requires a persistent container table")
	local container = opts.container
	local key = opts.key or "__default"
	container.__lazy_scroll = container.__lazy_scroll or {}
	local bucket = container.__lazy_scroll[key]
	if not bucket then
		bucket = {
			render_count = 0,
			cap_applied = false,
			pending = {},
			merge_after_tick = 0,
		}
		container.__lazy_scroll[key] = bucket
	end

	bucket.render_count = bucket.render_count + 1

	local list = opts.list or {}
	local max_visible = opts.max_visible or 10
	local clone_item_fn = opts.clone_item or table_helper.clone_item
	local clone_list_fn = opts.clone_list or function(values)
		return table_helper.clone_list(values, clone_item_fn)
	end

	if not bucket.cap_applied and #list > max_visible then
		bucket.cap_applied = true
		local visible = {}
		local pending = {}
		for index, item in ipairs(list) do
			local cloned = clone_item_fn(item)
			if index <= max_visible then
				visible[#visible + 1] = cloned
			else
				pending[#pending + 1] = cloned
			end
		end
		bucket.pending = pending
		bucket.merge_after_tick = bucket.render_count
		if opts.commit then
			opts.commit(visible)
		end
		return
	end

	if bucket.pending and #bucket.pending > 0 and bucket.render_count > (bucket.merge_after_tick or 0) then
		local merged = clone_list_fn(list)
		for _, item in ipairs(bucket.pending) do
			merged[#merged + 1] = clone_item_fn(item)
		end
		bucket.pending = {}
		bucket.merge_after_tick = 0
		if opts.commit then
			opts.commit(merged)
		end
		if opts.on_flush then
			opts.on_flush(merged)
		end
	end
end

---@param container table|nil
---@param key? string
function M.reset_lazy_scroll(container, key)
	if not container or not container.__lazy_scroll then
		return
	end
	container.__lazy_scroll[key or "__default"] = nil
end

-- Creates a window popup with just a title and a single button to exit.
---@param title_text string
---@param button_text string|nil
---@param callback fun()|nil
function M.show_dialog_single_button(title_text, button_text, callback)
	local dialog = editor.ui.dialog({
		title = title_text,
		buttons = {
			editor.ui.dialog_button({
				text = button_text or "OK",
				default = true,
				result = true,
			}),
		},
	})

	local result = editor.ui.show_dialog(dialog)
	if result and callback then
		callback()
	end
end

-- Creates a window popup with just a title and a single button to exit.
---@param title_text string
---@param content_text string
---@param button_text string
---@return any
function M.show_dialog_single_text_and_button(title_text, content_text, button_text)
	local dialog = editor.ui.dialog({
		title = title_text,
		content = editor.ui.vertical({
			padding = editor.ui.PADDING.LARGE,
			children = {
				editor.ui.paragraph({
					text = content_text,
					read_only = true,
					alignment = editor.ui.TEXT_ALIGNMENT.LEFT,
					width = 600,
					height = 300,
					word_wrap = true,
				}),
			},
		}),
		buttons = {
			editor.ui.dialog_button({
				text = button_text,
				default = true,
				result = true,
			}),
		},
	})

	return editor.ui.show_dialog(dialog)
end

-- Creates a window popup with just a title, a text in content and a single button to exit.
---@param error_text string
---@return any
function M.show_error(error_text)
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
		},
	})

	return editor.ui.show_dialog(dialog)
end

-- Creates a window popup with just a title and a single button to exit.
---@param title_text string
---@param confirm_button_text string
---@return any
function M.show_dialog_with_confirm_and_cancel(title_text, confirm_button_text)
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
				result = true,
			}),
		},
	})

	return editor.ui.show_dialog(dialog)
end

return M
