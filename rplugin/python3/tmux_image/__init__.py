import asyncio
from collections import defaultdict
import logging
from pathlib import Path
import sys
import traceback

from typing import Any, DefaultDict, Dict, List, Tuple

import pynvim
from pynvim.api import Buffer, Window
from tmux_image.image import to_sixel, CropDims
from tmux_image.delimit import process_content, DEFAULT_REGEXES

log = logging.getLogger(__name__)
log.setLevel(logging.DEBUG)

LOGGING_TO_NVIM_LEVELS: DefaultDict[int, int] = defaultdict(lambda: 1, {
    logging.DEBUG: 1,
    logging.INFO: 1,
    logging.ERROR: 3,
    logging.CRITICAL: 4,
})


class NvimHandler(logging.Handler):
    def __init__(self, nvim: pynvim.Nvim, level=0):
        super().__init__(level)
        self._nvim = nvim

    def emit(self, record: logging.LogRecord):
        self._nvim.async_call(
            self._nvim.api.notify,
            str(record.msg),
            LOGGING_TO_NVIM_LEVELS[record.levelno],
            {},
        )


# content cache: id to sixel cache
# sixel cache: range to blob


@pynvim.plugin
class NvimImage:
    def __init__(self, nvim: pynvim.Nvim):
        self.nvim = nvim
        self._handler = NvimHandler(nvim, level=logging.INFO)

        # self._content_cache: Dict[str, SixelCache] = {}

        # TODO: configurable
        self._regexes = DEFAULT_REGEXES

        nvim.loop.set_exception_handler(self.handle_exception)
        logging.getLogger().addHandler(self._handler)


    @pynvim.command("OpenImage", nargs=1, range=True, sync=True, complete="file")
    def open_image(self, args: List[str], range: Tuple[int, int]) -> None:
        start, end = range

        drawing_params: Tuple[int | None, int | None, int] = self.nvim.lua.get_drawing_params()
        start_column, topline, column_height_pixels = drawing_params

        if topline is None or start_column is None:
            log.critical("Could not get top line of window or starting column!")
            return

        window: Window = self.nvim.current.window
        row, col = (window.row, window.col)

        asyncio.create_task(
            self.draw_sixel(
                Path(args[0]),
                (row + (start - topline) + 1, col + start_column + 1),
                (end - start)*column_height_pixels,
            )
        )

    @pynvim.function("VimImageUpdateContent", sync=True)
    def update_content(self, args: List[str]):
        buffer: Buffer = self.nvim.current.buffer
        nodes = process_content(
            buffer[:],
            self._regexes,
        )
        # TODO: update content cache

        # TODO: combine ranges from this (buffer content) and the window view

        # TODO: start processing new sixel content in another thread
        # use asyncio.Future for running tasks, then update their sixel cache (range to blobs)


    def handle_exception(self, _: asyncio.AbstractEventLoop, context: Any) -> None:
        if (exception := context.get("exception")) is None or not isinstance(exception, Exception):
            message = context.get("message")
            log.error("Handler got non-exception: %s", message)
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

        log.error(f"Error occurred:\n{''.join(formatted)}")
        log.debug("", exc_info=True)


    def _draw_sixel(self, path: Path, target_height: int):
        return to_sixel(
            path,
            CropDims(height=target_height, top_bottom=None),
        )

    async def draw_sixel(self, path: Path, start: Tuple[int, int], target_height: int) -> None:
        loop: asyncio.AbstractEventLoop = self.nvim.loop
        sixel = await loop.run_in_executor(None, self._draw_sixel, path, target_height)
        self.nvim.async_call(
            self.nvim.lua.draw_sixel,
            sixel,
            start,
        )
