-- Test runner. Run with: ./tests/run.sh
-- Needs Nvim 0.10 or newer for the 'inline' virtual text.

local root = vim.fn.getcwd()
vim.opt.runtimepath = { root, vim.o.runtimepath }

local indent = require('md-indent.indent')
local mod = require('md-indent')
local ns = vim.api.nvim_get_namespaces()['md-indent']

local passed = 0
local failures = 0

local function eq(actual, expected, name)
  if actual ~= expected then
    failures = failures + 1
    io.write(string.format('FAIL %s: got %s, expected %s\n', name, tostring(actual), tostring(expected)))
  else
    passed = passed + 1
    io.write(string.format('ok   %s\n', name))
  end
  io.flush()
end

-- Lines with no offset are absent from the scan result, so nil means "no indent".
local function scan(lines, opts)
  opts = vim.tbl_deep_extend('force', { indent_width = 4 }, opts or {})
  local out = {}
  for _, e in ipairs(indent.scan(lines, opts)) do
    out[e.line] = e.width
  end
  return out
end

-- Unit tests of the scanner ---------------------------------------------------

local example = {
  '# Heading',
  'some text asdasd',
  '## Subheading',
  'some more text',
  '### Subsubheading',
  'some more, more text',
  '## Subheading 2',
  'lorem',
}

eq(scan(example)[0], nil, 'atx level 1 heading gets no offset')
eq(scan(example)[1], nil, 'body text under level 1 gets no offset')
eq(scan(example)[2], 4, 'level 2 heading')
eq(scan(example)[3], 4, 'body text under level 2')
eq(scan(example)[4], 8, 'level 3 heading')
eq(scan(example)[5], 8, 'body text under level 3')
eq(scan(example)[6], 4, 'level 2 heading after level 3')
eq(scan(example)[7], 4, 'body text after level 3 heading')

eq(scan({ '#### Deep', 'text' })[0], 12, 'level 4 heading')
eq(scan({ '#Heading', 'text' })[0], nil, 'no space after hashes is not a heading')
eq(scan({ '####### Too many' })[0], nil, 'more than 6 hashes is not a heading')
eq(scan({ '    ## Indented code' })[0], nil, 'heading with 4 leading spaces is code')
eq(scan({ ' ## Sub' })[0], 4, 'heading with up to 3 leading spaces counts')
eq(scan({ '##', 'text' })[1], 4, 'empty heading keeps the level')
eq(scan({ '# A', '', '## B' })[2], 4, 'blank line keeps the heading level')

-- Code fences ----------------------------------------------------------------
eq(scan({ '## Sub', '```', '# fake heading', 'code', '```', 'text' })[1], 4, 'fence line is indented')
eq(scan({ '## Sub', '```', '# fake', 'code', '```', 'text' })[2], 4, 'heading inside fence does not change level')
eq(scan({ '## Sub', '```', 'code', '```', 'text' })[4], 4, 'text after a fence keeps the level')
eq(scan({ '### Sub', '~~~', 'code', '~~~' })[1], 8, 'tilde fence is indented')
eq(scan({ '# A', '## Sub', '```', 'code', '```', 'text' }, { indent_code_blocks = false })[2], nil, 'code line is not indented')
eq(scan({ '# A', '## Sub', '```', 'code', '```', '```' }, { indent_code_blocks = false })[5], nil, 'closing fence is not indented')
eq(scan({ '# A', '## Sub', '```', 'code', '```', 'text' }, { indent_code_blocks = false })[5], 4, 'text outside fence is indented')

-- YAML metadata --------------------------------------------------------------
eq(scan({ '---', 'title: x', '---', '## Sub', 'text' })[1], nil, 'metadata line is not indented')
eq(scan({ '---', 'title: x', '---', '# Top', '## Sub', 'text' })[5], 4, 'heading after metadata')

-- Setext headings ------------------------------------------------------------
eq(scan({ 'Title', '=====', 'text' }, { setext_headings = true })[2], nil, 'setext level 1 body gets no offset')
eq(scan({ 'Title', '---', 'text' }, { setext_headings = true })[2], 4, 'setext level 2')
eq(scan({ 'Title', '=====', '## Sub', 'body' }, { setext_headings = true })[3], 4, 'atx heading after setext level 1')
eq(scan({ 'Title', '=====', '', 'text' }, { setext_headings = true })[3], nil, 'level 1 body text gets no offset')

