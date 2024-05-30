-- nvim_image_extmarks.lua
--
-- Functions providing a consistent interface to the management of sixel extmarks.

local interface = require "nvim_image_extmarks/interface"
local sixel_raw = require "nvim_image_extmarks/sixel_raw"
local window_drawing = require "nvim_image_extmarks/window_drawing"
local blob_cache = require "nvim_image_extmarks/blob_cache"

local extmark_timer = nil
assert(
  (
    type(vim.g.image_extmarks_buffer_ms) == "number" or
    type(vim.g.image_extmarks_buffer_ms) == "nil"
  ),
  "g:image_extmarks_buffer_ms must be a number"
)
vim.api.nvim_create_augroup("ImageExtmarks#pre_draw", { clear = false })


---@diagnostic disable-next-line
sixel_extmarks = {}


local function bind_autocmds()
  vim.cmd [[
  augroup ImageExtmarks
    autocmd!
    autocmd TabClosed,TextChanged,TextChangedI <buffer> lua sixel_extmarks.redraw()
    autocmd VimEnter,VimResized,TabEnter <buffer> lua sixel_extmarks.redraw(true)
    autocmd TabLeave,ExitPre <buffer> lua sixel_extmarks.clear_screen()
    autocmd CursorMoved <buffer> lua sixel_extmarks.redraw()
  augroup END
  ]]
end


-- Create a new image extmark in the current buffer.
--
---@param start_row integer The (0-indexed) row of the buffer that the image begins on
---@param end_row integer The (0-indexed) row of the buffer that the image ends on
---@param path string A path to the file content
---@return integer
function sixel_extmarks.create(start_row, end_row, path)
  local id = interface.create_image(start_row, end_row, path)

  -- Bind extmarks if we need to
  if (
    vim.b.image_extmark_to_path ~= nil and
    vim.tbl_count(vim.b.image_extmark_to_path) > 0
  ) then
    bind_autocmds()
  end

  window_drawing.draw_visible_blobs()

  return id
end


-- Retrieve a list of extmarks in the current buffer between the given rows.
-- To retrieve all extmarks in the current buffer, use parameters (0, -1).
-- 
---@param start_row integer The (0-indexed) row to start searching from
---@param end_row integer
---@return image_extmark[]
function sixel_extmarks.get(start_row, end_row)
  return interface.get_image_extmarks(start_row, end_row)
end

-- Retrieve an extmark in the current buffer with the given id.
--
---@param id integer The id of the extmark
---@return image_extmark
function sixel_extmarks.get_by_id(id)
  return interface.get_image_extmark_by_id(id)
end


-- Delete the extmark in the current buffer.
-- Note that this will NOT remove blobs from the cache.
-- 
---@param id integer The id of the extmark to remove
function sixel_extmarks.remove(id)
  local ret = interface.remove_image_extmark(id)
  window_drawing.draw_visible_blobs()

  return ret
end


-- Delete all extmarks in the current buffer.
-- The same caveat about the cache applies here as well.
--
---@see sixel_extmarks.remove
function sixel_extmarks.remove_all()
  local ret = interface.remove_images()
  window_drawing.draw_visible_blobs()

  return ret
end


-- Move the extmark identified by {id} so that the image stretches
-- starting at row {start_row} of the buffer and ends at {end_row}.
-- Be aware that this can resize the image.
--
---@param id integer
---@param start_row integer
---@param end_row integer
function sixel_extmarks.move(id, start_row, end_row)
  local ret = interface.move_extmark(id, start_row, end_row)
  window_drawing.draw_visible_blobs()

  return ret
end


-- Change the content of an extmark.
--
---@param id integer The id of the extmark to modify.
---@param path string The path to the file containing the new content.
function sixel_extmarks.change_content(id, path)
  local ret = interface.change_extmark_content(id, path)
  window_drawing.draw_visible_blobs()

  return ret
end


-- Clear the sixel cache.
-- If no arguments are supplied, the entire cache is cleared.
-- Otherwise, either a file path or list of file paths can be supplied.
-- If these paths have entries in the cache, they will be cleared.
--
---@param path? (string | string[])
function sixel_extmarks.clear_cache(path)
  interface.clear_cache(path)
end


-- Clear all content drawn to the screen. Unlike :mode in vim,
-- this has the additional guarantee of working inside a tmux session.
function sixel_extmarks.clear_screen()
  sixel_raw.clear_screen()
end


-- Draw all extmark content on the screen.
--
---@param force boolean Force redraw
function sixel_extmarks.redraw(force)
  local extmarks = window_drawing.extmarks_needing_update(force)
  if extmarks == nil then return end

  if vim.g.image_extmarks_buffer_ms == nil then
    window_drawing.draw_blobs(extmarks, vim.w.vim_image_window_cache)
    return
  -- "Renew" the timer by cancelling it first
  elseif extmark_timer ~= nil then
    pcall(function()
      extmark_timer:stop()
      extmark_timer:close()
    end)
  end
  sixel_raw.clear_screen()
  extmark_timer = vim.loop.new_timer()
  extmark_timer:start(
    vim.g.image_extmarks_buffer_ms,
    0,
    vim.schedule_wrap(function()
      extmark_timer:stop()
      extmark_timer:close()
      window_drawing.draw_blobs(extmarks, vim.w.vim_image_window_cache)
    end)
  )
end


-- Disable drawing blobs.
-- Blobs will still be generated in the background, but the contents will not
-- be pushed to the screen.
--
function sixel_extmarks.disable_drawing()
  window_drawing.disable_drawing()
end


-- Enable drawing blobs, after having disabled them with `disable_drawing`.
--
---@param redraw? boolean Whether or not to redraw the screen afterward. True if not given.
function sixel_extmarks.enable_drawing(redraw)
  window_drawing.enable_drawing()
  if redraw == nil or redraw then
    sixel_extmarks.redraw(true)
  end
end


-- Generate a snapshot of the blob cache.
-- Rather than the cache, the first two layers of keys are returned, i.e.,
-- a table with filenames as keys and buffer ranges as values.
--
function sixel_extmarks.dump_blob_cache()
  return blob_cache.dump()
end


local function create_image_command(opts)
  sixel_extmarks.create(
    opts.line1,
    opts.line2,
    opts.args
  )
end


vim.api.nvim_create_user_command(
  'CreateImage',
  create_image_command,
  { nargs = 1, range = 2, complete = "file" }
)
