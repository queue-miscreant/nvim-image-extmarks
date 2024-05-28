-- nvim_image_extmarks/interface.lua
--
-- Functions which wrap nvim's native extmark interface.
-- They are generally "dumber" than the functions exposed to the user, and
-- are focused primarily on buffer-local storage of extmark and file data.

---@class image_extmark
---@field id integer
---@field start_row integer
---@field end_row integer
---@field path string

local interface = {
  namespace = vim.api.nvim_create_namespace("Nvim-image"),
}


---@param start_row integer
---@param end_row integer
---@param path string
---@return integer
function interface.create_image(start_row, end_row, path)
  local id = vim.api.nvim_buf_set_extmark(
    0,
    interface.namespace,
    start_row,
    0,
    { end_row=end_row }
  )

  if vim.b.image_extmark_to_path == nil then
    vim.b.image_extmark_to_path = vim.empty_dict()
  end

  vim.print(vim.b.image_extmark_to_path)
  vim.cmd.let(("b:image_extmark_to_path[%d] = '%s'"):format(
    id,
    vim.fn.escape(path, "'\\")
  ))

  return id
end


-- Convert extmark from nvim_buf_get_extmark{_by_id,s} to idiomatic form
--
---@param extmark [integer, integer, integer, {end_row: integer}]
---@return image_extmark
local function convert_extmark(extmark)
    return {
      id = extmark[1],
      start_row = extmark[2],
      end_row = extmark[4].end_row,
      path = vim.b.image_extmark_to_path[tostring(extmark[1])]
    }
end


---@param id integer
---@return image_extmark
function interface.get_image_extmark_by_id(id)
  local extmarks = vim.api.nvim_buf_get_extmark_by_id(
    0,
    interface.namespace,
    id,
    { details=true }
  )

  return convert_extmark(extmarks)
end


---@param start_row integer
---@param end_row integer
---@return image_extmark[]
function interface.get_image_extmarks(start_row, end_row)
  local extmarks = vim.api.nvim_buf_get_extmarks(
    0,
    interface.namespace,
    start_row,
    end_row,
    { details=true }
  )

  return vim.tbl_map(convert_extmark, extmarks)
end


---@param id integer
function interface.remove_image_extmark(id)
  vim.b.image_extmark_to_path[tostring(id)] = nil

  return vim.api.nvim_buf_del_extmark(
    0,
    interface.namespace,
    id
  )
end


function interface.remove_images()
  vim.b.image_extmark_to_path = vim.empty_dict()
  return vim.api.nvim_buf_clear_namespace(
    0,
    interface.namespace,
    0,
    -1
  )
end


---@param id integer
---@param start_row integer
---@param end_row integer
function interface.move_extmark(id, start_row, end_row)
  local extmark = vim.api.nvim_buf_get_extmark_by_id(
    0,
    interface.namespace,
    id,
    {}
  )
  if extmark == nil then return end

  vim.api.nvim_buf_set_extmark(
    0,
    interface.namespace,
    start_row,
    0,
    { id=id, end_row=end_row }
  )
end


---@param id integer
---@param path string
function interface.change_extmark_content(id, path)
  local map = vim.b.image_extmark_to_path
  if map == nil then return end

  local extmark = vim.api.nvim_buf_get_extmark_by_id(
    0,
    interface.namespace,
    id,
    {}
  )
  if extmark == nil or map[tostring(id)] == nil then return end

  vim.cmd.let(("b:image_extmark_to_path[%d] = '%s'"):format(
    id,
    vim.fn.escape(path, "'\\")
  ))
end

return interface
