import asyncio
from collections import defaultdict
from dataclasses import dataclass
import logging
from pathlib import Path
import sys
import traceback

from typing import Any, DefaultDict, Dict, List, Optional, Tuple

import pynvim
from pynvim.api import Buffer, Window
from tmux_image.image import path_to_sixel, prepare_blob, CropDims
from tmux_image.delimit import process_content, DEFAULT_REGEXES, Node
from tmux_image.latex import ART_PATH

log = logging.getLogger(__name__)
log.setLevel(logging.DEBUG)

LOGGING_TO_NVIM_LEVELS: DefaultDict[int, int] = defaultdict(
    lambda: 1,
    {
        logging.DEBUG: 1,
        logging.INFO: 1,
        logging.ERROR: 3,
        logging.CRITICAL: 4,
    },
)


def crop_to_range(
    node: Node, column_height_pixels: int, top_line: int, bottom_line: int
) -> Optional[Tuple[Node, CropDims]]:
    crop_top_rows = 0
    crop_bottom_rows = 0
    range_start, range_end = node.range
    height = (range_end - range_start) * column_height_pixels

    if range_end < top_line or range_start > bottom_line:
        return None

    # TODO: mutations
    if range_start < top_line:
        crop_top_rows = top_line - range_start
        range_start = top_line
    if range_end > bottom_line:
        crop_bottom_rows = range_end - bottom_line
        range_end = bottom_line

    node.range = range_start, range_end

    return node, CropDims(
        height=height,
        top_bottom=(
            crop_top_rows * column_height_pixels,
            crop_bottom_rows * column_height_pixels,
        ),
    )


class NvimHandler(logging.Handler):
    def __init__(self, nvim: pynvim.Nvim, level=0):
        super().__init__(level)
        self._nvim = nvim

    def emit(self, record: logging.LogRecord):
        self._nvim.async_call(
            self._nvim.api.notify,
            str(record.getMessage()),
            LOGGING_TO_NVIM_LEVELS[record.levelno],
            {},
        )


# content cache: id to sixel cache
# sixel cache: range to blob


@dataclass
class SixelCache:
    content_id: str
    blob_cache: Dict[CropDims, str]


@pynvim.plugin
class NvimImage:
    def __init__(self, nvim: pynvim.Nvim):
        self.nvim = nvim
        self._handler = NvimHandler(nvim, level=logging.INFO)

        self._content_cache: Dict[str, SixelCache] = {}

        # TODO: configurable
        self._regexes = DEFAULT_REGEXES

        if not ART_PATH.exists():
            ART_PATH.mkdir()

        nvim.loop.set_exception_handler(self.handle_exception)
        logging.getLogger().addHandler(self._handler)

    @pynvim.command("OpenImage", nargs=1, range=True, sync=True, complete="file")
    def open_image(self, args: List[str], range: Tuple[int, int]) -> None:
        start, end = range

        drawing_params: Tuple[int | None, int | None, int] = (
            self.nvim.lua.get_drawing_params()
        )
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
                (end - start) * column_height_pixels,
            )
        )

    @pynvim.function("VimImageUpdateContent", sync=True)
    def update_content(self, args: List[str]):
        buffer: Buffer = self.nvim.current.buffer
        # this can be async
        nodes = process_content(
            buffer[:],
            self._regexes,
        )

        # this must be sync
        # this should get all windows in the current tabpage!
        drawing_params: Tuple[int | None, int | None, int] = (
            self.nvim.lua.get_drawing_params()
        )
        start_column, _, column_height_pixels = drawing_params
        if start_column is None:
            log.critical("Could not get top line of window or starting column!")
            return

        # TODO: duplicated
        wininfo = self.nvim.call("getwininfo", self.nvim.call("win_getid"))

        top_line = wininfo[0].get("topline")
        bottom_line = wininfo[0].get("botline")

        window: Window = self.nvim.current.window
        row, col = (window.row, window.col)

        # combine ranges from this (buffer content) and the window view
        visible_nodes = [
            cropped
            for cropped in (
                crop_to_range(node, column_height_pixels, top_line, bottom_line)
                for node in nodes
            )
            if cropped is not None
        ]
        log.debug(visible_nodes)

        async def do_stuff() -> None:
            loop: asyncio.AbstractEventLoop = self.nvim.loop
            # start processing new sixel content in another thread
            blobs = await asyncio.gather(
                *(
                    loop.run_in_executor(None, prepare_blob, *node)
                    for node in visible_nodes
                )
            )
            # update_cache(self._content_cache, blobs)

            params = [
                (
                    node_blob[1],
                    (
                        row + (node_blob[0].range[0] - top_line) + 1,
                        col + start_column + 1,
                    ),
                )
                for node_blob in blobs
                if node_blob is not None
            ]

            self.nvim.async_call(self.nvim.lua.draw_sixels, params)

        asyncio.create_task(do_stuff())

        # TODO: push blobs to lua for speed?

    def handle_exception(self, _: asyncio.AbstractEventLoop, context: Any) -> None:
        if (exception := context.get("exception")) is None or not isinstance(
            exception, Exception
        ):
            message = context.get("message")
            log.error("Handler got non-exception: %s", message)
            return
        if sys.version_info >= (3, 10):
            formatted = traceback.format_exception(exception)
        elif hasattr(exception, "__traceback__"):
            formatted = traceback.format_exception(
                type(exception), exception, exception.__traceback__
            )
        else:
            formatted = "(Could not get stack trace)"

        log.error(f"Error occurred:\n{''.join(formatted)}")
        log.debug("", exc_info=True)

    def _draw_sixel(self, path: Path, target_height: int):
        return path_to_sixel(
            path,
            CropDims(height=target_height, top_bottom=None),
        )

    async def draw_sixel(
        self, path: Path, start: Tuple[int, int], target_height: int
    ) -> None:
        loop: asyncio.AbstractEventLoop = self.nvim.loop
        sixel = await loop.run_in_executor(None, self._draw_sixel, path, target_height)
        self.nvim.async_call(
            self.nvim.lua.draw_sixel,
            sixel,
            start,
        )
