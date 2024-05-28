if !has("nvim")
  echo "Plugin not supported outside of nvim"
  finish
endif

lua require "nvim_image_extmarks"

let g:nvim_image_extmarks_loaded = 1