-- Integration with extmarks --------------------------------------------------

local function render(lines, opts)
  if opts then
    mod.setup(opts)
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = 'markdown'
  mod.update(buf)
  return buf
end

local function offset(buf, line)
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, line, line, { details = true })
  for _, m in ipairs(marks) do
    if m[4].virt_text then
      return #m[4].virt_text[1][1]
    end
  end
  return 0
end

local buf = render(example, { indent_width = 4 })
eq(offset(buf, 0), 0, 'rendered level 1 heading')
eq(offset(buf, 2), 4, 'rendered level 2 heading')
eq(offset(buf, 4), 8, 'rendered level 3 heading')
eq(offset(buf, 6), 4, 'rendered level back to 2')

-- 'shiftwidth' is the default width
mod.options.indent_width = nil
vim.o.shiftwidth = 2
local shift_buf = render(example)
eq(offset(shift_buf, 2), 2, 'default width follows shiftwidth')

-- Changing an option updates existing buffers
mod.setup({ indent_width = 8 })
eq(offset(buf, 4), 16, 'setup with a new width re-places the virtual text')
eq(vim.api.nvim_buf_get_lines(buf, 4, 5, false)[1], '### Subsubheading', 'buffer text stays untouched')

-- Fold text -----------------------------------------------------------------

-- v:foldstart is writable, so it stands in for the fold rendering context.
local fold_buf = render(example, { indent_width = 4 })
local current_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_set_current_buf(fold_buf)
-- Line 3 is the level 2 heading, so the fold offset there is 4.
vim.v.foldstart = 3
local builtin_text = mod.foldtext()
mod.disable(fold_buf)
eq(builtin_text:sub(1, 4), '    ', 'builtin fold text keeps the offset')

local chunks_mod = { foldtext = function() return { { 'ufo', 'Comment' } } end }
package.loaded['fake-ufo'] = chunks_mod
vim.o.foldtext = "v:lua.require'fake-ufo'.foldtext()"
mod.enable(fold_buf)
local chunks = chunks_mod.foldtext()
eq(chunks[1][1], '    ', 'chunk fold text gets the offset')
eq(chunks[2][1], 'ufo', 'chunk fold text stays intact')
-- A cached chunk table must not collect extra pads across renders.
local again = chunks_mod.foldtext()
eq(#again, 2, 'chunk fold text pads once per render')
eq(again[1][1], '    ', 'second render keeps one pad')
local string_mod = { foldtext = function() return 'ufo' end }
package.loaded['fake-ufo-2'] = string_mod
vim.o.foldtext = "v:lua.require'fake-ufo-2'.foldtext()"
mod.enable(fold_buf)
eq(string_mod.foldtext(), '    ufo', 'string fold text from another plugin gets the offset')

package.loaded['fake-ufo'] = nil
package.loaded['fake-ufo-2'] = nil
vim.v.foldstart = 0
mod.disable(fold_buf)
vim.api.nvim_set_current_buf(current_buf)
mod.setup({ indent_width = 8 })
mod.update(buf)

-- A buffer change triggers a scheduled update
vim.api.nvim_buf_set_lines(buf, 1, 2, false, { '### Body moved under level 3' })
-- Exits with a failure if the deferred checks never run.
vim.defer_fn(function()
  print('FAIL test runner timed out')
  vim.cmd('cquit! 1')
end, 5000)

local deferred = vim.defer_fn(function()
  eq(offset(buf, 1), 8, 'scheduled update after a change')
  local other = render({ '## Sub', 'text' }, { indent_width = 3 })
  mod.disable(other)
  eq(offset(other, 0), 0, 'disable clears the virtual text')
  mod.toggle(other)
  eq(offset(other, 0), 3, 'toggle turns the indentation back on')
  eq(mod.enabled(other), true, 'enabled reports the state')
  mod.disable(other)
  print(string.format('%d checks passed, %d failures', passed, failures))
  vim.cmd(failures > 0 and 'cquit! 1' or 'quit!')
end, 100)
assert(deferred ~= nil)
