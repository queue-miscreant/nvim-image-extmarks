nvim-image
==========

A plugin for drawing sixel images from nvim. Somewhat of a reimplementation of [vim-graphical-preview](https://github.com/bytesnake/vim-graphical-preview), which refused to compile on my Linux box.

Requirements
------------

- ImageMagick
- LaTeX (optional)
- Python libraries:
    - pynvim
    - wand (Python Imagemagick wrapper)


Installation
------------

### Vundle

<!--
Place the following in `~/.config/nvim/init.vim`:
```vim
Plugin '...', { 'do': ':UpdateRemotePlugins' }
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


Highlights
----------

Plugin highlights


TODOs
-----

- Sixel cache in Lua
- Suspend LaTeX display if cursor inside fence
- Asynchronously draw images
    - LaTeX update rendering currently forces all images to be available first
    - Hold off drawing edited LaTeX if insert mode exited while cursor inside fence
