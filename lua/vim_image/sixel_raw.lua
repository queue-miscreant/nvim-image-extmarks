-- sixel_raw.lua
--
-- "Low-level" sixel drawing functions, such as drawing blobs to the tty, clearing
-- the screen safely, and getting the character height for drawing.

local ffi = require "ffi"

---@class window_dimensions
---@field top_line integer
---@field bottom_line integer
---@field start_line integer
---@field window_column integer
---@field start_column integer

sixel_raw = { tty=nil }

-- Ideally, this would be imported, but alas
local TIOCGWINSZ = 0x5413

-- ioctl definition
ffi.cdef [[
struct winsize {
  unsigned short ws_row;
  unsigned short ws_col;
  unsigned short ws_xpixel;
  unsigned short ws_ypixel;
};
int ioctl(int fd, int cmd, ...);
]]

-- Perform the above ioctl operation and calculate the height of a character in pixels
---@return number
function sixel_raw.char_pixel_height()
  local buf = ffi.new("struct winsize")
  ffi.C.ioctl(1, TIOCGWINSZ, buf)

  if buf.ws_ypixel > 2 then
    return math.floor(buf.ws_ypixel / buf.ws_row)
  end
  return 28
end

-- Acquire the tty filename and store it for use later
function sixel_raw.get_tty()
  local proc = assert(io.popen("tty"))
  local tty_name = proc:read()
  proc:close()

  sixel_raw.tty = tty_name
end

-- Draw a sixel to the display
-- Move the cursor to (row, column) (1-indexed), draw the blob, then reset the cursor position
---@param blob string
---@param winpos [integer, integer]
function sixel_raw.draw_sixel(blob, winpos)
  if sixel_raw.tty == nil then
    vim.notify("Could not find the terminal device!", 3, {})
    return
  end

  pcall(function()
    local stdout = assert(io.open(sixel_raw.tty, "ab"))
    stdout:write(("\x1b[s\x1b[%d;%dH"):format(winpos[1], winpos[2]))
    stdout:write(blob)
    stdout:write("\x1b[u")
    stdout:close()
  end)
end

-- The same thing as draw_sixel, but operating on a table of blob, position pairs
--
---@param blob_ranges [string, [integer, integer]][]
function sixel_raw.draw_sixels(blob_ranges)
  if sixel_raw.tty == nil then
    vim.notify("Could not find the terminal device!", 3, {})
    return
  end

  pcall(function()
    local stdout = assert(io.open(sixel_raw.tty, "ab"))
    stdout:write("\x1b[s")

    for _, blob_range in ipairs(blob_ranges) do
      local winpos = blob_range[2]
      stdout:write(("\x1b[%d;%dH"):format(winpos[1], winpos[2]))
      stdout:write(blob_range[1])
    end

    stdout:write("\x1b[u")
    stdout:close()
  end)
end

-- Clear the screen of all sixel characters
-- This should also work in tmux, where sixel images can appear "sticky"
function sixel_raw.clear_screen()
  -- clear screen with :mode
  vim.cmd("mode")
  -- clear tmux with tmux detach -E "tmux attach -t (session number)"
  local _, _, _, tmux_pid, tmux_session = tostring(vim.env.TMUX):find("(.+),(%d+),(%d+)")
  if tmux_session ~= nil then
    vim.fn.system(("tmux detach -E 'tmux attach -t %s'"):format(tmux_session))
  end
end

---@return window_dimensions
function sixel_raw.get_windims()
  local wininfo = vim.fn.getwininfo(vim.fn.win_getid())

  return {
      top_line = wininfo[1].topline,
      bottom_line = wininfo[1].botline,
      start_line = wininfo[1].winrow,
      window_column = wininfo[1].wincol,
      start_column = wininfo[1].textoff,
  }
end