if !has("nvim")
  echo "Plugin not supported outside of nvim"
  finish
endif

lua require "vim_image"

let g:nvim_image_extmarks_loaded = 1
