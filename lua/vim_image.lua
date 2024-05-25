require "vim_image/sixel_raw"
require "vim_image/sixel_interface"
require "vim_image/autocmds"

---@param start_row integer
---@param end_row integer
---@param path string
function create_image_extmark(start_row, end_row, path)
  sixel_interface:create_image(start_row, end_row, path)
  vim_image_callbacks.bind_autocmds()
end
