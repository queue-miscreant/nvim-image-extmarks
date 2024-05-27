local sixel_interface = require "vim_image/sixel_interface"
local sixel_raw = require "vim_image/sixel_raw"
local callbacks = require "vim_image/autocmds"

sixel_extmarks = { callbacks = {} }


local function bind_autocmds()
  vim.cmd [[
  augroup VimImage
    autocmd!
    autocmd VimEnter,VimResized,TabClosed <buffer> lua sixel_extmarks.callbacks.update()
    autocmd TextChanged,TextChangedI <buffer> lua sixel_extmarks.callbacks.update()
    autocmd TabEnter <buffer> lua sixel_extmarks.callbacks.update(true)
    autocmd TabLeave,ExitPre <buffer> lua sixel_extmarks.clear_screen()
    autocmd CursorMoved <buffer> lua sixel_extmarks.callbacks.update()
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
  local id = sixel_interface.create_image(start_row, end_row, path)

  -- Bind extmarks if we need to
  if (
    vim.b.image_extmark_to_path ~= nil and
    vim.tbl_count(vim.b.image_extmark_to_path) > 0
  ) then
    bind_autocmds()
  end

  return id
end


-- Retrieve a list of extmarks in the current buffer between the given rows.
-- To retrieve all extmarks in the current buffer, use parameters (0, -1).
-- 
---@param start_row integer The (0-indexed) row to start searching from
---@param end_row integer
---@return image_extmark[]
function sixel_extmarks.get(start_row, end_row)
  return sixel_interface.get_image_extmarks(start_row, end_row)
end


-- Delete the extmark in the current buffer.
-- Note that this will NOT remove blobs from the cache.
-- 
---@param id integer The id of the extmark to remove
function sixel_extmarks.remove(id)
  return sixel_interface.remove_image_extmark(id)
end


-- Delete all extmarks in the current buffer.
-- The same caveat about the cache applies here as well.
--
---@see sixel_extmarks.remove
function sixel_extmarks.remove_all()
  return sixel_interface.remove_images()
end


-- Move the extmark identified by {id} so that the image stretches
-- starting at row {start_row} of the buffer and ends at {end_row}.
-- Be aware that this can resize the image.
--
---@param id integer
---@param start_row integer
---@param end_row integer
function sixel_extmarks.move(id, start_row, end_row)
  sixel_interface.move_extmark(id, start_row, end_row)
end


-- Change the content of an extmark.
--
---@param id integer The id of the extmark to modify.
---@param path string The path to the file containing the new content.
function sixel_extmarks.change_content(id, path)
  sixel_interface.change_extmark_content(id, path)
end


-- Clear the sixel cache.
-- If no arguments are supplied, the entire cache is cleared.
-- Otherwise, either a file path or list of file paths can be supplied.
-- If these paths have entries in the cache, they will be cleared.
--
---@param path? (string | string[])
function sixel_extmarks.clear_cache(path)
  sixel_interface.clear_cache(path)
end


-- Draw all extmark content on the screen.
--
---@param force boolean Force redraw
function sixel_extmarks.callbacks.update(force)
  local extmarks = callbacks.extmarks_needing_update(force)
  if extmarks == nil then return end

  sixel_interface.draw_blobs(extmarks, vim.w.vim_image_window_cache)
end


-- Clear all content drawn to the screen. Unlike :mode in vim,
-- this has the additional guarantee of working inside a tmux session.
function sixel_extmarks.clear_screen()
  sixel_raw.clear_screen()
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
