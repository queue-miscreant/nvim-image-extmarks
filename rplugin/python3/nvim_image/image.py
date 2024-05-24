from dataclasses import dataclass
import logging
from pathlib import Path

from typing import Optional, Dict, Tuple

from wand.image import Image

from nvim_image.delimit import Node, ContentType
from nvim_image.latex import (
    path_from_content,
    parse_equation,
    parse_latex,
    parse_latex_from_file,
    generate_svg_from_latex,
    generate_latex_from_gnuplot,
    generate_latex_from_gnuplot_file,
)

log = logging.getLogger(__name__)
log.setLevel(logging.DEBUG)


@dataclass(frozen=True)
class CropDims:
    height: int
    top_bottom: Optional[Tuple[int, int]]


@dataclass
class SixelCache:
    content_id: str
    blob_cache: Dict[CropDims, bytes]


def image_to_sixel(image: Image, dims: CropDims) -> Optional[bytes]:
    factor = dims.height / image.height
    # log.debug("%s %s", factor, img.width)
    # log.debug(img.height)
    image.resize(int(image.width * factor), int(image.height * factor))

    if dims.top_bottom is not None:
        top, bottom = dims.top_bottom
        image.crop(top=top, height=image.height - bottom)

    return image.make_blob("sixel")


def path_to_sixel(path: Path, dims: CropDims) -> Optional[bytes]:
    if not path.exists():
        raise ValueError("File does not exist")

    with Image(filename=str(path)) as img:
        return image_to_sixel(img, dims)


def prepare_blob(node: Node, dims: CropDims, sixel_cache: Dict[str, SixelCache]) -> Optional[Tuple[Node, bytes]]:
    if (cache := sixel_cache.get(node.content_id)) and dims in cache.blob_cache:
        return node, cache.blob_cache[dims]
    image = generate_content(node)
    blob = image_to_sixel(image, dims)

    if blob is None:
        return None

    if node.content_id not in sixel_cache:
        sixel_cache[node.content_id] = SixelCache(node.content_id, {})
    sixel_cache[node.content_id].blob_cache[dims] = blob

    return node, blob


def generate_content(node: Node) -> Image:
    path = path_from_content(node)
    missing = not path.exists()

    if missing:
        if node.content_type == ContentType.FILE:
            raise FileNotFoundError(f"Could not find file {path}!")
        if node.content_type == ContentType.MATH:
            path = parse_equation(node, 1.0)
        elif node.content_type == ContentType.TEX:
            path = parse_latex(node.content)
        elif node.content_type == ContentType.GNUPLOT:
            new_path = generate_latex_from_gnuplot(node.content)
            generate_svg_from_latex(path, 1.0)

    # // rewrite path if ending as tex or gnuplot file
    if node.content_type == ContentType.FILE:
        if path.suffix == ".tex":
            path = parse_latex_from_file(path)
        elif path.suffix == ".plt":
            new_path = generate_latex_from_gnuplot_file(path)
            path = new_path.with_suffix(".svg")

    image = Image(resolution=(600.0, 600.0), filename=str(path))
    # image.compression_quality = 5
    # image.transform_colorspace("gray")
    # image.quantize(8, "gray", 0, False, False)
    return image
