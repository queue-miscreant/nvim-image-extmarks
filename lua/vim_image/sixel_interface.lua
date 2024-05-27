local sixel_raw = require "vim_image/sixel_raw"

---@class image_extmark
---@field id integer
---@field start_row integer
---@field end_row integer
---@field path string

-- Blobs are cached by the following characteristics:
--
-- - Layer 1:
--      - Content hash
-- - Layer 2:
--      - Height, in rows
--      - Crop from top of image, in rows
--      - Crop from bottom of image (i.e., number of rows removed, as a full image)

pcall(sixel_raw.get_tty)
local sixel_interface = {
  namespace = vim.api.nvim_create_namespace("Nvim-image"),
  cache = {},
  debounce = {}
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
---@param path string
---@param extmark wrapped_extmark
function sixel_interface._cache_blob(blob, path, extmark)
  local index = extmark_to_cache_id(extmark)

  if sixel_interface.cache[path] ~= nil then
    sixel_interface.cache[path][index] = blob
  else
    local temp = {}
    temp[index] = blob
    sixel_interface.cache[path] = temp
  end
end


---@param path string
---@param extmark wrapped_extmark
function sixel_interface._get_from_cache(path, extmark)
  local cached = sixel_interface.cache[path]
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


---@param extmark wrapped_extmark
---@param path string
---@param char_pixel_height integer
local function schedule_generate_blob(extmark, path, char_pixel_height)
  if sixel_interface.debounce[tostring(extmark.id)] ~= nil then
    return
  end
  sixel_interface.debounce[tostring(extmark.id)] = true

  sixel_raw.convert(
    extmark,
    path,
    char_pixel_height,
    function(blob)
      vim.defer_fn(function()
        sixel_interface.cache_and_draw_blob(blob, path, extmark)
        sixel_interface.debounce[tostring(extmark.id)] = nil
      end, 0)
    end
  )
end


---@param blob string
---@param path string
---@param extmark wrapped_extmark
function sixel_interface.cache_and_draw_blob(blob, path, extmark)
  sixel_interface._cache_blob(blob, path, extmark)

  local windims = get_windims()
  sixel_raw.draw_sixel(
    blob,
    window_to_terminal(extmark.start_row + extmark.crop_row_start, windims)
  )
end


---@param top_line integer The first line of the currently-displayed window
---@param bottom_line integer The last line of the currently-displayed window
---@return (wrapped_extmark | nil)[]
function sixel_interface.get_visible_extmarks(top_line, bottom_line)
  local extmarks = vim.api.nvim_buf_get_extmarks(0, sixel_interface.namespace, 0, -1, { details=true })
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
function sixel_interface._lookup_blob_by_extmark(extmark, windims, char_pixel_height)
  local path = vim.b.image_extmark_to_path[tostring(extmark.id)]
  if path == nil then
    vim.api.nvim_buf_set_extmark(0, sixel_interface.namespace, extmark.start_row, 0, {
      id=extmark.id,
      virt_text= { { "Extmark lookup failure!", "ErrorMsg" } },
      end_row=extmark.end_row,
    })
    return nil
  end

  -- Get rid of the text
  vim.api.nvim_buf_set_extmark(0, sixel_interface.namespace, extmark.start_row, 0, {
    id=extmark.id,
    end_row=extmark.end_row,
  })

  local cache_lookup = sixel_interface._get_from_cache(path, extmark)
  if cache_lookup == nil then
    -- Needed async guarantees: window position and other drawing parameters are unchanged
    schedule_generate_blob(extmark, path, char_pixel_height)
    return nil
  end

  return {
    cache_lookup,
    window_to_terminal(extmark.start_row + extmark.crop_row_start, windims)
  }
end


function sixel_interface.draw_visible_blobs()
  sixel_raw.clear_screen()
  local windims = get_windims()

  local visible_extmarks = sixel_interface.get_visible_extmarks(
    windims.top_line - 1,
    windims.bottom_line - 1
  )

  sixel_interface.draw_blobs(visible_extmarks, windims)
end


---@param extmarks (wrapped_extmark | nil)[]
---@param windims window_dimensions
function sixel_interface.draw_blobs(extmarks, windims)
  sixel_raw.clear_screen()

  if vim.b.image_extmark_to_path == nil then
    vim.b.image_extmark_to_path = vim.empty_dict()
  end

  local char_pixel_height = sixel_raw.char_pixel_height()

  sixel_raw.draw_sixels(
    vim.tbl_map(
      function(extmark) return sixel_interface._lookup_blob_by_extmark(
        extmark,
        windims,
        char_pixel_height
      ) end,
      extmarks
   )
  )
end


---@param start_row integer
---@param end_row integer
---@param path string
---@return integer
function sixel_interface.create_image(start_row, end_row, path)
  local id = vim.api.nvim_buf_set_extmark(
    0,
    sixel_interface.namespace,
    start_row,
    0,
    { end_row=end_row }
  )

  if vim.b.image_extmark_to_path == nil then
    vim.b.image_extmark_to_path = vim.empty_dict()
  end

  vim.cmd.let(("b:image_extmark_to_path[%d] = '%s'"):format(
    id,
    vim.fn.escape(path, "'\\")
  ))

  sixel_interface.draw_visible_blobs()

  return id
end


---@param start_row integer
---@param end_row integer
---@return image_extmark[]
function sixel_interface.get_image_extmarks(start_row, end_row)
  local extmarks = vim.api.nvim_buf_get_extmarks(
    0,
    sixel_interface.namespace,
    start_row,
    end_row,
    { details=true }
  )

  return vim.tbl_map(function(extmark)
    ---@type image_extmark
    return {
      id = extmark[1],
      start_row = extmark[2],
      end_row = extmark[4].end_row,
      path = vim.b.image_extmark_to_path[extmark[1]]
    }
  end, extmarks)
end


---@param id integer
function sixel_interface.remove_image_extmark(id)
  return vim.api.nvim_buf_del_extmark(
    0,
    sixel_interface.namespace,
    id
  )
end


function sixel_interface.remove_images()
  return vim.api.nvim_buf_clear_namespace(
    0,
    sixel_interface.namespace,
    0,
    -1
  )
end


---@param id integer
---@param start_row integer
---@param end_row integer
function sixel_interface.move_extmark(id, start_row, end_row)
  local extmark = vim.api.nvim_buf_get_extmark_by_id(
    0,
    sixel_interface.namespace,
    id,
    {}
  )
  if extmark == nil then return end

  vim.api.nvim_buf_set_extmark(
    0,
    sixel_interface.namespace,
    start_row,
    0,
    { id=id, end_row=end_row }
  )

  sixel_interface.draw_visible_blobs()
end


---@param id integer
---@param path string
function sixel_interface.change_extmark_content(id, path)
  local map = vim.b.image_extmark_to_path
  if map == nil then return end

  local extmark = vim.api.nvim_buf_get_extmark_by_id(
    0,
    sixel_interface.namespace,
    id,
    {}
  )
  if extmark == nil or map[tostring(id)] == nil then return end

  vim.cmd.let(("b:image_extmark_to_path[%d] = '%s'"):format(
    id,
    vim.fn.escape(path, "'\\")
  ))

  sixel_interface.draw_visible_blobs()
end


---@param path (nil | string | string[])
function sixel_interface.clear_cache(path)
  if path == nil then
    sixel_interface.cache = {}
  elseif type(path) == "table" then
    for _, path_ in ipairs(path) do
      sixel_interface.cache[path_] = {}
    end
  elseif type(path) == "string" then
    sixel_interface.cache[path] = {}
  else
    assert(false, "Invalid argument to clear_cache")
  end

  collectgarbage()
end

return sixel_interface
