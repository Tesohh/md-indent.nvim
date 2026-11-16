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
eq(scan(example)[1], 2, 'body text under level 1 lines up past the heading text')
eq(scan(example)[2], 2, 'level 2 heading nests under the level 1 text')
eq(scan(example)[3], 5, 'body text under level 2')
eq(scan(example)[4], 5, 'level 3 heading nests under the level 2 text')
eq(scan(example)[5], 9, 'body text under level 3')
eq(scan(example)[6], 2, 'level 2 heading after level 3')
eq(scan(example)[7], 5, 'body text after level 3 heading')

eq(scan({ '#### Deep', 'text' })[0], nil, 'heading with no parent sits flush left')
eq(scan({ '#### Deep', 'text' })[1], 5, 'level 4 body text lines up past the hashes')
eq(scan({ '#Heading', 'text' })[0], nil, 'no space after hashes is not a heading')
eq(scan({ '##', 'text' })[0], nil, 'hashes without a space are not a heading')
eq(scan({ '##', 'text' })[1], nil, 'hashes without a space do not indent the next line')
eq(scan({ '# A', '##', 'text' })[1], 2, 'hashes without a space are body text')
eq(scan({ '# A', '##', 'text' })[2], 2, 'text after typed hashes stays under the level 1 heading')
eq(scan({ '## Sub', '###', 'text' })[1], 3, 'typed hashes under a heading are body text')
eq(scan({ '## Sub', '###', 'text' })[2], 3, 'text after typed hashes keeps the enclosing heading')
eq(scan({ '####### Too many' })[0], nil, 'more than 6 hashes is not a heading')
eq(scan({ '    ## Indented code' })[0], nil, 'heading with 4 leading spaces is code')
eq(scan({ ' ## Sub' })[0], nil, 'heading with no parent sits flush left')
eq(scan({ ' ## Sub', 'text' })[1], 4, 'leading spaces of the heading count in the body offset')
eq(scan({ '# A', '', '## B' })[2], 2, 'blank line keeps the heading level')

-- Code fences ----------------------------------------------------------------
eq(scan({ '## Sub', '```', '# fake heading', 'code', '```', 'text' })[1], 3, 'fence line is indented')
eq(scan({ '## Sub', '```', '# fake', 'code', '```', 'text' })[2], 3, 'heading inside fence does not change level')
eq(scan({ '## Sub', '```', 'code', '```', 'text' })[4], 3, 'text after a fence keeps the level')
eq(scan({ '### Sub', '~~~', 'code', '~~~' })[1], 4, 'tilde fence is indented')
eq(scan({ '# A', '## Sub', '```', 'code', '```', 'text' }, { indent_code_blocks = false })[2], nil, 'code line is not indented')
eq(scan({ '# A', '## Sub', '```', 'code', '```', '```' }, { indent_code_blocks = false })[5], nil, 'closing fence is not indented')
eq(scan({ '# A', '## Sub', '```', 'code', '```', 'text' }, { indent_code_blocks = false })[5], 5, 'text outside fence is indented')

-- YAML metadata --------------------------------------------------------------
eq(scan({ '---', 'title: x', '---', '## Sub', 'text' })[1], nil, 'metadata line is not indented')
eq(scan({ '---', 'title: x', '---', '# Top', '## Sub', 'text' })[5], 5, 'heading after metadata')

-- Setext headings ------------------------------------------------------------
eq(scan({ 'Title', '=====', 'text' }, { setext_headings = true })[2], nil, 'setext level 1 body gets no offset')
eq(scan({ 'Title', '---', 'text' }, { setext_headings = true })[2], nil, 'setext level 2 with no parent sits flush left')
eq(scan({ 'Title', '=====', '## Sub', 'body' }, { setext_headings = true })[3], 3, 'body text after an atx heading below a setext level 1')
-- A setext heading puts its text on the line above, so body text gets no pad.
eq(scan({ 'Title', '=====', 'body' }, { setext_headings = true })[2], nil, 'setext body text gets no pad')
eq(scan({ 'Title', '=====', '', 'text' }, { setext_headings = true })[3], nil, 'level 1 body text gets no offset')

-- Integration with extmarks --------------------------------------------------

local function render(lines, opts)
  if opts then
    mod.setup(opts)
  else
    -- setup is what marks the plugin as loaded, so update can run.
    mod.setup({})
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = 'markdown'
  mod.update(buf)
  return buf
end

-- Reads a line, then looks up the offset of the virtual text placed there.
-- A line range like (line, line) fails on a buffer with no extmarks, so scan
-- the whole buffer and pick the line.
local function offset(buf, line)
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  for _, m in ipairs(marks) do
    if m[2] == line and m[4].virt_text then
      return #m[4].virt_text[1][1]
    end
  end
  return 0
end

local buf = render(example)
-- The extmark must pull left, so typed text lands after the indent and the
-- insert cursor is drawn after the indent too.
local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
eq(marks[1][4].right_gravity, false, 'extmark has left gravity')
eq(offset(buf, 0), 0, 'rendered level 1 heading')
eq(offset(buf, 2), 2, 'rendered level 2 heading')
eq(offset(buf, 4), 5, 'rendered level 3 heading')
eq(offset(buf, 6), 2, 'rendered level back to 2')

