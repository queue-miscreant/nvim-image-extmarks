nvim-image-extmarks
===================

A plugin for drawing sixel images from nvim. Uses extmarks to keep track of the locations in the buffer.

[Sixels](https://en.wikipedia.org/wiki/Sixel) are a blob of binary data which, when written to a
supported terminal, display an image. To see if your terminal is supoorted, a good resource to check is
[Are We Sixel Yet?](https://www.arewesixelyet.com/).

Note that this plugin is only meant to expose a convenient API. Images will not be displayed
automatically - for example, previews in a netrw buffer - without another plugin.

See also [fence-preview](https://github.com/queue-miscreant/fence-preview), a sister project to preview
markdown-formatted content like LaTeX.


Requirements
------------

- A terminal emulator that can display sixels
    - A good resource to check is [Are We Sixel Yet?](https://www.arewesixelyet.com/)
- ImageMagick with support for sixel blobs
    - Run `magick -list format | grep -i sixel` to check


Installation
------------

### Vundle

Place the following in `~/.config/nvim/init.vim`:
```vim
Plugin 'queue-miscreant/nvim_image_extmarks'
```
Make sure the file is sourced and run `:PluginInstall`.


Commands
--------

### `:[range]CreateImage {filepath}`

Create an image extmark with the given filename at the range
specified. This wraps `sixel_extmarks.create` below.


Lua Functions
-------------

### `sixel_extmarks.create`

`sixel_extmarks.create(
  start_row: integer,
  end_row: integer,
  path: string
) -> integer`

Create a new image extmark which stretches from (0-indexed) row
`start_row` to row `end_row` of the buffer and has content
from the file at `path`.


### `sixel_extmarks.get`

`sixel_extmarks.get(
  start_row: integer,
  end_row: integer
) -> image_extmark[]`

Retrieve a list of image extmarks in the current buffer between
(0-indexed) rows `start_row` and `end_row`.
To get all extmarks, set `start_row` to 0 and `end_row` to -1.

The return value is a table with the following the structure:

|-------------|------------|-------------------------------------------------|
|`id`         | integer    | The id of the extmark                           |
|`start_row`  | integer    | The (0-indexed) row that the extmark starts on  |
|`end_row`    | integer    | The (0-indexed) row that the extmark ends on    |
|`path`       | string     | A path to the current content                   |
|-------------|------------|-------------------------------------------------|

### `sixel_extmarks.remove`

`sixel_extmarks.remove(id: integer)`

Delete the extmark in the current buffer identified by `id`. This does NOT free
from the cache any of the blobs generated from the file the extmark points to.


### `sixel_extmarks.remove_all`

`sixel_extmarks.remove_all()`

Delete all extmarks in the current buffer. The same caveat about the
cache applies here as well.


### `sixel_extmarks.move`

`sixel_extmarks.move(id: integer, start_row: integer, end_row: integer)`

Move the extmark identified by `id` so that the image stretches
starting at row `start_row` of the buffer and ends at `end_row`.
Be aware that this can resize the image.


### `sixel_extmarks.change_content`

`sixel_extmarks.change_content(id: integer, path: string)`

Change the content of the extmark identified by `id` to the file at
`path`.


### `sixel_extmarks.clear_cache`

`sixel_extmarks.clear_cache()`
`sixel_extmarks.clear_cache(path: string)`
`sixel_extmarks.clear_cache(paths: string[])`

Clear the sixel blob cache. If no argument is supplied, then the entire
cache is cleared.

If `path`, a single string argument is supplied, then only the blobs
for that file are removed.

If `paths`, a list of strings are supplied, then all blobs for those
files in the list are removed. 


### `sixel_extmarks.clear_screen`

`sixel_extmarks.clear_screen()`

Clear all content drawn to the screen. Unlike `:mode`, this has the
additional guarantee of working inside a tmux session.


Configuration
-------------

None yet


TODOs
-----

- Documentation
- Extra commands
    - Force redraw
    - Suspend drawing
        - All images in insert mode
        - Just those under the cursor in insert mode
    - Push failure message
- Buffering redraws until the cursor stays still enough
- Crop thresholds
- Pre-redraw autocmds
