require "vim_image/sixel_raw"
require "vim_image/sixel_interface"
require "vim_image/autocmds"

---@param start_row integer
---@param end_row integer
---@param path string
---@return integer
function create_image_extmark(start_row, end_row, path)
  local id = sixel_interface.create_image(start_row, end_row, path)

  -- Bind extmarks if we need to
  if (
    vim.b.image_extmark_to_path ~= nil and
    vim.tbl_count(vim.b.image_extmark_to_path) > 0
  ) then
    vim_image_callbacks.bind_autocmds()
  end

  return id
end


---@param start_row integer
---@param end_row integer
---@return image_extmark[]
function get_image_extmarks(start_row, end_row)
  return sixel_interface.get_image_extmarks(start_row, end_row)
end


---@param id integer
function remove_image_extmark(id)
  return sixel_interface.remove_image_extmark(id)
end


function remove_images()
  return sixel_interface.remove_images()
end


---@param id integer
---@param start_row integer
---@param end_row integer
function move_image_extmark(id, start_row, end_row)
  sixel_interface.move_extmark(id, start_row, end_row)
end


---@param id integer
---@param path string
function change_extmark_content(id, path)
  sixel_interface.change_extmark_content(id, path)
end


---@param path (nil | string | string[])
function clear_cache(path)
  sixel_interface.clear_cache(path)
end
