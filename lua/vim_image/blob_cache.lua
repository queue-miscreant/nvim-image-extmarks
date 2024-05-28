local sixel_raw = require "vim_image/sixel_raw"

local blob_cache = { contents = {} }


-- Blobs are cached by the following characteristics:
--
-- - Layer 1:
--      - Content hash
-- - Layer 2:
--      - Height, in rows
--      - Crop from top of image, in rows
--      - Crop from bottom of image (i.e., number of rows removed, as a full image)


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
---@param path string
---@param extmark wrapped_extmark
function blob_cache.insert(blob, path, extmark)
  local index = extmark_to_cache_id(extmark)

  if blob_cache.contents[path] ~= nil then
    blob_cache.contents[path][index] = blob
  else
    local temp = {}
    temp[index] = blob
    blob_cache.contents[path] = temp
  end
end


---@param path string
---@param extmark wrapped_extmark
function blob_cache.get(path, extmark)
  local cached = blob_cache.contents[path]
  if cached == nil then
    return nil
  end

  local index = extmark_to_cache_id(extmark)
  if cached[index] == nil then
    return nil
  end

  return cached[index]
end

---@param path? (string | string[])
function blob_cache.clear(path)
  if path == nil then
    blob_cache.contents = {}
  elseif type(path) == "table" then
    for _, path_ in ipairs(path) do
      blob_cache.contents[path_] = {}
    end
  elseif type(path) == "string" then
    blob_cache.contents[path] = {}
  else
    assert(false, "Invalid argument")
  end

  collectgarbage()
end


return blob_cache
