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

-- Hide line numbers in markdown files.
vim.opt_local.number = false
vim.opt_local.relativenumber = false

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

-- Manual structural formatting via conform + mdformat (",md"). mdformat
-- defaults to --wrap=keep, so this only normalizes document structure (blank
-- lines around headings/lists, list markers, trailing whitespace) and leaves
-- prose wrapping to the `gw` operator below. Scoped to markdown so the keymap
-- only exists where a formatter is actually configured. Bound to <leader>md
-- (not <leader>ff) so it shares no prefix with <leader>f (",f", the combined
-- wrap+format binding) -- otherwise both ,f and ,ff mapped would impose a
-- timeoutlen delay on the common ,f path while Neovim waits to disambiguate.
vim.keymap.set("n", "<leader>md", function()
  require("conform").format({ bufnr = 0 })
end, { silent = true, buffer = true, desc = "Markdown: format buffer (mdformat)" })

-- Intelligent protected line-wrapping for gW.
-- Since gw ignores formatexpr and formatprg, we remap gW to a custom operator.
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
  local query_str = "((atx_heading) @heading) ((setext_heading) @heading) ((fenced_code_block) @code) ((pipe_table) @table)"
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

-- Buffer-local keymaps remapping gW to use our custom operator
vim.keymap.set("n", "gW", function()
  vim.go.operatorfunc = "v:lua.__markdown_gw_format"
  return "g@"
end, { expr = true, buffer = true, desc = "Markdown: protected line-wrapping" })

vim.keymap.set("x", "gW", function()
  vim.go.operatorfunc = "v:lua.__markdown_gw_format"
  return "g@"
end, { expr = true, buffer = true, desc = "Markdown: protected line-wrapping" })

vim.keymap.set("n", "gWW", function()
  vim.go.operatorfunc = "v:lua.__markdown_gw_format"
  return "g@_"
end, { expr = true, buffer = true, desc = "Markdown: protected line-wrap current line" })

vim.keymap.set("n", "gw", function()
  local saved_view = vim.fn.winsaveview()
  vim.api.nvim_buf_set_mark(0, "[", 1, 0, {})
  local last_line = vim.api.nvim_buf_line_count(0)
  vim.api.nvim_buf_set_mark(0, "]", last_line, 0, {})
  _G.__markdown_gw_format("line")
  vim.fn.winrestview(saved_view)
end, { buffer = true, desc = "Markdown: protected line-wrap entire file" })

