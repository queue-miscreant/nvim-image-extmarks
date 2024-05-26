nvim-image-extmarks
===================

A plugin for drawing sixel images from nvim. Uses extmarks to keep track of the locations in the buffer.


Requirements
------------

- ImageMagick with support for sixel blobs
    - Run `magick -list format | grep -i sixel` to check


Installation
------------

### Vundle

<!--
Place the following in `~/.config/nvim/init.vim`:
```vim
Plugin '...'
```
Make sure the file is sourced and run `:PluginInstall`.
-->


Commands
--------

Plugin commands


Functions
---------

Exposed functions


Keys
----

Plugin keybinds


Configuration
-------------

Global variables


TODOs
-----

- Extra commands
    - Force redraw
    - Suspend drawing
    - Push failure message
- Crop thresholds
- Pre-redraw autocmds
