# md-indent.nvim
Indents nested Markdown headings by their level, like Emacs does.
The plugin adds the indentation as virtual text, so buffer text stays unchanged.
Undo, diffs, and the saved file keep the original lines.

Requires Neovim 0.10 or newer, which supports `virt_text_pos = 'inline'`.

```markdown
# Heading
some text asdasd
## Subheading
some more text
### Subsubheading
some more, more text
## Subheading 2
lorem
```

renders as:

```markdown
# Heading
  some text asdasd
 ## Subheading
    some more text
  ### Subsubheading
      the text is aligned to the heading text
 ## Subheading 2
    lorem
```

A heading of level n sits `n - 1` columns in, and its body text lines up
right past the hashes of the heading, at `2 * n` columns.

## Install
Add the package to `init.lua`, then restart Nvim with `:restart`:

```lua
vim.pack.add({ 'https://github.com/Tesohh/md-indent.nvim' })

require('md-indent').setup()
```

`vim.pack` needs Neovim 0.11 or newer.
The lockfile `nvim.pack.json` records the installed revision.

Put options in the `setup` call:

```lua
require('md-indent').setup({ setext_headings = true })
```

With lazy.nvim, use this entry:

```lua
{
  'Tesohh/md-indent.nvim',
  opts = { setext_headings = true },
}
```

The plugin reads `vim.g.md_indent_setup` before the `setup` call runs:

```lua
vim.g.md_indent_setup = { setext_headings = true }
```

You may omit the setup call: the plugin loads by itself.

## Options
Pass these options to `require('md-indent').setup()`:

- `filetypes` - The filetypes to enable on, default `{ 'markdown', 'markdown.native' }`
- `hl_group` - The highlight group of the added spaces, default `'MdIndent'`
- `frontmatter` - Skip the YAML metadata block at the top of the file, default `true`
- `setext_headings` - Count `=` and `-` underlines as level 1 and level 2 headings, default `false`
- `indent_code_blocks` - Indent code block lines with the heading, default `true`
- `virtual_cursor` - Park the cursor past the indent on blank lines, default `true`
- `guides` - Draw a vertical guide under each indented heading, default `true`
- `guide_char` - Character of the guide, default `│`
- `guide_hl_group` - Highlight group of the guide, default `MdIndentGuide`

When indent-blankline is installed, its guides are shifted by the indent, so they stay with the text.

## Commands
- `:MDIndentEnable` - Indent headings in the current buffer
- `:MDIndentDisable` - Remove the indentation from the current buffer
- `:MDIndentToggle` - Switch the indentation on or off

## Behavior
- A heading of level n sits one column further left for each parent level
  - The offset of a heading line equals the level minus one
- Body text lines up with the heading text above
  - The offset equals twice the level of the heading above
- Each line keeps its own leading whitespace, and the plugin adds the offset on top
- The plugin ignores headings in a fenced code block
- The plugin treats a heading with 4 leading spaces or more as code, like CommonMark does
- Blank lines get the heading offset only
- The offset comes from the heading level alone, not from the heading above
- Hashes without a space after them are body text
  - A heading that is still being typed does not move the line
- The cursor and typed text sit after the indent
  - The extmark pulls left, so text typed at column 0 lands after the indent
  - On blank lines in normal and insert mode the cursor sits where the next
    typed character lands, aligned with the text of the heading above
  - The parked cursor borrows a window-local `'virtualedit'` of `all` while
    parked, so moves off a parked blank line follow the screen column the way
    stock Neovim does with virtual editing
  - The borrowed option is restored when the plugin turns off
- Fold lines keep the indent
  - The plugin prefixes the fold text with the offset of the first line of the fold
  - The plugin sets `'foldtext'` in windows that show an enabled buffer, so other buffers keep their own folding
  - The plugin pads the fold text function of the plugin that owns that option
  - The plugin pads the fold text function of the plugin that owns that option
    - The pad covers string fold text and chunk fold text alike
  - The plugin restores the option and the function after every enabled buffer is off

Set `'breakindent'` to keep wrapped lines aligned with the indent.

## Tests
Run the script with the nvim on PATH, or point `NVIM_BIN` at another nvim:

```sh
./tests/run.sh           # needs the nvim on PATH, Nvim 0.10 or newer
NVIM_BIN=/path/to/nvim ./tests/run.sh
```

## Help
`:help md-indent`
