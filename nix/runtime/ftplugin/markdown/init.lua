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
