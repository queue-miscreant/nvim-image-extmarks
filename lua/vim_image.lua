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


function DrawInner()
    -- local res = s:inst.call("draw", [""], "string") 
    -- local res = json_decode(res)
    local res = {}

    if res.err ~= nil then
	vim.api.nvim_notify("Error: " .. res.err, 4, {})
    elseif res.ok == 1 then
	Draw()
    end
end

function Draw()
    if timer ~= nil then
        timer:stop()
    end

    timer = vim.loop.new_timer()
    timer:start(50, 0, function() DrawInner() end)
end

local callbacks = {}

function callbacks.TextChanged()
    -- call s:UpdateMetadata()
    -- local current_buf = table.concat(
    --   vim.fn.getline(1, '$'),
    --   "\n",
    -- )
    local res = vim.fn.VimImageUpdateContent()
    -- let res = json_decode(res)['ok']

    if res.update_folding ~= nil then
        local folds = res.update_folding
        -- call s:UpdateFolds()
    end
    if res.should_redraw then
        Draw()
    end
end


function bind_autocmds()
  vim.cmd [[
  augroup VimImage
      autocmd!
    autocmd VimEnter,TextChanged,InsertLeave * lua callbacks.TextChanged()
    " autocmd VimResized * lua <SID>UpdateMetadata()
    " autocmd CursorMoved * lua <SID>UpdateMetadata()
    autocmd InsertEnter * lua clear_screen()
  augroup END
  ]]
end