-- Nesting follows the heading prefixes, not 'shiftwidth'
vim.o.shiftwidth = 8
local wider = render(example)
eq(offset(wider, 2), 2, 'a deeper heading ignores shiftwidth')
eq(offset(wider, 4), 5, 'a level 3 heading nests under the level 2 text')

-- Changing an option updates existing buffers
local fence_buf = render({ '## Sub', '```', 'code', '```' })
eq(offset(fence_buf, 1), 3, 'fenced code lines up with the heading text')
mod.setup({ indent_code_blocks = false })
eq(offset(fence_buf, 1), 0, 'setup with indent_code_blocks false drops the code indent')
eq(vim.api.nvim_buf_get_lines(fence_buf, 1, 2, false)[1], '```', 'buffer text stays untouched')

-- Fold text -----------------------------------------------------------------

-- v:foldstart is writable, so it stands in for the fold rendering context.
local fold_buf = render(example)
local current_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_set_current_buf(fold_buf)
-- Line 3 is the level 2 heading, so the fold offset there is 2.
vim.v.foldstart = 3
local builtin_text = mod.foldtext()
mod.disable(fold_buf)
eq(builtin_text:sub(1, 2), '  ', 'builtin fold text keeps the offset')

local chunks_mod = { foldtext = function() return { { 'ufo', 'Comment' } } end }
package.loaded['fake-ufo'] = chunks_mod
vim.o.foldtext = "v:lua.require'fake-ufo'.foldtext()"
mod.enable(fold_buf)
local chunks = chunks_mod.foldtext()
eq(chunks[1][1], '  ', 'chunk fold text gets the offset')
eq(chunks[2][1], 'ufo', 'chunk fold text stays intact')
-- A cached chunk table must not collect extra pads across renders.
local again = chunks_mod.foldtext()
eq(#again, 2, 'chunk fold text pads once per render')
eq(again[1][1], '  ', 'second render keeps one pad')
local string_mod = { foldtext = function() return 'ufo' end }
package.loaded['fake-ufo-2'] = string_mod
vim.o.foldtext = "v:lua.require'fake-ufo-2'.foldtext()"
mod.enable(fold_buf)
eq(string_mod.foldtext(), '  ufo', 'string fold text from another plugin gets the offset')

package.loaded['fake-ufo'] = nil
package.loaded['fake-ufo-2'] = nil
vim.v.foldstart = 0
mod.disable(fold_buf)
vim.api.nvim_set_current_buf(current_buf)
mod.setup({ indent_code_blocks = true })
mod.update(buf)

-- Fold text is only taken over in windows that show an enabled buffer.
local default_foldtext = vim.api.nvim_get_option_value('foldtext', { win = 0 })
vim.o.foldtext = default_foldtext
local md_buf = render(example)
vim.api.nvim_set_current_buf(md_buf)
local md_win = vim.api.nvim_get_current_win()
vim.cmd('rightbelow vsplit')
local plain_win = vim.api.nvim_get_current_win()
local plain = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(plain, 0, -1, false, { '# Plain', 'text' })
vim.api.nvim_win_set_buf(plain_win, plain)
mod.enable(md_buf)
local md_ft = vim.api.nvim_get_option_value('foldtext', { win = md_win })
local plain_ft = vim.api.nvim_get_option_value('foldtext', { win = plain_win })
eq(md_ft:find('md_indent') ~= nil, true, 'foldtext is taken over in the markdown window')
eq(plain_ft, default_foldtext, 'foldtext in a plain window is untouched')
eq(vim.o.foldtext, default_foldtext, 'the global foldtext is untouched')
mod.disable(md_buf)
eq(vim.api.nvim_get_option_value('foldtext', { win = md_win }), default_foldtext, 'disable restores the foldtext of the markdown window')
vim.api.nvim_win_close(plain_win, true)

-- A heading removed by a change shifts the deeper headings up
vim.api.nvim_buf_set_lines(buf, 2, 3, false, { 'text under level 1' })
mod.schedule_update(buf)
-- Exits with a failure if the deferred checks never run.
vim.defer_fn(function()
  print('FAIL test runner timed out')
  vim.cmd('cquit! 1')
end, 5000)

local deferred = vim.defer_fn(function()
  eq(offset(buf, 4), 2, 'scheduled update after a change')
  local other = render({ '# Top', '## Sub', 'text' })
  mod.disable(other)
  eq(offset(other, 2), 0, 'disable clears the virtual text')
  mod.toggle(other)
  eq(offset(other, 2), 5, 'toggle turns the indentation back on')
  eq(mod.enabled(other), true, 'enabled reports the state')
  mod.disable(other)
  print(string.format('%d checks passed, %d failures', passed, failures))
  vim.cmd(failures > 0 and 'cquit! 1' or 'quit!')
end, 100)
assert(deferred ~= nil)
