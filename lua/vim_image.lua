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

function draw_sixel(blob, winpos)
  if tty == nil then
    return
  end
  pcall(function()
    local stdout = assert(io.open(tty, "ab"))
    stdout:write(string.format("\x1b[s\x1b[%d;%dH", winpos[1], winpos[2]))
    stdout:write(blob)
    stdout:write("\x1b[u")
    stdout:close()
  end)
end

pcall(get_tty)
