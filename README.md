# md-indent.nvim
Indents nested Markdown headings the way `org-indent-mode` indents org headings.
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
         the text is aligned to the heading text, just like org mode
  ## Subheading 2
     lorem
```

## Install
Add the package to `init.lua`, then restart Nvim with `:restart`:

```lua
vim.pack.add({ 'https://github.com/your-org/md-indent.nvim' })

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
  'your-org/md-indent.nvim',
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

## Commands
- `:MDIndentEnable` - Indent headings in the current buffer
- `:MDIndentDisable` - Remove the indentation from the current buffer
- `:MDIndentToggle` - Switch the indentation on or off

## Behavior
- A heading nests under the text of the heading above
  - `## Sub` lines up at the column of the level 1 body text
  - The nesting comes from the heading hashes only
- Body text lines up with the heading text above
  - The offset equals the heading offset plus the hashes and the space after them
- A setext heading keeps its text on the line above
  - Body text under that heading gets the heading offset only
- Each line keeps its own leading whitespace, and the plugin adds the offset on top
- The plugin ignores headings in a fenced code block
- The plugin treats a heading with 4 leading spaces or more as code, like CommonMark does
- Blank lines get the heading offset only
- Fold lines keep the indent
  - The plugin prefixes the fold text with the offset of the first line of the fold
  - The plugin sets `'foldtext'` while that option holds the default value
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
