require "vim_image/sixel_raw"
require "vim_image/sixel_interface"

sixel_interface:init()

function get_drawing_params()
  local wininfo = vim.fn.getwininfo(vim.fn.win_getid())[1]
  local start_column = wininfo.textoff
  local topline = wininfo.topline

  return {start_column, topline, sixel_raw.char_pixel_height()}
end

callbacks = {}

function callbacks.TextChanged()
    -- local res = vim.fn.VimImageUpdateContent()
    sixel_interface:draw_visible_blobs()
end

function callbacks.CursorMoved()
    -- local res = vim.fn.VimImageRedrawContent()
    sixel_interface:draw_visible_blobs()
end


function bind_autocmds()
  vim.cmd [[
  augroup VimImage
    autocmd!
    autocmd VimEnter,TextChanged,InsertLeave <buffer> lua callbacks.TextChanged()
    autocmd VimResized <buffer> lua callbacks.CursorMoved()
    autocmd CursorMoved <buffer> lua callbacks.CursorMoved()
    autocmd InsertEnter <buffer> lua sixel_raw.clear_screen()
    autocmd ExitPre,TabClosed,WinClosed,WinLeave <buffer> lua sixel_raw.clear_screen()
  augroup END
  ]]
end
