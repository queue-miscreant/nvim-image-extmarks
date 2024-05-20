from dataclasses import dataclass
import logging
from pathlib import Path

from typing import Optional, Tuple

from wand.image import Image

from tmux_image.delimit import Node, ContentType

log = logging.getLogger(__name__)
log.setLevel(logging.DEBUG)

@dataclass
class CropDims:
    height: int
    top_bottom: Optional[Tuple[int, int]]


def to_sixel(path: Path, dims: CropDims) -> Optional[bytes]:
    if not path.exists():
        raise ValueError("File does not exist")

    with Image(filename=str(path)) as img:
        factor = dims.height / img.height
        # log.debug("%s %s", factor, img.width)
        # log.debug(img.height)
        img.resize(int(img.width * factor), int(img.height * factor))

        if dims.top_bottom is not None:
            top, bottom = dims.top_bottom
            img.crop(top=top, height=img.height-bottom)

        return img.make_blob("sixel")


def generate_content(node: Node, dims: CropDims) -> Optional[Tuple[Node, bytes]]:
    blob = None
    if node.content_type == ContentType.FILE:
        try:
            blob = to_sixel(Path(node.content).expanduser(), dims)
        except ValueError as exc:
            log.error(exc.args[0])
            log.debug("", exc_info=True)
            return None
    else:
        pass

    if blob is None:
        return None

    return node, blob
