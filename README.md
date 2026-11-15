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
         the text is aligned to the heading text, just like org mode
  ## Subheading 2
     lorem
```

## Install

With a plugin manager such as lazy.nvim:

```lua
{
  'your-org/md-indent.nvim',
}
```

Or with `vim.g`:

```lua
vim.g.md_indent_setup = { setext_headings = true }
```

No setup is needed: the plugin loads by itself.

## Options

Passed to `require('md-indent').setup()`:

| Option               | Default                      | Description                                   |
| -------------------- | ---------------------------- | ------------------------------------------- |
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

- A heading nests under the heading text of the heading it sits under, so
  `## Sub` lines up at the column of the level 1 body text. Nesting follows the
  hashes only, not `shiftwidth`.
- Body text lines up with the heading text it follows, the way org-indent does:
  the heading offset plus the hashes and the space after them.
- A setext heading keeps its text on the line above, so body text under it gets
  no extra alignment.
- Lines keep their own leading whitespace; the offset is added on top.
- Headings inside a fenced code block are not counted as headings.
- Headings with 4 or more leading spaces are treated as code, like CommonMark.
- Blank lines get the offset of the heading they sit under, and no extra
  alignment.
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