-- Combined wrap + format on <leader>f (",f"). Runs the protected line-wrap
-- (`gw`) over the whole buffer, THEN mdformat via conform. mdformat runs LAST
-- in --wrap=keep mode (conform's default), so it normalizes structure and
-- re-indents list continuation lines while preserving the breaks `gw` just
-- produced -- the order is what stops mdformat from unwrapping prose and stops
-- `gw` from leaving list items un-indented. Exposed on _G so headless tests can
-- call it directly.
_G.__markdown_format_all = function()
  local saved_view = vim.fn.winsaveview()
  vim.api.nvim_buf_set_mark(0, "[", 1, 0, {})
  local last_line = vim.api.nvim_buf_line_count(0)
  vim.api.nvim_buf_set_mark(0, "]", last_line, 0, {})
  _G.__markdown_gw_format("line")
  require("conform").format({ bufnr = 0 })
  vim.fn.winrestview(saved_view)
end

vim.keymap.set("n", "<leader>f", _G.__markdown_format_all,
  { silent = true, buffer = true, desc = "Markdown: wrap + format buffer" })

-- Convert GFM pipe tables to YAML-style lists on <leader>tl (",tl"),
-- visual selection only. Tables are hard to scan as raw text; each row
-- becomes a list item with the first column on the item line and the
-- remaining columns as indented "Header: value" lines, e.g.
--   | Option | Type |    ->  - Option: `wrap`
--   | `wrap` | string |         Type: string
-- One-way for now, but the header-as-key layout keeps a future reverse
-- mapping (e.g. ,lt) lossless -- only the delimiter row's alignment
-- hints are dropped. Cell text passes through verbatim (backticks,
-- escaped pipes); treesitter already resolved cell boundaries, so "\|"
-- and pipes inside code spans do not split cells.
-- Selection semantics: every table overlapping the selection converts
-- in full (a partial selection never truncates a table); other prose in
-- the selection is left untouched. x-mode only (visual scope), and the
-- key shares no prefix with <leader>f (see the <leader>md note above).
-- Known limitation: a table indented inside a list item is replaced at
-- column 0 (dedented).
local function tl_trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Collect the text of every pipe_table_cell child of a header/row node.
---@param row_node TSNode
---@return string[]
local function tl_row_cells(row_node)
  local cells = {}
  for child in row_node:iter_children() do
    if child:type() == "pipe_table_cell" then
      cells[#cells + 1] = tl_trim(vim.treesitter.get_node_text(child, 0))
    end
  end
  return cells
end

--- Render one table row as a list item line plus indented key lines.
---@param headers string[]
---@param cells string[]
---@return string[]
local function tl_list_item(headers, cells)
  local lines = {}
  for i, key in ipairs(headers) do
    local value = cells[i] or ""
    local text = key .. ":" .. (value ~= "" and (" " .. value) or "")
    lines[#lines + 1] = (i == 1 and "- " or "  ") .. text
  end
  return lines
end

_G.__markdown_table_to_list = function(start_line, end_line)
  if not (start_line and end_line) then
    start_line = vim.api.nvim_buf_get_mark(0, "<")[1]
    end_line = vim.api.nvim_buf_get_mark(0, ">")[1]
  end
  if not start_line or start_line == 0 or not end_line or end_line == 0 then
    vim.notify("table-to-list: no visual selection", vim.log.levels.WARN)
    return
  end
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  local parser_ok, parser = pcall(vim.treesitter.get_parser, 0, "markdown")
  if not parser_ok or not parser then
    vim.notify("table-to-list: markdown parser unavailable",
      vim.log.levels.WARN)
    return
  end
  local query_ok, q = pcall(vim.treesitter.query.parse, "markdown",
    "(pipe_table) @table")
  if not query_ok or not q then
    vim.notify("table-to-list: pipe_table query failed", vim.log.levels.WARN)
    return
  end

  local sel_srow, sel_erow = start_line - 1, end_line - 1
  local tables = {}
  for _, node in q:iter_captures(parser:parse(true)[1]:root(), 0, 0, -1) do
    local srow, _, erow, ecol = node:range()
    local last_row = (ecol == 0 and erow > srow) and (erow - 1) or erow
    if srow <= sel_erow and last_row >= sel_srow then
      tables[#tables + 1] = { node = node, srow = srow, last_row = last_row }
    end
  end
  if #tables == 0 then
    vim.notify("table-to-list: no table in selection", vim.log.levels.WARN)
    return
  end

  -- Replace bottom-up so earlier table ranges stay valid.
  table.sort(tables, function(a, b) return a.srow > b.srow end)

  local converted, skipped = 0, 0
  for _, t in ipairs(tables) do
    local header_node, rows = nil, {}
    for child in t.node:iter_children() do
      local ty = child:type()
      if ty == "pipe_table_header" then
        header_node = child
      elseif ty == "pipe_table_row" then
        rows[#rows + 1] = child
      end
    end
    if not header_node or #rows == 0 then
      skipped = skipped + 1
    else
      local headers = tl_row_cells(header_node)
      local new_lines = {}
      for _, row in ipairs(rows) do
        vim.list_extend(new_lines, tl_list_item(headers, tl_row_cells(row)))
      end
      vim.api.nvim_buf_set_lines(0, t.srow, t.last_row + 1, false, new_lines)
      converted = converted + 1
    end
  end

  -- Drop the visual selection highlight left behind by the x-mode mapping.
  if vim.fn.mode():find("^[vV\22]") then
    vim.cmd("normal! \27")
  end

  local msg = ("table-to-list: converted %d table(s)"):format(converted)
  if skipped > 0 then
    msg = msg .. (", skipped %d (empty)"):format(skipped)
  end
  vim.notify(msg, vim.log.levels.INFO)
end

vim.keymap.set("x", "<leader>tl", function()
  _G.__markdown_table_to_list()
end, { silent = true, buffer = true, desc = "Markdown: table to list" })
