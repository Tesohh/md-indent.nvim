# md-indent.nvim

Indents nested Markdown headings the way emacs' `org-indent-mode` indents org
headings. The indentation is added as virtual text, so buffer text stays
unchanged: undo, diffs and the saved file keep the original lines.

Requires Neovim 0.10 or newer (`virt_text_pos = 'inline'`).

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
        some more, more text
    ## Subheading 2
    lorem
```

## Install

With a plugin manager such as lazy.nvim:

```lua
{
  'your-org/md-indent.nvim',
  opts = { indent_width = 4 },
}
```

Or with `vim.g`:

```lua
vim.g.md_indent_setup = { indent_width = 4 }
```

No setup is needed: the plugin loads by itself and uses `shiftwidth` as the
indent width.

## Options

Passed to `require('md-indent').setup()`:

| Option               | Default                      | Description                                   |
| -------------------- | ---------------------------- | ------------------------------------------- |
| `indent_width`       | `shiftwidth`                 | Spaces per heading level                     |
| `filetypes`          | `{ 'markdown', 'markdown.native' }` | Filetypes to enable on                |
| `hl_group`           | `'MdIndent'`                 | Highlight group of the added spaces          |
| `frontmatter`        | `true`                       | Skip the YAML metadata block at the top      |
| `setext_headings`    | `false`                      | Count `=` / `-` underlines as level 1 / 2    |
| `indent_code_blocks` | `true`                       | Indent code block lines with the heading     |

## Commands

- `:MDIndentEnable` - indent headings in the current buffer
- `:MDIndentDisable` - remove the indentation from the current buffer
- `:MDIndentToggle` - switch the indentation on or off

## Behaviour

- Heading level comes from the leading hashes (1 to 6), so level 1 adds no offset and level 2 adds one `indent_width`.
- Body text gets the offset of the heading it follows.
- Lines keep their own leading whitespace; the offset is added on top.
- Headings inside a fenced code block are not counted as headings.
- Headings with 4 or more leading spaces are treated as code, like CommonMark.
- Blank lines get no offset.
- Fold lines keep the indent: the plugin prefixes the fold text with the offset
  of the fold's first line. It sets `'foldtext'` when nothing owns it, and pads the
  fold text function of the plugin that owns it (for example nvim-ufo), for string
  and chunk fold texts alike. The option and the function are restored when no
  enabled buffer is left.

Set `'breakindent'` to keep wrapped lines aligned with the indent.

## Tests

```sh
./tests/run.sh           # needs the nvim on PATH, Nvim 0.10 or newer
NVIM_BIN=/path/to/nvim ./tests/run.sh
```

## Help

`:help md-indent`
