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

eq(scan(example)[0], nil, 'level 1 heading gets no offset')
eq(scan(example)[1], 2, 'level 1 body lines up with the heading text')
eq(scan(example)[2], 1, 'level 2 heading sits one column in')
eq(scan(example)[3], 4, 'level 2 body lines up with the heading text')
eq(scan(example)[4], 2, 'level 3 heading sits two columns in')
eq(scan(example)[5], 6, 'level 3 body lines up with the heading text')
eq(scan(example)[6], 1, 'level 2 heading after level 3')
eq(scan(example)[7], 4, 'level 2 body after level 3 heading')

eq(scan({ '#### Deep', 'text' })[0], 3, 'heading offset only depends on the level')
eq(scan({ '#### Deep', 'text' })[1], 8, 'level 4 body lines up with the heading text')
eq(scan({ '#Heading', 'text' })[0], nil, 'no space after hashes is not a heading')
eq(scan({ '##', 'text' })[0], nil, 'hashes without a space are not a heading')
eq(scan({ '##', 'text' })[1], nil, 'hashes without a space do not indent the next line')
eq(scan({ '# A', '##', 'text' })[1], 2, 'hashes without a space are body text')
eq(scan({ '# A', '##', 'text' })[2], 2, 'text after typed hashes stays under the level 1 heading')
eq(scan({ '## Sub', '###', 'text' })[1], 4, 'typed hashes under a heading are body text')
eq(scan({ '## Sub', '###', 'text' })[2], 4, 'text after typed hashes keeps the enclosing heading')
eq(scan({ '####### Too many' })[0], nil, 'more than 6 hashes is not a heading')
eq(scan({ '    ## Indented code' })[0], nil, 'heading with 4 leading spaces is code')
eq(scan({ ' ## Sub' })[0], 2, 'leading spaces of the heading shift the heading offset')
eq(scan({ ' ## Sub', 'text' })[1], 5, 'leading spaces of the heading count in the body offset')
eq(scan({ '# A', '', '## B' })[2], 1, 'blank line keeps the heading level')

-- Code fences ----------------------------------------------------------------
eq(scan({ '## Sub', '```', '# fake heading', 'code', '```', 'text' })[1], 4, 'fence line is indented')
eq(scan({ '## Sub', '```', '# fake', 'code', '```', 'text' })[2], 4, 'heading inside fence does not change level')
eq(scan({ '## Sub', '```', 'code', '```', 'text' })[4], 4, 'text after a fence keeps the level')
eq(scan({ '### Sub', '~~~', 'code', '~~~' })[1], 6, 'tilde fence is indented')
eq(scan({ '# A', '## Sub', '```', 'code', '```', 'text' }, { indent_code_blocks = false })[2], nil, 'code line is not indented')
eq(scan({ '# A', '## Sub', '```', 'code', '```', '```' }, { indent_code_blocks = false })[5], nil, 'closing fence is not indented')
eq(scan({ '# A', '## Sub', '```', 'code', '```', 'text' }, { indent_code_blocks = false })[5], 4, 'text outside fence is indented')

-- YAML metadata --------------------------------------------------------------
eq(scan({ '---', 'title: x', '---', '## Sub', 'text' })[1], nil, 'metadata line is not indented')
eq(scan({ '---', 'title: x', '---', '# Top', '## Sub', 'text' })[5], 4, 'heading after metadata')

-- Setext headings ------------------------------------------------------------
eq(scan({ 'Title', '=====', 'text' }, { setext_headings = true })[2], 2, 'setext level 1 body lines up with the heading text')
eq(scan({ 'Title', '---', 'text' }, { setext_headings = true })[2], 4, 'setext level 2 body lines up with the heading text')
eq(scan({ 'Title', '=====', '## Sub', 'body' }, { setext_headings = true })[2], 1, 'atx heading below a setext level 1')
eq(scan({ 'Title', '=====', '## Sub', 'body' }, { setext_headings = true })[3], 4, 'body text below an atx heading under a setext level 1')
-- A setext heading puts its text on the line above, so only the underline moves.
eq(scan({ 'Title', '=====', 'body' }, { setext_headings = true })[2], 2, 'setext body text is indented')
eq(scan({ 'Title', '=====', '', 'text' }, { setext_headings = true })[3], 2, 'level 1 body text is indented')

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
eq(offset(buf, 2), 1, 'rendered level 2 heading')
eq(offset(buf, 4), 2, 'rendered level 3 heading')
eq(offset(buf, 6), 1, 'rendered level back to 2')

-- Nesting follows the heading prefixes, not 'shiftwidth'
vim.o.shiftwidth = 8
local wider = render(example)
eq(offset(wider, 2), 1, 'a deeper heading ignores shiftwidth')
eq(offset(wider, 4), 2, 'a level 3 heading sits two columns in')

-- Changing an option updates existing buffers
local fence_buf = render({ '## Sub', '```', 'code', '```' })
eq(offset(fence_buf, 1), 4, 'fenced code lines up with the heading text')
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
eq(builtin_text:sub(1, 1), ' ', 'builtin fold text keeps the offset')

