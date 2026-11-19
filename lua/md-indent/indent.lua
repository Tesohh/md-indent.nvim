-- Computes the indentation offset for every line, inspired by org-indent.
-- Pure Lua: no Neovim API calls, so the scanner can be tested standalone.

local M = {}

-- Lua patterns cannot put a quantifier after a capture group, so heading and
-- fence markers are matched against the text after the leading whitespace.
local leading = '^%s?%s?%s?'

-- YAML metadata block delimiters at the first line of the file.
local frontmatter_open = '^---[%w_-]*%s*$'
local frontmatter_close = '^---%s*$'

local function is_blank(line)
  return line:match('^%s*$') ~= nil
end

-- Returns the text after at most 3 leading whitespace characters.
local function strip_leading(line)
  local lead = line:match(leading)
  return line:sub(#lead + 1)
end

-- Number of leading whitespace characters of a line.
local function lead_width(line)
  return #line:match(leading)
end

-- Returns a heading level (1..6) for an ATX heading line, else nil.
local function atx_level(line)
  local rest = strip_leading(line)
  local hashes = rest:match('^#+')
  if not hashes or #hashes > 6 then
    return nil
  end
  -- '#' must be followed by a space, so a heading that is still being typed
  -- stays body text and does not move the line around.
  local after = rest:sub(#hashes + 1)
  if after:sub(1, 1) ~= ' ' and after:sub(1, 1) ~= '\t' then
    return nil
  end
  return #hashes
end

-- Returns the end line (1-based) of a YAML metadata block, else nil.
local function frontmatter_end(lines)
  if not lines[1] or not lines[1]:match(frontmatter_open) then
    return nil
  end
  for i = 2, #lines do
    if lines[i]:match(frontmatter_close) then
      return i
    end
  end
  return nil
end

-- Returns whether a line closes the code fence started by `fence`.
local function closes_fence(line, fence)
  local marker = strip_leading(line):match('^[%`~]+%s*$')
  return marker ~= nil and marker:sub(1, 1) == fence.char and #marker >= fence.len
end

-- Scans `lines` and returns { { line = 0-based index, width = n }, ... }.
-- A heading of level n sits n - 1 columns in, and its body text lines up
-- with the heading text at 2 * n. The level alone decides every offset. Only
-- lines that need an offset are returned; existing line indentation is kept
-- in the buffer text, so `width` is added on top of it.
function M.scan(lines, opts)
  opts = opts or {}
  local use_setext = opts.setext_headings or false
  local indent_code = opts.indent_code_blocks ~= false

  -- Innermost heading first: { level, head = heading offset, body = text offset }
  -- The stack only tells blank lines, code fences, and setext underlines which
  -- heading is current
  local stack = {}
  local out = {}
  local fence = nil -- open code fence: { char, len }
  local paragraph = false -- previous line is paragraph text (setext candidate)
  local skip_until = opts.frontmatter and frontmatter_end(lines) or 0

  for i, line in ipairs(lines) do
    if i <= skip_until then
      paragraph = false
    else
      local closed = false
      if fence then
        if closes_fence(line, fence) then
          fence = nil
          closed = true
        end
      else
        local marker = strip_leading(line):match('^[%`~]+')
        if marker and #marker >= 3 then
          fence = { char = marker:sub(1, 1), len = #marker }
        end
      end
      -- A fence line is never paragraph text, so it cannot start a setext heading.
      local in_code = fence ~= nil or closed

      if in_code then
        paragraph = false
      end

      local heading = nil
      if not in_code then
        heading = atx_level(line)
      end
      -- A heading of level n sits n - 1 columns in, and its body text lines up
      -- with the heading text at 2 * n.
      local offset
      local function place(heading_level)
        local lead = lead_width(line)
        offset = lead + heading_level - 1
        stack[#stack + 1] = { level = heading_level, head = offset, body = lead + 2 * heading_level }
        paragraph = false
      end
      if heading then
        while #stack > 0 and stack[#stack].level >= heading do
          stack[#stack] = nil
        end
        place(heading)
      else
        local underline = use_setext and paragraph
            and strip_leading(line):match('^[=-]+%s*$')
        if underline then
          local level = underline:sub(1, 1) == '=' and 1 or 2
          -- A setext heading keeps its text on the line above, so only the
          -- underline takes the heading offset itself.
          while #stack > 0 and stack[#stack].level >= level do
            stack[#stack] = nil
          end
          place(level)
        elseif is_blank(line) then
          paragraph = false
          local top = stack[#stack]
          offset = top and top.head or 0
        else
          paragraph = true
          local top = stack[#stack]
          offset = top and top.body or 0
        end
      end

      if offset > 0 and (not in_code or indent_code) then
        out[#out + 1] = { line = i - 1, width = offset }
      end
    end
  end

  return out
end

return M
