require "vim_image/sixel_raw"
require "vim_image/sixel_interface"

vim_image_callbacks = {}

---@return (wrapped_extmark | nil)[] | nil
local function extmarks_needing_update(force)

  local line_cache = vim.w.vim_image_line_cache
  local window_cache = vim.w.vim_image_window_cache
  local drawing_cache = vim.w.vim_image_extmark_cache

  local new_dims = sixel_raw.get_windims()
  local new_line = vim.fn.line("$")

  -- Try getting the visible extmarks, since the cache seems valid

  local extmarks = sixel_interface:get_visible_extmarks(
    new_dims.top_line,
    new_dims.bottom_line
  )
  local new_extmark = table.concat(
    vim.tbl_map(function(extmark) return extmark.id end, extmarks),
    ","
  )

  if (
    not force and
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


function vim_image_callbacks.update_extmarks(force)
  local extmarks = extmarks_needing_update(force)
  if extmarks == nil then return end

  sixel_interface:draw_blobs(extmarks, vim.w.vim_image_window_cache)
end


function vim_image_callbacks.bind_autocmds()
  vim.cmd [[
  augroup VimImage
    autocmd!
    " autocmd InsertLeave <buffer> lua callbacks.update_extmarks()
    autocmd VimEnter,VimResized,TabClosed <buffer> lua vim_image_callbacks.update_extmarks()
    autocmd TextChanged,TextChangedI <buffer> lua vim_image_callbacks.update_extmarks()
    autocmd TabEnter <buffer> lua vim_image_callbacks.update_extmarks(true)
    autocmd TabLeave,ExitPre <buffer> lua sixel_raw.clear_screen()
    autocmd CursorMoved <buffer> lua vim_image_callbacks.update_extmarks()
  augroup END
  ]]
end