local chunks_mod = { foldtext = function() return { { 'ufo', 'Comment' } } end }
package.loaded['fake-ufo'] = chunks_mod
vim.o.foldtext = "v:lua.require'fake-ufo'.foldtext()"
mod.enable(fold_buf)
local chunks = chunks_mod.foldtext()
eq(chunks[1][1], ' ', 'chunk fold text gets the offset')
eq(chunks[2][1], 'ufo', 'chunk fold text stays intact')
-- A cached chunk table must not collect extra pads across renders.
local again = chunks_mod.foldtext()
eq(#again, 2, 'chunk fold text pads once per render')
eq(again[1][1], ' ', 'second render keeps one pad')
local string_mod = { foldtext = function() return 'ufo' end }
package.loaded['fake-ufo-2'] = string_mod
vim.o.foldtext = "v:lua.require'fake-ufo-2'.foldtext()"
mod.enable(fold_buf)
eq(string_mod.foldtext(), ' ufo', 'string fold text from another plugin gets the offset')

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

-- Parked cursor ---------------------------------------------------------------

local function curpos()
  local p = vim.fn.getcurpos()
  return p[3], p[4] -- 1-based byte col, coladd
end
-- The level 3 heading body sits at 2 * 3 = 6 columns; the blank line under it
-- parks the cursor there, where a typed character would land.
local park_buf = render({ '### Sub3', '', 'text' })
vim.api.nvim_set_current_buf(park_buf)
-- Sets up our window-local 'virtualedit', which park_cursor needs.
mod.refresh_windows()
vim.api.nvim_win_set_cursor(0, { 2, 0 })
mod.park_cursor()
local pcol, padd = curpos()
eq(padd, 6, 'park cursor uses the body offset of the heading above')
eq(pcol, 1, 'park cursor keeps the byte column')
-- A blank line keeps working when the heading pad is empty but text would
-- still land deeper: a level 1 heading line has no pad, its body has.
local bare_buf = render({ '# H', '' })
vim.api.nvim_set_current_buf(bare_buf)
mod.refresh_windows()
vim.api.nvim_win_set_cursor(0, { 2, 0 })
mod.park_cursor()
local bcol, badd = curpos()
eq(badd, 2, 'park cursor works on a blank line without a pad')
eq(bcol, 1, 'park cursor keeps the byte column without a pad')
-- A column carried onto an unindented line by virtual editing is undone.
vim.api.nvim_set_current_buf(park_buf)
mod.refresh_windows()
-- simulate virtual editing carrying the parked column 6 onto '# Top'
local carry_buf = render({ '### Sub3', '', '# Top', 'plain' })
vim.api.nvim_set_current_buf(carry_buf)
mod.refresh_windows()
vim.api.nvim_win_set_cursor(0, { 2, 0 })
mod.park_cursor()
vim.fn.cursor({ 3, 6, 0 }) -- byte col 5, where the carried column would land
mod.park_cursor()
local scol, sadd = curpos()
eq(sadd, 0, 'carried virtual columns lose the coladd')
eq(scol, 1, 'carried virtual columns restore the parked byte column')
-- The coladd is cleared again on a line with text.
vim.api.nvim_win_set_cursor(0, { 3, 0 })
mod.park_cursor()
local tcol, tadd = curpos()
eq(tadd, 0, 'park cursor clears the coladd on text lines')
-- A coladd the user set outside the plugin is not kept.
vim.fn.cursor({ 3, 2, 1 })
mod.park_cursor()
local ocol, oadd = curpos()
eq(ocol, 2, 'park cursor keeps a user-set column')
eq(oadd, 0, 'park cursor drops a user-set coladd')
-- Insert mode grows the pad of the blank line, so the insert cursor is drawn
-- where typed text lands and the coladd stays out of the way. The insert state
-- is captured from a mapped key, so 'mode()' really is insert.
local pnames = vim.api.nvim_get_namespaces()['md-indent']
vim.api.nvim_set_current_buf(park_buf)
mod.refresh_windows()
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local insert_state = {}
vim.keymap.set('i', '<F1>', function()
  local exts = vim.api.nvim_buf_get_extmarks(0, pnames, { 1, 0 }, { 1, 0 }, { details = true })
  insert_state.pads = #exts
  insert_state.width = exts[1] and #exts[1][4].virt_text[1][1] or 0
  insert_state.coladd = vim.fn.getcurpos()[4]
end)
local esc = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)
vim.fn.feedkeys('i' .. vim.api.nvim_replace_termcodes('<F1>', true, false, true) .. esc, 'x!')
eq(insert_state.pads, 1, 'insert mode keeps a pad extmark on the blank line')
eq(insert_state.width, 6, 'insert mode grows the pad to the body offset')
eq(insert_state.coladd, 0, 'insert mode keeps the coladd out of typed text')
eq(offset(park_buf, 1), 2, 'leaving insert restores the pad of the blank line')
-- A blank line without a pad of its own (level 1 heading) gets a bump extmark
-- in insert mode, and it is gone again afterwards.
local bare_buf = render({ '# H', '' })
vim.api.nvim_set_current_buf(bare_buf)
mod.refresh_windows()
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local bare_state = {}
vim.keymap.set('i', '<F1>', function()
  local exts = vim.api.nvim_buf_get_extmarks(0, pnames, { 1, 0 }, { 1, 0 }, { details = true })
  bare_state.pads = #exts
  bare_state.width = exts[1] and #exts[1][4].virt_text[1][1] or 0
end)
vim.fn.feedkeys('i' .. vim.api.nvim_replace_termcodes('<F1>', true, false, true) .. esc, 'x!')
eq(bare_state.pads, 1, 'insert mode bumps a pad onto a blank line without one')
eq(bare_state.width, 2, 'the bump pad is the body offset')
eq(offset(bare_buf, 1), 0, 'the bump extmark is removed again after insert')
-- No indent is added to the buffer text at any point.
eq(vim.api.nvim_buf_get_lines(bare_buf, 1, 2, false)[1], '', 'the blank line is still empty')
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
  eq(offset(other, 2), 4, 'toggle turns the indentation back on')
  eq(mod.enabled(other), true, 'enabled reports the state')
  mod.disable(other)
  print(string.format('%d checks passed, %d failures', passed, failures))
  vim.cmd(failures > 0 and 'cquit! 1' or 'quit!')
end, 100)
assert(deferred ~= nil)
