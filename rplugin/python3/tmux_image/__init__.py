import asyncio
import logging
import sys
import traceback

import pynvim
from tmux_image.image import *

log = logging.getLogger("vimcord")
log.setLevel(logging.ERROR)

@pynvim.plugin
class Vimcord:
    def __init__(self, nvim):
        self.nvim = nvim
        self.tty = None
        nvim.loop.set_exception_handler(self.handle_exception)

    @pynvim.command("OpenImage", nargs=1, range=True, sync=True, complete="file")
    def open_image(self, args, range):
        pixel_height = self.nvim.lua.char_pixel_height()
        window = self.nvim.current.window
        start, end = range
        row, col = (window.row, window.col)
        topline = self.nvim.call("winsaveview").get("topline", 1)

        asyncio.create_task(
            self.draw_sixel(
                Path(args[0]),
                (row + (start - topline) + 1, col + 1),
                end - start,
                pixel_height
            )
        )

    # @pynvim.function("FunctionName", sync=True)
    # def run_function(self, args):
    #     pass

    def handle_exception(self, loop, context):
        if (exception := context.get("exception")) is None or not isinstance(exception, Exception):
            message = context.get("message")
            log.error("Handler got non-exception: %s", message)
            self.notify(message, level=0)
            return
        if sys.version_info >= (3, 10):
            formatted = traceback.format_exception(exception)
        elif hasattr(exception, "__traceback__"):
            formatted = traceback.format_exception(
                type(exception),
                exception,
                exception.__traceback__
            )
        else:
            formatted = "(Could not get stack trace)"

        error_text = f"Error occurred:\n{''.join(formatted)}"
        log.error(error_text)
        self.notify(error_text)

    def notify(self, msg, level=4):
        self.nvim.async_call(self.nvim.api.notify, msg, level, {})


    def _draw_sixel(self, path: Path, column_height: int, pixel_height):
        return to_sixel(
            path,
            CropDims(height=column_height*pixel_height, top_bottom=None),
        )

    async def draw_sixel(self, path: Path, start: Tuple[int, int], row_height: int, pixel_height):
        loop: asyncio.AbstractEventLoop = self.nvim.loop
        sixel = await loop.run_in_executor(None, self._draw_sixel, path, row_height, pixel_height)
        self.nvim.async_call(
            self.nvim.lua.draw_sixel,
            sixel,
            start,
        )
