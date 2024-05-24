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

---@class window_dimensions
---@field top_line integer
---@field bottom_line integer
---@field start_line integer
---@field window_column integer
---@field start_column integer

sixel_interface = {
  namespace = nil,
  cache = {}
}

function sixel_interface:init()
  self.namespace = vim.api.nvim_create_namespace("Nvim-image")
  pcall(sixel_raw.get_tty)
end


---@param extmark wrapped_extmark
---@return string
local function extmark_to_cache_id(extmark)
  return ("%d,%d,%d"):format(
    extmark.height,
    extmark.crop_row_start,
    extmark.crop_row_end
  )
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


---@param top_line integer The first line of the currently-displayed window
---@param bottom_line integer The last line of the currently-displayed window
---@return wrapped_extmark[]
function sixel_interface:get_visible_extmarks(top_line, bottom_line)
  local extmarks = vim.api.nvim_buf_get_extmarks(0, self.namespace, 0, -1, { details=true })

  return vim.tbl_map(function(extmark)
    local start_row, end_row = extmark[2], extmark[4].end_row

    if end_row < top_line or start_row > bottom_line then
      return nil
    end

    local crop_row_start = math.max(0, top_line - start_row)
    local crop_row_end = math.max(0, end_row - bottom_line)

    return {
      id = extmark[1],
      start_row = start_row,
      end_row = end_row,
      -- TODO: this might be unnecessary
      height = (end_row - crop_row_end) - (start_row - crop_row_start),
      crop_row_start = crop_row_start,
      crop_row_end = crop_row_end,
    }
  end, extmarks)
end


-- Convert window coordinates (start_row, end_row) to terminal coordinates
---@param start_row integer The row of the buffer to start drawing on
---@param windims window_dimensions The current dimensions of the window
local function window_to_terminal(start_row, windims)
    local row = windims.start_line + start_row - windims.top_line
    local column = windims.window_column + windims.start_column

    return row, column
end


---@param windims window_dimensions
---@param extmark wrapped_extmark
function sixel_interface:_lookup_blob_by_extmark(extmark, windims)
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
  local cursor_row = vim.fn.line(".") - 1
  -- Hide the extmark if the cursor is there
  if extmark.start_row <= cursor_row and cursor_row <= extmark.end_row then
    return nil
  end

  local cache_lookup = self:_get_from_cache(blob_id, extmark)
  if cache_lookup == nil then
    -- TODO: async request from backend
    -- Needed async guarantees: window position and other drawing parameters are unchanged
    return nil
  end

  return cache_lookup, window_to_terminal(extmark.start_row - extmark.crop_row_start, windims)
end


---@param start_row integer
---@param end_row integer
---@param path string
function sixel_interface:create_image(start_row, end_row, path)
  local id = vim.api.nvim_buf_set_extmark(0, self.namespace, start_row, 0, { end_row=end_row })

  if vim.b.image_extmark_to_blob_id == nil then
    vim.b.image_extmark_to_blob_id = vim.empty_dict()
  end

  vim.cmd.let(("b:image_extmark_to_blob_id[%d] = '%s'"):format(
    id,
    vim.fn.escape(path, "'\\")
  ))

  -- TODO: try to draw it
end


function sixel_interface:draw_visible_blobs()
  local wininfo = vim.fn.getwininfo(vim.fn.win_getid())

  -- TODO: probably useless
  local new_dims = {
      top_line = wininfo[1].topline,
      bottom_line = wininfo[1].botline,
      start_line = wininfo[1].winrow,
      window_column = wininfo[1].wincol,
      start_column = wininfo[1].textoff,
  }

  local visible_extmarks = self:get_visible_extmarks(
    new_dims.top_line - 1,
    new_dims.bottom_line - 1
  )

  if vim.b.image_extmark_to_blob_id == nil then
    vim.b.image_extmark_to_blob_id = vim.empty_dict()
  end

  sixel_raw.draw_sixels(
    vim.tbl_map(
      function(extmark) self:_lookup_blob_by_extmark(extmark, new_dims) end,
      visible_extmarks
    )
  )
end
