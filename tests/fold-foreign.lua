-- Renders a fold whose foldtext returns chunks, like nvim-ufo, so tests/run.sh
-- can check that the plugin keeps that fold text instead of breaking it.

function _G.foreign_foldtext()
  return {
    { 'ufo', 'Comment' },
    { vim.fn.getline(vim.v.foldstart), 'Normal' },
  }
end

vim.o.foldtext = 'v:lua.foreign_foldtext()'
require('md-indent').setup()
vim.bo.filetype = 'markdown'

-- The fold needs a window, so wait for startup to finish.
vim.defer_fn(function()
  vim.cmd('2,5fold')
  vim.cmd('redraw')
  vim.cmd('q!')
end, 200)
