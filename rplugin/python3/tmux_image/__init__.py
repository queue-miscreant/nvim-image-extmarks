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
from tmux_image.image import path_to_sixel, prepare_blob, SixelCache, CropDims
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
class WindowDims:
    top_line: int
    bottom_line: int
    start_line: int
    window_column: int
    start_column: int


@dataclass
class WindowDisplay:
    dims: WindowDims
    nodes: Optional[List[Tuple[Node, CropDims]]]


def window_to_terminal(start_row: int, dims: WindowDims):
    '''Convert window coordinates (start_row, end_row) to terminal coordinates'''
    row = dims.start_line + start_row - dims.top_line
    column = dims.window_column + dims.start_column

    return row, column


@pynvim.plugin
class NvimImage:
    def __init__(self, nvim: pynvim.Nvim):
        self.nvim = nvim
        self._handler = NvimHandler(nvim, level=logging.INFO)

        self._content_cache: Dict[int, List[Node]] = {}
        self._sixel_cache: Dict[str, SixelCache] = {}

        # TODO: configurable
        self._regexes = DEFAULT_REGEXES
        self._last_window_display: Dict[int, WindowDisplay] = {}

        if not ART_PATH.exists():
            ART_PATH.mkdir()

        nvim.loop.set_exception_handler(self.handle_exception)
        logging.getLogger().addHandler(self._handler)

    def update_window_cache(self) -> Optional[WindowDisplay]:
        wininfo = self.nvim.call("getwininfo", self.nvim.call("win_getid"))

        window_id = wininfo[0].get("winid")
        new_dims = WindowDims(
            top_line = wininfo[0].get("topline"),
            bottom_line = wininfo[0].get("botline"),
            start_line = wininfo[0].get("winrow"),
            window_column = wininfo[0].get("wincol"),
            start_column = wininfo[0].get("textoff"),
        )
        if new_dims.top_line is None or new_dims.start_column is None:
            log.critical("Could not get top line of window or starting column!")
            return None

        display = self._last_window_display.get(window_id)
        if display is None:
            display = WindowDisplay(
                dims=new_dims,
                nodes=None,
            )
            self._last_window_display[window_id] = display
        else:
            if new_dims != display.dims:
                display.nodes = None
            display.dims = new_dims

        return display

    @pynvim.command("OpenImage", nargs=1, range=True, sync=True, complete="file")
    def open_image(self, args: List[str], range: Tuple[int, int]) -> None:
        start, end = range

        drawing_params: Tuple[int | None, int | None, int] = (
            self.nvim.lua.get_drawing_params()
        )
        _, __, column_height_pixels = drawing_params

        display = self.update_window_cache()
        if display is None:
            return

        self.nvim.lua.sixel_raw.clear_screen()
        asyncio.create_task(
            self.draw_sixel(
                Path(args[0]),
                window_to_terminal(start, display.dims),
                (end - start) * column_height_pixels,
            )
        )

    @pynvim.function("VimImageUpdateContent", sync=True)
    def update_content(self, args: List[str]):
        buffer: Buffer = self.nvim.current.buffer
        # This can be async from nvim...
        nodes = process_content(
            buffer[:],
            self._regexes,
        )
        self._content_cache[buffer.number] = nodes
        # ...but this can't be
        self.draw_visible(nodes, force=True)

    @pynvim.function("VimImageRedrawContent", sync=True)
    def redraw_content(self, args: List[str]):
        buffer: Buffer = self.nvim.current.buffer
        if (nodes := self._content_cache.get(buffer.number)) is not None:
            self.draw_visible(nodes)

    def draw_visible(self, nodes: List[Node], force=False):
        # this must be sync
        # this should get all windows in the current tabpage!
        drawing_params: Tuple[int | None, int | None, int] = (
            self.nvim.lua.get_drawing_params()
        )
        _, __, column_height_pixels = drawing_params

        display = self.update_window_cache()
        if display is None:
            return

        if display.nodes is None or force:
            # combine ranges from this (buffer content) and the window view
            visible_nodes = [
                cropped
                for cropped in (
                    crop_to_range(node, column_height_pixels, display.dims.top_line, display.dims.bottom_line)
                    for node in nodes
                )
                if cropped is not None
            ]
            for node in self._content_cache[self.nvim.current.buffer.number]:
                for visible, _ in visible_nodes:
                    if node.content_id == visible.content_id:
                        node.range = visible.range
                        break
            display.nodes = visible_nodes
        else:
            return

        async def do_stuff() -> None:
            loop: asyncio.AbstractEventLoop = self.nvim.loop
            # start processing new sixel content in another thread
            blobs = await asyncio.gather(
                *(
                    loop.run_in_executor(None, prepare_blob, node, dims, self._sixel_cache)
                    for node, dims in visible_nodes
                )
            )

            params = [
                (
                    node_blob[1],
                    window_to_terminal(node_blob[0].range[0], display.dims)
                )
                for node_blob in blobs
                if node_blob is not None
            ]

            self.nvim.async_call(self.nvim.lua.sixel_raw.draw_sixels, params)

        self.nvim.lua.sixel_raw.clear_screen()
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
            self.nvim.lua.sixel_raw.draw_sixel,
            sixel,
            start,
        )
