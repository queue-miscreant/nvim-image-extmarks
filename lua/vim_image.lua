local ffi = require "ffi"

ffi.cdef [[
struct winsize {
  unsigned short ws_row;
  unsigned short ws_col;
  unsigned short ws_xpixel;
  unsigned short ws_ypixel;
};
int ioctl(int fd, int cmd, ...);
]]

-- This should be imported ideally, but alas
local TIOCGWINSZ = 0x5413

function get_tty()
  local proc = assert(io.popen("tty"))
  tty_name = proc:read()
  proc:close()

  tty = tty_name
end

function char_pixel_height()
  local buf = ffi.new("struct winsize")
  ffi.C.ioctl(1, TIOCGWINSZ, buf)

  if buf.ws_ypixel > 2 then
    return math.floor(buf.ws_ypixel / buf.ws_row)
  end
  return 28
end

function get_drawing_params()
  local wininfo = vim.fn.getwininfo(vim.fn.win_getid())[1]
  local start_column = wininfo.textoff
  local topline = wininfo.topline

  return {start_column, topline, char_pixel_height()}
end

function draw_sixel(blob, winpos)
  if tty == nil then
    return
  end
  pcall(function()
    local stdout = assert(io.open(tty, "ab"))
    stdout:write(("\x1b[s\x1b[%d;%dH"):format(winpos[1], winpos[2]))
    stdout:write(blob)
    stdout:write("\x1b[u")
    stdout:close()
  end)
end

function draw_sixels(blob_ranges)
  for i, blob_range in ipairs(blob_ranges) do
    draw_sixel(unpack(blob_range))
  end
end

function clear_screen()
  -- clear screen with :mode
  vim.cmd("mode")
  -- clear tmux with tmux detach -E "tmux attach -t (session number)"
  local _, _, _, tmux_pid, tmux_session = tostring(vim.env.TMUX):find("(.+),(%d+),(%d+)")
  if tmux_session ~= nil then
    vim.fn.system(("tmux detach -E 'tmux attach -t %s'"):format(tmux_session))
  end
end

pcall(get_tty)

callbacks = {}

function callbacks.TextChanged()
    local res = vim.fn.VimImageUpdateContent()
end

function callbacks.CursorMoved()
    local res = vim.fn.VimImageRedrawContent()
end


function bind_autocmds()
  vim.cmd [[
  augroup VimImage
    autocmd!
    autocmd VimEnter,TextChanged,InsertLeave <buffer> lua callbacks.TextChanged()
    autocmd VimResized <buffer> lua callbacks.CursorMoved()
    autocmd CursorMoved <buffer> lua callbacks.CursorMoved()
    autocmd InsertEnter <buffer> lua clear_screen()
    autocmd ExitPre,TabClosed,WinClosed,WinLeave <buffer> lua clear_screen()
  augroup END
  ]]
end
