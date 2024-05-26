if !has("nvim")
  echo "Plugin not supported outside of nvim"
  finish
endif

lua require "vim_image"
