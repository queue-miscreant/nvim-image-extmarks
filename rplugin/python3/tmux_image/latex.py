import logging
from pathlib import Path
import shutil
import subprocess

from tmux_image.delimit import hash_content, Node, ContentType

log = logging.getLogger(__name__)

ART_PATH = Path("/tmp/nvim_arts/")

MATH_START = """
\\documentclass[20pt, preview]{standalone}
\\nonstopmode
\\usepackage{amsmath,amsfonts,amsthm}
\\usepackage{xcolor}
\\begin{document}
$$
"""

MATH_END = """
$$
\\end{document}
"""


def path_from_content(node: Node) -> Path:
    content_hash = node.content_id
    if node.content_type == ContentType.FILE:
        return Path(node.content).expanduser()
    return Path(ART_PATH, content_hash).with_suffix(".svg")


# Parse an equation with the given zoom
def parse_equation(
    node: Node,
    zoom: float,
) -> Path:
    path = Path(ART_PATH, node.content_id).with_suffix(".svg")

    # create a new tex file containing the equation
    tex_path = path.with_suffix(".tex")
    if not tex_path.exists():
        with open(tex_path, "w") as file:
            file.writelines([MATH_START, node.content, MATH_END])

    return generate_svg_from_latex(path, zoom)


def parse_latex_output(buf: str):
    err = ["", "", None]
    for elm in buf.split("\n"):
        log.error(elm)
        if elm.startswith("! "):
            err[0] = elm
        elif elm.startswith("l.") and elm.find("Emergency stop") == -1:
            elms = elm.removeprefix("1.")
            if elm == elms:
                continue

            elm_one, _, rest = elms.partition(" ")
            elm_two, _, rest = rest.partition(" ")
            try:
                err[2] = elm_one
            except ValueError:
                pass

            if elm_two != "":
                err[1] = elm_two

    return err


def generate_svg_from_latex(path: Path, zoom: float) -> Path:
    # TODO: In rust, these are typed as Maybes and used unwrap()
    dest_path = path.parent

    # use latex to generate a dvi
    dvi_path = path.with_suffix(".dvi")
    if not dvi_path.exists():
        latex_path = shutil.which("latex")
        if latex_path is None:
            raise RuntimeError("Could not find LaTeX installation!")

        cmd = subprocess.Popen(
            [latex_path, str(path.with_suffix(".tex"))],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=dest_path,
        )
        # .arg("--jobname").arg(&dvi_path)
        # .expect("Could not spawn latex");

        stdout, stderr = cmd.communicate()

        retval = cmd.wait()
        # if retval != 0:
        if False:
            buf = stdout.decode()

            # latex prints error to the stdout, if this is empty, then something is fundamentally
            # wrong with the latex binary (for example shared library error). In this case just
            # exit the program
            if buf == "":
                buf = stderr.decode()
                raise RuntimeError(f"Latex exited with `{buf}`")

            raise RuntimeError(parse_latex_output(buf))

    # convert the dvi to a svg file with the woff font format
    svg_path = path.with_suffix(".svg")
    if not svg_path.exists() and dvi_path.exists():
        dvisvgm_path = shutil.which("dvisvgm")
        if dvisvgm_path is None:
            raise RuntimeError("Could not find dvisvgm!")

        cmd = subprocess.Popen(
            [dvisvgm_path, "-b", "1", "--no-fonts", f"--zoom={zoom}", str(dvi_path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=dest_path,
        )

        stdout, stderr = cmd.communicate()

        retval = cmd.wait()
        buf = stderr.decode()
        if retval != 0 or buf.find("error:") != -1:
            buf = stdout.decode()

            raise RuntimeError(buf)

    return path


def generate_latex_from_gnuplot(content: str) -> Path:
    """
    Generate latex file from gnuplot

    This function generates a latex file with gnuplot `epslatex` backend and then source it into
    the generate latex function
    """
    path = (Path(ART_PATH) / hash_content(content)).with_suffix(".tex")

    gnuplot_path = shutil.which("gnuplot")
    if gnuplot_path is None:
        raise RuntimeError("Could not find gnuplot!")

    cmd = subprocess.Popen(
        [gnuplot_path, "-p"],
        stdin=subprocess.PIPE,
        cwd=ART_PATH,
    )
    # .expect("Could not spawn gnuplot");

    cmd.communicate(
        f"set output '{str(path)}'\nset terminal epslatex color standalone\n{content}".encode()
    )

    return path


def generate_latex_from_gnuplot_file(path: Path) -> Path:
    with open(path) as gnuplot_file:
        content = gnuplot_file.read()

    path = generate_latex_from_gnuplot(content)
    return generate_svg_from_latex(path, 1.0)


def parse_latex(
    content: str,
) -> Path:
    """Parse a latex content and convert it to a SVG file"""
    path = (Path(ART_PATH) / hash_content(content)).with_suffix(".svg")

    # create a new tex file containing the equation
    tex_path = path.with_suffix(".tex")
    if not tex_path.exists():
        with open(tex_path, "w") as file:
            file.write(content)

    if not path.exists():
        generate_svg_from_latex(path, 1.0)

    return path


def parse_latex_from_file(
    path: Path,
) -> Path:
    with open(path, "w") as file:
        content = file.read()
        return parse_latex(content)
