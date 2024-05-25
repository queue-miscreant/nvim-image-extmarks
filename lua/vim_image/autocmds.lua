require "vim_image/sixel_raw"
require "vim_image/sixel_interface"

vim_image_callbacks = {}

---@return (wrapped_extmark | nil)[] | nil
local function extmarks_needing_update()

  local line_cache = vim.w.vim_image_line_cache
  local window_cache = vim.w.vim_image_window_cache
  local drawing_cache = vim.w.vim_image_extmark_cache

  local new_dims = sixel_raw.get_windims()
  local new_line = vim.fn.line("$")

  -- Try getting the visible extmarks, since the cache seems valid
  local extmarks = sixel_interface:get_visible_extmarks(
    new_dims.top_line - 1,
    new_dims.bottom_line - 1
  )
  local new_extmark = table.concat(
    vim.tbl_map(function(extmark) return extmark.id end, extmarks),
    ","
  )

  if (
    vim.deep_equal(new_dims, window_cache) and -- Window has not moved
    line_cache == vim.fn.line("$") and -- No lines have been added
    new_extmark == drawing_cache -- And the same extmarks will be drawn
  ) then
    -- No need to redraw, same extmarks visible as before
    return nil
  end

  -- Update cache
  vim.w.vim_image_extmark_cache = new_extmark
  vim.w.vim_image_window_cache = new_dims
  vim.w.vim_image_line_cache = new_line

  return extmarks
end


function vim_image_callbacks.window_movement()
  local extmarks = extmarks_needing_update()
  if extmarks == nil then return end

  sixel_interface:draw_blobs(extmarks, vim.w.vim_image_window_cache)
end


function vim_image_callbacks.bind_autocmds()
  vim.cmd [[
  augroup VimImage
    autocmd!
    " autocmd InsertLeave <buffer> lua callbacks.window_movement()
    autocmd VimResized <buffer> lua vim_image_callbacks.window_movement()
    autocmd TextChanged,TextChangedI <buffer> lua vim_image_callbacks.window_movement()
    autocmd CursorMoved <buffer> lua vim_image_callbacks.window_movement()
    autocmd ExitPre,TabClosed,WinClosed,WinLeave <buffer> lua sixel_raw.clear_screen()
  augroup END
  ]]
end
