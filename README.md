nvim-image-extmarks
===================

A plugin for drawing sixel images from nvim. Uses extmarks to keep track of the locations in the buffer.


Note that this plugin is only meant to expose a convenient API. Images will not be displayed
automatically -- for example, previews in a netrw buffer -- without another plugin.


See also [fence-preview](https://github.com/queue-miscreant/fence-preview), a sister project preview
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

Plugin commands


Lua Functions
-------------

Exposed functions


Keys
----

Plugin keybinds


Configuration
-------------

Global variables


TODOs
-----

- Documentation
- Extra commands
    - Force redraw
    - Suspend drawing
        - All images in insert mode
        - Just those under the cursor in insert mode
    - Push failure message
- Crop thresholds
- Pre-redraw autocmds
