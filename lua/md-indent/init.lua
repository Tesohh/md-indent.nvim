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

-- 'inline' virtual text shifts the buffer text right, since Nvim 0.10
local function supported()
  return vim.fn.has('nvim-0.10') == 1
end

function M.highlight()
  vim.api.nvim_set_hl(0, 'MdIndent', { link = 'Normal', default = true })
end

local function scan_options()
  return {
    frontmatter = M.options.frontmatter,
    setext_headings = M.options.setext_headings,
    indent_code_blocks = M.options.indent_code_blocks,
  }
end

local function offsets_by_line(entries)
  local map = {}
  for _, e in ipairs(entries) do
    map[e.line] = e.width
  end
  return map
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
  fold_offsets[buf] = offsets_by_line(entries)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, e in ipairs(entries) do
    vim.api.nvim_buf_set_extmark(buf, ns, e.line, 0, {
      virt_text = { { string.rep(' ', e.width), M.options.hl_group } },
      virt_text_pos = 'inline',
      -- Left gravity keeps the extmark at column 0 when text is typed there,
      -- which also draws the insert cursor after the indent.
      right_gravity = false,
      virt_text_repeat_linebreak = true,
    })
  end
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

-- Takes over 'foldtext' when nothing owns it, otherwise pads the fold text
-- function of the plugin that owns the option.
local function assert_foldtext()
  local current = vim.o.foldtext
  if current == foldtext_expr then
    return
  end
  if current == '' or current == builtin_foldtext then
    vim.o.foldtext = foldtext_expr
    return
  end
  if not pad_foldtext_fn(current) and not foldtext_warned then
    foldtext_warned = true
    vim.notify('md-indent: cannot pad the foldtext of ' .. current, vim.log.levels.WARN)
  end
end

-- Runs after the autocmds of other plugins, so the option ends up ours.
function M.schedule_assert()
  if assert_pending then
    return
  end
  assert_pending = true
  vim.schedule(function()
    assert_pending = false
    for _ in pairs(enabled) do
      assert_foldtext()
      return
    end
  end)
end

function M.enable(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not supported() then
    vim.notify('md-indent: needs Nvim 0.10 or newer', vim.log.levels.WARN)
    return false
  end
  assert_foldtext()
  if enabled[buf] then
    return true
  end
  enabled[buf] = true
  M.update(buf)
  return true
end

function M.disable(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  enabled[buf] = nil
  pending[buf] = nil
  fold_offsets[buf] = nil
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _ in pairs(enabled) do
    return
  end
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
local function refresh()
  for buf in pairs(enabled) do
    M.update(buf)
  end
end

function M.setup(user_opts)
  if user_opts then
    M.options = vim.tbl_deep_extend('force', M.options, user_opts)
  end
  M.highlight()

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

  refresh()
end

return M
