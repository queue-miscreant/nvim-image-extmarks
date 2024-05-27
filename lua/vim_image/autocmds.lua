local sixel_raw = require "vim_image/sixel_raw"
local sixel_interface = require "vim_image/sixel_interface"

local vim_image_callbacks = {}

---@return (wrapped_extmark | nil)[] | nil
function vim_image_callbacks.extmarks_needing_update(force)

  local line_cache = vim.w.vim_image_line_cache
  local window_cache = vim.w.vim_image_window_cache
  local drawing_cache = vim.w.vim_image_extmark_cache

  local new_dims = sixel_raw.get_windims()
  local new_line = vim.fn.line("$")

  -- Try getting the visible extmarks, since the cache seems valid

  local extmarks = vim.tbl_values(
    sixel_interface.get_visible_extmarks(
      new_dims.top_line,
      new_dims.bottom_line
    )
  )
  local new_extmark = table.concat(
    vim.tbl_map(function(extmark) return extmark.id or "" end, extmarks),
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

return vim_image_callbacks
