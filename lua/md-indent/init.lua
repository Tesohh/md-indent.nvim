-- Indent nested Markdown headings like emacs' org-indent does.

local indent = require('md-indent.indent')

local M = {}

local defaults = {
  filetypes = { 'markdown', 'markdown.native' },
  hl_group = 'MdIndent',
  -- Skip the YAML metadata block at the top of the file
  frontmatter = true,
  -- Treat '=' / '-' underlines as headings (level 1 / 2)
  setext_headings = false,
  -- false keeps code block lines at their own indentation
  indent_code_blocks = true,
  -- Show the cursor past the indent on blank lines
  virtual_cursor = true,
  -- Draw a vertical guide under each indented heading
  guides = true,
  guide_char = '\u{2502}',
  guide_hl_group = 'MdIndentGuide',
}

M.options = vim.tbl_deep_extend('force', {}, defaults)

local ns = vim.api.nvim_create_namespace('md-indent')
local enabled = {} -- buffer -> true
local pending = {} -- buffer -> true, update already scheduled
local fold_offsets = {} -- buffer -> { line = offset }
local foldtext_expr = 'v:lua.md_indent_foldtext()'
local builtin_foldtext = vim.o.foldtext -- default expression, restored on disable
local assert_pending = false
local foldtext_warned = false
local patched = {} -- module.fn key -> { mod, fn, orig }
local ve_wins = {} -- window -> true, we set a window-local 'virtualedit'
local parked = {} -- window -> { lnum, col, vcol }, parked cursor
local park_offsets = {} -- buffer -> { line = cursor column }
local extmark_ids = {} -- buffer -> { line = extmark id of the pad }
local integrated = false
local bumped = {} -- buffer -> { line = line0, id, width }: insert-mode pad

-- 'inline' virtual text shifts the buffer text right, since Nvim 0.10
local function supported()
  return vim.fn.has('nvim-0.10') == 1
end

function M.highlight()
  vim.api.nvim_set_hl(0, 'MdIndent', { link = 'Normal', default = true })
  local base = vim.fn.hlexists('IblIndent') == 1 and 'IblIndent' or 'Whitespace'
  vim.api.nvim_set_hl(0, 'MdIndentGuide', { link = base, default = true })
end

local function scan_options()
  return {
    frontmatter = M.options.frontmatter,
    setext_headings = M.options.setext_headings,
    indent_code_blocks = M.options.indent_code_blocks,
  }
end

local function offsets_by_line(entries)
  local map, cursors = {}, {}
  for _, e in ipairs(entries) do
    map[e.line] = e.width
    if e.cursor then
      cursors[e.line] = e.cursor
    end
  end
  return map, cursors
end

-- The offset of the fold's first line, inside the fold rendering context.
local function fold_pad()
  local buf = vim.api.nvim_get_current_buf()
  local start = vim.v.foldstart
  if not enabled[buf] or not start then
    return ''
  end
  local map = fold_offsets[buf]
  if not map then
    map = offsets_by_line(indent.scan(vim.api.nvim_buf_get_lines(buf, 0, -1, false), scan_options()))
  end
  return string.rep(' ', map[start - 1] or 0)
end

