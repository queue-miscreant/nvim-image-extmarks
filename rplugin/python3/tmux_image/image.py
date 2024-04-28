from dataclasses import dataclass
from pathlib import Path
from wand.image import Image

from typing import Optional, Tuple

@dataclass
class CropDims:
    height: int
    top_bottom: Optional[Tuple[int, int]]

def to_sixel(path: Path, dims: CropDims) -> Optional[bytes]:
    if not path.exists():
        raise ValueError("File does not exist")

    with Image(filename=str(path)) as img:
        factor = dims.height / img.height
        img.resize(int(img.width * factor), int(img.height * factor))

        if dims.top_bottom is not None:
            top, bottom = dims.top_bottom
            img.crop(img.width, top, 0, bottom)

        return img.make_blob("sixel")
