-- Markdown heading navigation, ported from the host's nvim 0.11 config to
-- native Neovim 0.12 treesitter APIs. The old version depended on the legacy
-- nvim-treesitter Lua API (`require("nvim-treesitter.ts_utils").goto_node` and
-- the `nvim_treesitter#foldexpr()` autoload function), both of which are gone
-- in the rewritten nvim-treesitter that nvf ships. Everything below uses only
-- the built-in `vim.treesitter` runtime, so there is no plugin dependency.

--- Parsed once at load. `atx_heading` is the `# Heading` node in the markdown
--- grammar. Kept equivalent to the host behavior (setext headings excluded).
local query = vim.treesitter.query.parse("markdown", "(atx_heading) @heading")

--- Return the 0-based start row of every atx_heading in the buffer, ascending.
---@param bufnr integer
---@return integer[]
local function heading_rows(bufnr)
  local parser = assert(vim.treesitter.get_parser(bufnr, "markdown"))
  local root = parser:parse()[1]:root()
  local rows = {}
  for _, node in query:iter_captures(root, bufnr, 0, -1) do
    rows[#rows + 1] = (node:start())
  end
  return rows
end

--- Jump to the count-th heading in the given direction, then scroll it to the
--- top of the window (`zt`). No-op if there is no such heading.
---@param direction "next" | "prev"
local function jump(direction)
  local count = vim.v.count == 0 and 1 or vim.v.count
  local cur = vim.fn.line(".") - 1 -- current row, 0-based
  local rows = heading_rows(0)

  -- `vim.iter` chains make the directional lookup declarative:
  --   next -> first heading strictly after cursor
  --   prev -> reverse, then first heading strictly before cursor
  local target
  if direction == "next" then
    target = vim.iter(rows):filter(function(r) return r > cur end):nth(count)
  else
    target = vim.iter(rows):rev():filter(function(r) return r < cur end):nth(count)
  end

  if target then
    vim.api.nvim_win_set_cursor(0, { target + 1, 0 })
    vim.cmd("normal! zt")
  end
end

-- Hard-wrap markdown prose at 80 columns.
vim.opt_local.textwidth = 80

-- Repurpose `gc` (Comment.nvim) as a blockquote toggle: prefix lines with "> ".
-- Markdown's stock commentstring is "<!-- %s -->", which is near-useless in
-- prose; blockquotes are far more common. Comment.nvim falls back to
-- `commentstring` for markdown (it has no built-in ft entry), so this is enough.
vim.bo.commentstring = "> %s"

-- Per-markdown treesitter folding using the native foldexpr (the replacement
-- for the removed `nvim_treesitter#foldexpr()`). foldlevel 99 keeps the file
-- open by default, matching the host.
vim.opt_local.foldmethod = "expr"
vim.opt_local.foldexpr = "v:lua.vim.treesitter.foldexpr()"
vim.opt_local.foldlevel = 99

-- `desc` is picked up by which-key-style plugins; `silent` keeps the jump quiet.
vim.keymap.set({ "n", "v" }, "<C-Down>", function() jump("next") end,
  { silent = true, buffer = true, desc = "Markdown: next heading" })
vim.keymap.set({ "n", "v" }, "<C-Up>", function() jump("prev") end,
  { silent = true, buffer = true, desc = "Markdown: previous heading" })

-- Intelligent protected line-wrapping for gw.
-- Since gw ignores formatexpr and formatprg, we remap gw to a custom operator.
_G.__markdown_gw_format = function(motion_type)
  local start_line = vim.api.nvim_buf_get_mark(0, "[")[1]
  local end_line = vim.api.nvim_buf_get_mark(0, "]")[1]

  if start_line == 0 or end_line == 0 then
    return
  end

  local parser_ok, parser = pcall(vim.treesitter.get_parser, 0, "markdown")
  if not parser_ok or not parser then
    -- Fallback: standard gw
    local count = end_line - start_line
    local saved_view = vim.fn.winsaveview()
    vim.api.nvim_win_set_cursor(0, { start_line, 0 })
    if count == 0 then
      vim.cmd("normal! gww")
    else
      vim.cmd("normal! " .. count .. "gwj")
    end
    vim.fn.winrestview(saved_view)
    return
  end

  local tree = parser:parse(true)[1]
  local root = tree:root()
  local query_str = "((atx_heading) @heading) ((setext_heading) @heading) ((fenced_code_block) @code)"
  local query_ok, query = pcall(vim.treesitter.query.parse, "markdown", query_str)
  if not query_ok or not query then
    -- Fallback: standard gw
    local count = end_line - start_line
    local saved_view = vim.fn.winsaveview()
    vim.api.nvim_win_set_cursor(0, { start_line, 0 })
    if count == 0 then
      vim.cmd("normal! gww")
    else
      vim.cmd("normal! " .. count .. "gwj")
    end
    vim.fn.winrestview(saved_view)
    return
  end

  local protected = {}
  for id, node in query:iter_captures(root, 0, 0, -1) do
    local srow, scol, erow, ecol = node:range()
    local last_row = erow
    if ecol == 0 and erow > srow then
      last_row = erow - 1
    end
    for r = srow, last_row do
      protected[r] = true
    end
  end

  local function is_blank(line_str)
    return line_str:match("^%s*$") ~= nil
  end

  local buffer_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local runs = {}
  local current_run = nil

  for r = start_line - 1, end_line - 1 do
    local line_str = buffer_lines[r + 1]
    if not line_str then
      break
    end

    local is_protected = protected[r] or is_blank(line_str)
    if not is_protected then
      if not current_run then
        current_run = { start_row = r, end_row = r }
      else
        current_run.end_row = r
      end
    else
      if current_run then
        table.insert(runs, current_run)
        current_run = nil
      end
    end
  end

  if current_run then
    table.insert(runs, current_run)
  end

  local delta = 0
  local saved_view = vim.fn.winsaveview()

  for _, run in ipairs(runs) do
    local run_start_1 = run.start_row + 1 + delta
    local run_end_1 = run.end_row + 1 + delta

    local lines_before = vim.api.nvim_buf_line_count(0)

    vim.api.nvim_win_set_cursor(0, { run_start_1, 0 })

    local count = run_end_1 - run_start_1
    if count == 0 then
      vim.cmd("normal! gww")
    else
      vim.cmd("normal! " .. count .. "gwj")
    end

    local lines_after = vim.api.nvim_buf_line_count(0)
    local run_delta = lines_after - lines_before
    delta = delta + run_delta
  end

  vim.fn.winrestview(saved_view)
end

-- Buffer-local keymaps remapping gw to use our custom operator
vim.keymap.set("n", "gw", function()
  vim.go.operatorfunc = "v:lua.__markdown_gw_format"
  return "g@"
end, { expr = true, buffer = true, desc = "Markdown: protected line-wrapping" })

vim.keymap.set("x", "gw", function()
  vim.go.operatorfunc = "v:lua.__markdown_gw_format"
  return "g@"
end, { expr = true, buffer = true, desc = "Markdown: protected line-wrapping" })

vim.keymap.set("n", "gww", function()
  vim.go.operatorfunc = "v:lua.__markdown_gw_format"
  return "g@_"
end, { expr = true, buffer = true, desc = "Markdown: protected line-wrap current line" })
