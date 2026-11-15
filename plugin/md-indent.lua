if vim.g.loaded_md_indent then
  return
end
vim.g.loaded_md_indent = true

require('md-indent').setup(vim.g.md_indent_setup)
