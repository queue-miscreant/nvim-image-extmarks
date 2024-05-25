require "vim_image/sixel_raw"

-- Blobs are cached by the following characteristics:
--
-- - Layer 1:
--      - Content hash
-- - Layer 2:
--      - Height, in rows
--      - Crop from top of image, in rows
--      - Crop from bottom of image (i.e., number of rows removed, as a full image)

---@class wrapped_extmark
---@field id integer
---@field start_row integer
---@field end_row integer
---@field height integer
---@field crop_row_start integer
---@field crop_row_end integer

pcall(sixel_raw.get_tty)
sixel_interface = {
  namespace = vim.api.nvim_create_namespace("Nvim-image"),
  cache = {}
}


---@param extmark wrapped_extmark
---@return string
local function extmark_to_cache_id(extmark)
  return ("%d,%d,%d"):format(
    extmark.height,
    extmark.crop_row_start,
    extmark.crop_row_end
  )
end

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


---@param blob string
---@param blob_id string
---@param extmark wrapped_extmark
function sixel_interface:_cache_blob(blob, blob_id, extmark)
  local index = extmark_to_cache_id(extmark)

  if self.cache[blob_id] ~= nil then
    self.cache[blob_id][index] = blob
  else
    local temp = {}
    temp[index] = blob
    self.cache[blob_id] = temp
  end
end


---@param blob_id string
---@param extmark wrapped_extmark
function sixel_interface:_get_from_cache(blob_id, extmark)
  local cached = self.cache[blob_id]
  if cached == nil then
    return nil
  end

  local index = extmark_to_cache_id(extmark)
  if cached[index] == nil then
    return nil
  end

  return cached[index]
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
---@param blob_id string
---@param extmark wrapped_extmark
function sixel_interface.cache_and_draw_blob(blob, blob_id, extmark)
  sixel_interface:_cache_blob(blob, blob_id, extmark)

  local windims = get_windims()
  sixel_raw.draw_sixel(
    blob,
    window_to_terminal(extmark.start_row + extmark.crop_row_start, windims)
  )
end


---@param top_line integer The first line of the currently-displayed window
---@param bottom_line integer The last line of the currently-displayed window
---@return (wrapped_extmark | nil)[]
function sixel_interface:get_visible_extmarks(top_line, bottom_line)
  local extmarks = vim.api.nvim_buf_get_extmarks(0, self.namespace, 0, -1, { details=true })
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
function sixel_interface:_lookup_blob_by_extmark(extmark, windims, char_pixel_height)
  local blob_id = vim.b.image_extmark_to_blob_id[tostring(extmark.id)]
  if blob_id == nil then
    vim.api.nvim_buf_set_extmark(0, self.namespace, extmark.start_row, 0, {
      id=extmark.id,
      virt_text= { { "Extmark lookup failure!", "ErrorMsg" } },
      end_row=extmark.end_row,
    })
    return nil
  end

  -- Get rid of the text
  vim.api.nvim_buf_set_extmark(0, self.namespace, extmark.start_row, 0, {
    id=extmark.id,
    end_row=extmark.end_row,
  })

  local cache_lookup = self:_get_from_cache(blob_id, extmark)
  if cache_lookup == nil then
    -- TODO: async request from backend
    -- Needed async guarantees: window position and other drawing parameters are unchanged
    vim.fn.VimImageCacheBlob(extmark, blob_id, char_pixel_height)
    return nil
  end

  return {
    cache_lookup,
    window_to_terminal(extmark.start_row + extmark.crop_row_start, windims)
  }
end


---@param start_row integer
---@param end_row integer
---@param path string
function sixel_interface:create_image(start_row, end_row, path)
  local id = vim.api.nvim_buf_set_extmark(
    0,
    self.namespace,
    start_row,
    0,
    { end_row=end_row }
  )

  if vim.b.image_extmark_to_blob_id == nil then
    vim.b.image_extmark_to_blob_id = vim.empty_dict()
  end

  vim.cmd.let(("b:image_extmark_to_blob_id[%d] = '%s'"):format(
    id,
    vim.fn.escape(path, "'\\")
  ))

  self:draw_visible_blobs()
end


function sixel_interface:draw_visible_blobs()
  sixel_raw.clear_screen()
  local windims = get_windims()

  local visible_extmarks = self:get_visible_extmarks(
    windims.top_line - 1,
    windims.bottom_line - 1
  )

  self:draw_blobs(visible_extmarks, windims)
end


---@param extmarks (wrapped_extmark | nil)[]
---@param windims window_dimensions
function sixel_interface:draw_blobs(extmarks, windims)
  sixel_raw.clear_screen()

  if vim.b.image_extmark_to_blob_id == nil then
    vim.b.image_extmark_to_blob_id = vim.empty_dict()
  end

  local char_pixel_height = sixel_raw.char_pixel_height()

  sixel_raw.draw_sixels(
    vim.tbl_map(
      function(extmark) return self:_lookup_blob_by_extmark(
        extmark,
        windims,
        char_pixel_height
      ) end,
      extmarks
   )
  )
end
