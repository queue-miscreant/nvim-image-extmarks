-- nvim_image_extmarks/window_drawing.lua
--
-- Sixel drawing functionality, relative to the current window state.


local sixel_raw = require "nvim_image_extmarks/sixel_raw"
local interface = require "nvim_image_extmarks/interface"
local blob_cache = require "nvim_image_extmarks/blob_cache"

pcall(sixel_raw.get_tty)
local window_drawing = {
  debounce = {},
  enabled = true,
  just_enabled = true
}


---@class window_dimensions
---@field top_line integer
---@field bottom_line integer
---@field start_line integer
---@field window_column integer
---@field start_column integer


---@return window_dimensions
local function get_windims()
  local wininfo = vim.fn.getwininfo(vim.fn.win_getid())

  return {
      top_line = wininfo[1].topline,
      bottom_line = wininfo[1].botline,
      start_line = wininfo[1].winrow,
      window_column = wininfo[1].wincol,
      start_column = wininfo[1].textoff,
  }
end


-- Convert window coordinates (start_row, end_row) to terminal coordinates
---@param start_row integer The row of the buffer to start drawing on
---@param windims window_dimensions The current dimensions of the window
---@return [integer, integer]
local function window_to_terminal(start_row, windims)
    local row = windims.start_line + start_row - windims.top_line
    local column = windims.window_column + windims.start_column

    return { row, column }
end


---@param blob string
---@param path string
---@param extmark wrapped_extmark
function window_drawing.cache_and_draw_blob(blob, path, extmark)
  blob_cache.insert(blob, path, extmark)

  local windims = get_windims()
  sixel_raw.draw_sixel(
    blob,
    window_to_terminal(extmark.start_row + extmark.crop_row_start, windims)
  )
end


---@param extmark wrapped_extmark
---@param path string
---@param char_pixel_height integer
local function schedule_generate_blob(extmark, path, char_pixel_height)
  if window_drawing.debounce[tostring(extmark.id)] ~= nil then
    return
  end
  window_drawing.debounce[tostring(extmark.id)] = true

  sixel_raw.blobify(
    extmark,
    path,
    char_pixel_height,
    function(blob)
      vim.defer_fn(function()
        window_drawing.cache_and_draw_blob(blob, path, extmark)
        window_drawing.debounce[tostring(extmark.id)] = nil
      end, 0)
    end
  )
end


---@param top_line integer The first line of the currently-displayed window
---@param bottom_line integer The last line of the currently-displayed window
---@return (wrapped_extmark | nil)[]
function window_drawing.get_visible_extmarks(top_line, bottom_line)
  local extmarks = vim.api.nvim_buf_get_extmarks(0, interface.namespace, 0, -1, { details=true })
  local cursor_row = vim.fn.line(".")

  return vim.tbl_map(function(extmark)
    local start_row, end_row = extmark[2], extmark[4].end_row

    if end_row <= top_line or start_row > bottom_line then
      return nil
    end

    local crop_row_start = math.max(0, top_line - start_row)
    local crop_row_end = math.max(0, end_row - bottom_line)

    -- Hide the extmark if the cursor is there
    if start_row <= cursor_row and cursor_row <= end_row then
      return nil
    end

    return {
      id = extmark[1],
      start_row = start_row,
      end_row = end_row,
      height = end_row - start_row,
      crop_row_start = crop_row_start,
      crop_row_end = crop_row_end,
    }
  end, extmarks)
end


---@param extmark wrapped_extmark
---@param windims window_dimensions
---@param char_pixel_height integer
---@return [string, [number, number]] | nil
local function lookup_or_generate_blob(extmark, windims, char_pixel_height)
  local path = vim.b.image_extmark_to_path[tostring(extmark.id)]
  if path == nil then
    vim.api.nvim_buf_set_extmark(0, interface.namespace, extmark.start_row, 0, {
      id=extmark.id,
      virt_text= { { "Extmark lookup failure!", "ErrorMsg" } },
      end_row=extmark.end_row,
    })
    return nil
  end

  -- Get rid of the text
  vim.api.nvim_buf_set_extmark(0, interface.namespace, extmark.start_row, 0, {
    id=extmark.id,
    end_row=extmark.end_row,
  })

  local cache_lookup = blob_cache.get(path, extmark)
  if cache_lookup == nil then
    -- TODO: Needed async guarantees - window position and other drawing parameters are unchanged
    schedule_generate_blob(extmark, path, char_pixel_height)
    return nil
  end

  return {
    cache_lookup,
    window_to_terminal(extmark.start_row + extmark.crop_row_start, windims)
  }
end


---@return (wrapped_extmark | nil)[] | nil
function window_drawing.extmarks_needing_update(force)
  -- Get current cache
  local line_cache = vim.w.vim_image_line_cache
  local window_cache = vim.w.vim_image_window_cache
  local drawing_cache = vim.w.vim_image_extmark_cache

  local new_dims = get_windims()
  local new_line = vim.fn.line("$")

  -- Try getting the visible extmarks, since the cache seems valid

  local extmarks = vim.tbl_values(
    window_drawing.get_visible_extmarks(
      new_dims.top_line,
      new_dims.bottom_line
    )
  )
  local new_extmark = table.concat(
    vim.tbl_map(function(extmark) return extmark.id or "" end, extmarks),
    ","
  )

  if window_drawing.just_enabled then
    window_drawing.just_enabled = false
  elseif (
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


---@param extmarks (wrapped_extmark | nil)[]
---@param windims window_dimensions
function window_drawing.draw_blobs(extmarks, windims)
  if window_drawing.enabled then
    sixel_raw.clear_screen()
  end

  if vim.b.image_extmark_to_path == nil then
    vim.b.image_extmark_to_path = vim.empty_dict()
  end

  local char_pixel_height = sixel_raw.char_pixel_height()

  local blobs = vim.tbl_map(
    function(extmark) return lookup_or_generate_blob(
      extmark,
      windims,
      char_pixel_height
    ) end,
    extmarks
  )

  if window_drawing.enabled then
    sixel_raw.draw_sixels(blobs)
  end
end


function window_drawing.draw_visible_blobs()
  local windims = get_windims()

  local visible_extmarks = window_drawing.get_visible_extmarks(
    windims.top_line - 1,
    windims.bottom_line - 1
  )

  window_drawing.draw_blobs(visible_extmarks, windims)
end


-- Disable drawing blobs.
-- Blobs will still be generated in the background, but the contents will not
-- be pushed to the screen.
--
function window_drawing.disable_drawing()
  window_drawing.enabled = false
  window_drawing.just_enabled = false
end


-- Enable drawing blobs, after having disabled them with `disable_drawing`.
--
function window_drawing.enable_drawing()
  window_drawing.enabled = true
  window_drawing.just_enabled = true
end

return window_drawing