-- Prepends the offset to a fold text result, which can be a string or chunks.
-- The result table is copied, since some plugins cache it and would otherwise
-- accumulate the pad on every render.
local function pad_result(res, pad)
  if pad == '' or res == nil then
    return res
  end
  if type(res) == 'table' then
    local out = { { pad, M.options.hl_group } }
    for i = 1, #res do
      out[#out + 1] = res[i]
    end
    return out
  end
  if type(res) == 'string' then
    return pad .. res
  end
  return res
end

-- Pads a fold text function that another plugin owns, like nvim-ufo. Returns
-- false when the expression names a function we cannot reach.
local function pad_foldtext_fn(expr)
  local module, fn = expr:match("^v:lua%.require'([%w%.%-]+)'%.([%w_]+)%(")
  if module then
    local mod = package.loaded[module]
    if not mod or type(mod[fn]) ~= 'function' then
      return false
    end
    local key = module .. '.' .. fn
    if patched[key] then
      return true
    end
    local orig = mod[fn]
    mod[fn] = function(...)
      return pad_result(orig(...), fold_pad())
    end
    patched[key] = { mod = mod, fn = fn, orig = orig }
    return true
  end
  local name = expr:match('^v:lua%.([%w_]+)%(')
  local global = name and _G[name]
  if type(global) ~= 'function' then
    return false
  end
  local key = 'global.' .. name
  if patched[key] then
    return true
  end
  _G[name] = function(...)
    return pad_result(global(...), fold_pad())
  end
  patched[key] = { mod = _G, fn = name, orig = global }
  return true
end

-- Fold lines render 'foldtext' instead of the buffer line, so the offset has to
-- be added to the fold text to keep folded headings indented.
function M.foldtext()
  -- Clearing 'foldtext' reaches the builtin fold text; restore it afterwards.
  local saved = vim.o.foldtext
  vim.o.foldtext = ''
  local ok, text = pcall(vim.fn.foldtext)
  vim.o.foldtext = saved
  return fold_pad() .. (ok and text or '')
end

-- Vimscript calls 'v:lua' functions without dashes in the name.
_G.md_indent_foldtext = M.foldtext

-- Replaces the indentation of every line in the buffer with virtual text.
function M.update(buf)
  buf = buf or 0
  if not enabled[buf] then
    return
  end
  local entries = indent.scan(vim.api.nvim_buf_get_lines(buf, 0, -1, false), scan_options())
  fold_offsets[buf], park_offsets[buf] = offsets_by_line(entries)
  extmark_ids[buf] = {}
  bumped[buf] = nil
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, e in ipairs(entries) do
    -- Guides inside the pad are part of the pad text. Extra extmarks at column
    -- 0 would break the marks of other plugins, like the heading bullets.
    local chunks, outside = {}, {}
    local at = 0
    if M.options.guides then
      for _, col in ipairs(e.guides or {}) do
        if col < e.width then
          if col > at then
            chunks[#chunks + 1] = { string.rep(' ', col - at), M.options.hl_group }
          end
          chunks[#chunks + 1] = { M.options.guide_char, M.options.guide_hl_group }
          at = col + 1
        else
          outside[#outside + 1] = col
        end
      end
    end
    if e.width > at then
      chunks[#chunks + 1] = { string.rep(' ', e.width - at), M.options.hl_group }
    end
    if e.width > 0 then
      extmark_ids[buf][e.line] = vim.api.nvim_buf_set_extmark(buf, ns, e.line, 0, {
        virt_text = chunks,
        virt_text_pos = 'inline',
        -- Left gravity keeps the extmark at column 0 when text is typed there,
        -- which also draws the insert cursor after the indent.
        right_gravity = false,
        virt_text_repeat_linebreak = true,
      })
    end
    -- Only blank lines have guides past the pad, and they hold no bullets
    for _, col in ipairs(outside) do
      vim.api.nvim_buf_set_extmark(buf, ns, e.line, 0, {
        virt_text = { { M.options.guide_char, M.options.guide_hl_group } },
        virt_text_win_col = col,
        hl_mode = 'combine',
        priority = 200,
      })
    end
  end
  if integrated then
    -- Its guides depend on our pad widths, so draw them again
    pcall(function()
      require('ibl').debounced_refresh(buf)
    end)
  end
  if buf == vim.api.nvim_get_current_buf() then
    M.park_cursor()
  end
end

-- The byte column a virtual-editing move lands on when it carries screen
-- column `vcol` onto `line`: the last character whose width still fits.
local function carried_byte(line, vcol)
  local col, cells = 0, 0
  while col < #line do
    local len = #line:sub(col + 1):match('^.[\128-\191]*')
    local width = vim.fn.strdisplaywidth(line:sub(col + 1, col + len))
    if cells + width > vcol then
      break
    end
    cells = cells + width
    col = col + len
  end
  return col
end

-- Drops our window-local 'virtualedit' back to the global value.
local function drop_virtualedit(win)
  ve_wins[win] = nil
  pcall(function()
    vim.api.nvim_win_call(win, function()
      vim.cmd('setlocal virtualedit<')
    end)
  end)
end

-- Sets the pad of one line back to its scanned width, the state a bump left.
local function restore_pad(buf)
  local bump = bumped[buf]
  bumped[buf] = nil
  if not bump then
    return
  end
  pcall(function()
    if bump.width > 0 then
      vim.api.nvim_buf_set_extmark(buf, ns, bump.line, 0, {
        id = bump.id,
        virt_text = { { string.rep(' ', bump.width), M.options.hl_group } },
        virt_text_pos = 'inline',
        right_gravity = false,
        virt_text_repeat_linebreak = true,
      })
    else
      vim.api.nvim_buf_del_extmark(buf, ns, bump.id)
    end
  end)
end

-- Sits the cursor past the indent on blank lines. The scanner records where
-- typed text would land (the body column of the heading), and the below
-- applies whenever the cursor rests on such a line:
-- Normal mode: a cursor coladd with a window-local "all" of 'virtualedit'
-- shows the cursor there, since Nvim drops the inline virtual text from the
-- virtual column of an empty line.
-- Insert mode: a coladd would pad typed text with spaces, so the pad of the
-- line grows to the body column instead: the insert cursor is drawn right
-- after it, and typed text keeps that column, with no jump at all.
function M.park_cursor()
  if not supported() then
    return
  end
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  if not enabled[buf] and not ve_wins[win] then
    restore_pad(buf)
    return
  end
  local pos = vim.fn.getcurpos()
  local lnum, col, coladd = pos[2], pos[3] - 1, pos[4] or 0
  local lines = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)
  local line = lines[1] or ''
  local mode = vim.fn.mode()

  -- Moving off a parked line carries the virtual column into the next line
  -- as a real byte column; undo that, it is never where the user aimed.
  local park = parked[win]
  parked[win] = nil
  if park and park.lnum ~= lnum and mode == 'n' and col ~= park.col then
    -- The carried screen column compares against the line without its pad.
    local target_pad = fold_offsets[buf] and fold_offsets[buf][lnum - 1] or 0
    if col == carried_byte(line, park.vcol - target_pad) then
      col = math.min(park.col, #line)
      coladd = 0
      pcall(vim.api.nvim_win_set_cursor, win, { lnum, col })
    end
  end

  -- Blank lines park the cursor where typed text would land: the scanner
  -- records that column per line.
  local pad = park_offsets[buf] and park_offsets[buf][lnum - 1] or 0
  local blank = line:match('^%s*$') ~= nil
  local insert = mode:sub(1, 1) == 'i'
    or mode:sub(1, 1) == 'R' or mode:sub(1, 2) == 'ni'
  if insert and blank and pad > 0 and M.options.virtual_cursor then
    restore_pad(buf)
    -- A coladd would pad typed text with spaces, so make sure it is zero.
    if coladd > 0 then
      pcall(vim.api.nvim_win_set_cursor, win, { lnum, col })
    end
    if ve_wins[win] then
      drop_virtualedit(win)
    end
    -- Grow the pad to the body column: the insert cursor lands right after
    -- the virtual text, so this also puts the cursor where typing puts text.
    local width = fold_offsets[buf] and fold_offsets[buf][lnum - 1] or 0
    local id = extmark_ids[buf] and extmark_ids[buf][lnum - 1]
    if id then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, 0, {
        id = id,
        virt_text = { { string.rep(' ', pad), M.options.hl_group } },
        virt_text_pos = 'inline',
        right_gravity = false,
        virt_text_repeat_linebreak = true,
      })
      bumped[buf] = { line = lnum - 1, id = id, width = width }
    else
      local own = vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, 0, {
        virt_text = { { string.rep(' ', pad), M.options.hl_group } },
        virt_text_pos = 'inline',
        right_gravity = false,
        virt_text_repeat_linebreak = true,
      })
      bumped[buf] = { line = lnum - 1, id = own, width = 0 }
    end
    return
  end
  restore_pad(buf)

  local want = (M.options.virtual_cursor and mode == 'n'
    and blank and pad > 0) and pad or 0
  if want == 0 then
    if ve_wins[win] then
      drop_virtualedit(win)
    end
    if coladd > 0 then
      pcall(vim.api.nvim_win_set_cursor, win, { lnum, col })
    end
    return
  end
  if not ve_wins[win] then
    vim.api.nvim_set_option_value('virtualedit', 'all', { win = win, scope = 'local' })
    ve_wins[win] = true
  end
  if coladd ~= want then
    pcall(vim.fn.cursor, { lnum, col + 1, want })
  end
  -- The carried column is the screen column as it renders: the byte column
  -- with the pad of the line in front of it, plus the parked column itself.
  local byte_vcol = col == 0 and 0
    or ((fold_offsets[buf] and fold_offsets[buf][lnum - 1] or 0) + col)
  parked[win] = { lnum = lnum, col = col, vcol = byte_vcol + want }
end

-- Coalesces consecutive changes into one update.
function M.schedule_update(buf)
  if pending[buf] then
    return
  end
  pending[buf] = true
  vim.schedule(function()
    pending[buf] = nil
    M.update(buf)
  end)
end

-- Takes over 'foldtext' in windows that show an enabled buffer, so other
-- buffers keep their own folding. When another plugin owns the option, its
-- fold text function is padded instead.
local function assert_foldtext()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if enabled[vim.api.nvim_win_get_buf(win)] then
      local current = vim.api.nvim_get_option_value('foldtext', { win = win })
      if current ~= foldtext_expr then
        if current == '' or current == builtin_foldtext then
          vim.api.nvim_set_option_value('foldtext', foldtext_expr, { win = win })
        elseif not pad_foldtext_fn(current) and not foldtext_warned then
          foldtext_warned = true
          vim.notify('md-indent: cannot pad the foldtext of ' .. current, vim.log.levels.WARN)
        end
      end
    end
  end
end

-- Drops our window-local 'virtualedit' back to the global value and resets
-- a parked coladd, which stays in the window's cursor across buffer switches.
local function restore_virtualedit(win)
  ve_wins[win] = nil
  parked[win] = nil
  pcall(function()
    local pos = vim.api.nvim_win_get_cursor(win)
    vim.api.nvim_win_set_cursor(win, pos)
    vim.api.nvim_win_call(win, function()
      vim.cmd('setlocal virtualedit<')
    end)
  end)
end

-- Undo our window-local 'virtualedit' in windows that no longer show an
-- enabled buffer; park_cursor sets it for the window it parks the cursor in.
local function assert_virtualedit()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local ok, buf = pcall(vim.api.nvim_win_get_buf, win)
    if not ok or not enabled[buf] then
      if ve_wins[win] then
        restore_virtualedit(win)
      end
    end
  end
end

-- Reasserts every option the plugin takes over, then re-parks the cursor.
function M.refresh_windows()
  if not supported() then
    return
  end
  assert_foldtext()
  assert_virtualedit()
  M.park_cursor()
end

-- Runs after the autocmds of other plugins, so the options end up ours.
function M.schedule_assert()
  if assert_pending then
    return
  end
  assert_pending = true
  vim.schedule(function()
    assert_pending = false
    if next(enabled) then
      M.refresh_windows()
    end
  end)
end

-- indent-blankline draws its guides over the first columns of a line, which
-- is where our pad sits, so its guides are shifted right by the pad width.
local function integrate_ibl()
  local ok, hooks = pcall(require, 'ibl.hooks')
  if not ok or integrated then
    return
  end
  integrated = true
  hooks.register(hooks.type.VIRTUAL_TEXT, function(_, buf, row, virt_text)
    local width = enabled[buf] and fold_offsets[buf] and fold_offsets[buf][row]
    if not width or width == 0 then
      return virt_text
    end
    local out = {}
    for _ = 1, width do
      out[#out + 1] = { ' ', M.options.hl_group }
    end
    vim.list_extend(out, virt_text)
    return out
  end)
end

function M.enable(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not supported() then
    vim.notify('md-indent: needs Nvim 0.10 or newer', vim.log.levels.WARN)
    return false
  end
  enabled[buf] = true
  M.update(buf)
  M.refresh_windows()
  return true
end

function M.disable(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  enabled[buf] = nil
  pending[buf] = nil
  fold_offsets[buf] = nil
  park_offsets[buf] = nil
  extmark_ids[buf] = nil
  bumped[buf] = nil
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for win in pairs(parked) do
    parked[win] = nil
  end
  -- Unpark the cursor if the disabled buffer is the one under the cursor.
  if vim.api.nvim_get_current_buf() == buf then
    pcall(vim.api.nvim_win_set_cursor, 0, { vim.fn.line('.'), vim.fn.col('.') - 1 })
  end
  for win in pairs(ve_wins) do
    restore_virtualedit(win)
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_get_option_value('foldtext', { win = win }) == foldtext_expr then
      vim.api.nvim_set_option_value('foldtext', builtin_foldtext, { win = win })
    end
  end
  -- A previous version set the option globally, so clean it up too.
  if vim.o.foldtext == foldtext_expr then
    vim.o.foldtext = builtin_foldtext
  end
  for key, p in pairs(patched) do
    p.mod[p.fn] = p.orig
    patched[key] = nil
  end
end

function M.toggle(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if enabled[buf] then
    M.disable(buf)
  else
    M.enable(buf)
  end
end

function M.enabled(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  return enabled[buf] == true
end

-- Updates buffers that already have the plugin on, so option changes apply.
local function refresh_buffers()
  for buf in pairs(enabled) do
    M.update(buf)
  end
end

function M.setup(user_opts)
  if user_opts then
    M.options = vim.tbl_deep_extend('force', M.options, user_opts)
  end
  M.highlight()
  integrate_ibl()

  local group = vim.api.nvim_create_augroup('md-indent', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = M.options.filetypes,
    callback = function(ev)
      M.enable(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd({
    'TextChanged',
    'TextChangedI',
    'BufWritePost',
    'BufReadPost',
    'BufWinEnter',
    'FileChangedShellPost',
    'VimResume',
    'BufModifiedSet',
  }, {
    group = group,
    callback = function(ev)
      if enabled[ev.buf] then
        M.schedule_update(ev.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufUnload', {
    group = group,
    callback = function(ev)
      enabled[ev.buf] = nil
      pending[ev.buf] = nil
      fold_offsets[ev.buf] = nil
      park_offsets[ev.buf] = nil
      extmark_ids[ev.buf] = nil
      bumped[ev.buf] = nil
      M.schedule_assert()
    end,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    -- In WinClosed, ev.buf carries the window id.
    callback = function(ev)
      ve_wins[ev.buf] = nil
      parked[ev.buf] = nil
    end,
  })
  -- Blank lines park the cursor past the indent while it rests on them.
  vim.api.nvim_create_autocmd({
    'CursorMoved',
    'CursorMovedI',
    'ModeChanged',
    'WinEnter',
  }, {
    group = group,
    callback = function()
      M.park_cursor()
    end,
  })
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = M.highlight,
  })
  vim.api.nvim_create_autocmd({
    'BufReadPost',
    'BufWinEnter',
    'BufWritePost',
    'VimEnter',
    'User',
    'ColorScheme',
    'VimResume',
  }, {
    group = group,
    callback = M.schedule_assert,
  })

  local filetypes = {}
  for _, ft in ipairs(M.options.filetypes) do
    filetypes[ft] = true
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if filetypes[vim.fn.getbufvar(buf, '&ft')] then
      M.enable(buf)
    end
  end

  vim.api.nvim_create_user_command('MDIndentEnable', function()
    M.enable()
  end, { desc = 'Indent nested headings in the current buffer' })
  vim.api.nvim_create_user_command('MDIndentDisable', function()
    M.disable()
  end, { desc = 'Remove heading indentation from the current buffer' })
  vim.api.nvim_create_user_command('MDIndentToggle', function()
    M.toggle()
  end, { desc = 'Turn heading indentation on or off in the current buffer' })

  refresh_buffers()
end

return M
