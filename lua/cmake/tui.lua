local cmake = require('cmake')
local extras = require('cmake.tui_extras')
local api = vim.api

local M = {}

local ns = api.nvim_create_namespace('cmake_tui')
local highlight_initialized = false

-- buffer and window handles
M.bufnr = nil
M.winid = nil
-- track which targets are expanded
M.expanded = {}

local function target_name_from_line(line)
  return extras.extract_target_name(line or "")
end

local function set_default_hl(name, opts)
  opts = vim.tbl_extend(
    "force",
    { default = true },
    opts or {}
  )
  api.nvim_set_hl(0, name, opts)
end

local function ensure_highlights()
  if highlight_initialized then
    return
  end
  set_default_hl("CMakeTuiFilter", { link = "Title" })
  set_default_hl("CMakeTuiActions", { link = "Comment" })
  set_default_hl("CMakeTuiArrow", { link = "Boolean" })
  set_default_hl("CMakeTuiBadgeExecutable", { link = "Function" })
  set_default_hl("CMakeTuiBadgeLibrary", { link = "Type" })
  set_default_hl("CMakeTuiBadgeTest", { link = "DiagnosticWarn" })
  set_default_hl("CMakeTuiBadgeOther", { link = "Identifier" })
  set_default_hl("CMakeTuiTarget", { link = "String" })
  set_default_hl("CMakeTuiDetailKey", { link = "Statement" })
  set_default_hl("CMakeTuiMuted", { link = "Comment" })
  highlight_initialized = true
end

local badge_highlights = {
  EXE = "CMakeTuiBadgeExecutable",
  LIB = "CMakeTuiBadgeLibrary",
  TST = "CMakeTuiBadgeTest",
  OTH = "CMakeTuiBadgeOther",
}

local function highlight_target_row(line, row)
  api.nvim_buf_add_highlight(M.bufnr, ns, "CMakeTuiArrow", row, 0, 1)
  local badge_start, badge_end = line:find("%b[]")
  if badge_start and badge_end then
    local badge_name = line:sub(badge_start + 1, badge_end - 1)
    local group = badge_highlights[badge_name] or "CMakeTuiBadgeOther"
    api.nvim_buf_add_highlight(
      M.bufnr,
      ns,
      group,
      row,
      badge_start - 1,
      badge_end
    )
    local after = badge_end + 2
    if after <= #line then
      api.nvim_buf_add_highlight(
        M.bufnr,
        ns,
        "CMakeTuiTarget",
        row,
        after - 1,
        -1
      )
    end
  end
end

local function highlight_detail_row(line, row)
  local first = line:find("%S")
  if not first then
    return
  end
  local colon = line:find(":", first)
  if not colon then
    return
  end
  api.nvim_buf_add_highlight(
    M.bufnr,
    ns,
    "CMakeTuiDetailKey",
    row,
    first - 1,
    colon - 1
  )
end

local function apply_highlights(lines)
  if not (M.bufnr and api.nvim_buf_is_valid(M.bufnr)) then
    return
  end
  ensure_highlights()
  api.nvim_buf_clear_namespace(M.bufnr, ns, 0, -1)
  for index, line in ipairs(lines) do
    local row = index - 1
    if vim.startswith(line, "Filter:") then
      api.nvim_buf_add_highlight(M.bufnr, ns, "CMakeTuiFilter", row, 0, -1)
    elseif vim.startswith(line, "Actions:") then
      api.nvim_buf_add_highlight(M.bufnr, ns, "CMakeTuiActions", row, 0, -1)
    elseif vim.startswith(line, "  No targets") then
      api.nvim_buf_add_highlight(M.bufnr, ns, "CMakeTuiMuted", row, 0, -1)
    else
      local first = line:sub(1, 1)
      if first == "▼" or first == "▶" then
        highlight_target_row(line, row)
      elseif line:match("^%s+%S") then
        highlight_detail_row(line, row)
      end
    end
  end
end

local function find_target_under_cursor()
  if not (M.bufnr and api.nvim_buf_is_valid(M.bufnr)) then
    return nil
  end
  local row = api.nvim_win_get_cursor(M.winid)[1]
  local line = api.nvim_buf_get_lines(M.bufnr, row - 1, row, false)[1] or ""
  local name = target_name_from_line(line)
  if name then
    return name
  end
  for i = row - 1, 1, -1 do
    local prev = api.nvim_buf_get_lines(M.bufnr, i - 1, i, false)[1] or ""
    local parent = target_name_from_line(prev)
    if parent then
      return parent
    end
  end
  return nil
end

local function set_cursor_to_first_target()
  if not (M.winid and api.nvim_win_is_valid(M.winid)) then
    return
  end
  local total_lines = api.nvim_buf_line_count(M.bufnr)
  if total_lines >= 3 then
    api.nvim_win_set_cursor(M.winid, { 3, 0 })
  else
    api.nvim_win_set_cursor(M.winid, { 1, 0 })
  end
end

function M.is_open()
  return M.winid and api.nvim_win_is_valid(M.winid)
end

function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.open()
  end
end

-- Open the CMake TUI panel on the left side
function M.open()
  -- if already open, just focus
  if M.is_open() then
    api.nvim_set_current_win(M.winid)
    return
  end
  -- create buffer
  M.bufnr = api.nvim_create_buf(false, true)
  -- calculate width for the split
  local width = math.floor(vim.o.columns * 0.3)
  -- open vertical split on the left and set buffer
  vim.cmd('topleft vsplit')
  M.winid = api.nvim_get_current_win()
  api.nvim_win_set_buf(M.winid, M.bufnr)
  -- resize to desired width
  vim.cmd('vertical resize ' .. width)
  -- show a non-selectable header via the winbar so the pane is easy to spot
  -- use pcall in case winbar is not supported
  pcall(api.nvim_win_set_option, M.winid, 'winbar', ' CMake Targets ')
  -- buffer options
  api.nvim_buf_set_option(M.bufnr, 'bufhidden', 'wipe')
  api.nvim_buf_set_option(M.bufnr, 'buftype', 'nofile')
  api.nvim_buf_set_option(M.bufnr, 'swapfile', false)
  api.nvim_buf_set_option(M.bufnr, 'filetype', 'cmake_tui')
  -- window options
  api.nvim_win_set_option(M.winid, 'wrap', false)
  api.nvim_win_set_option(M.winid, 'cursorline', true)
  api.nvim_win_set_option(M.winid, 'number', false)
  api.nvim_win_set_option(M.winid, 'relativenumber', false)


  local opts = { noremap = true, silent = true, buffer = M.bufnr }
  vim.keymap.set("n", "<CR>", M.toggle_target, opts)
  vim.keymap.set("n", "q", M.close, opts)
  vim.keymap.set("n", "f", function()
    M.cycle_filter(1)
  end, opts)
  vim.keymap.set("n", "F", function()
    M.cycle_filter(-1)
  end, opts)
  vim.keymap.set("n", "a", function()
    M.apply_filter("all")
  end, opts)
  vim.keymap.set("n", "e", function()
    M.apply_filter("executables")
  end, opts)
  vim.keymap.set("n", "l", function()
    M.apply_filter("libraries")
  end, opts)
  vim.keymap.set("n", "t", function()
    M.apply_filter("tests")
  end, opts)
  vim.keymap.set("n", "b", function()
    M.run_action("build")
  end, opts)
  vim.keymap.set("n", "r", function()
    M.run_action("run")
  end, opts)
  vim.keymap.set("n", "d", function()
    M.run_action("debug")
  end, opts)

  M.render()
  set_cursor_to_first_target()
end

-- Close the panel
function M.close()
  if M.is_open() then
    api.nvim_win_close(M.winid, true)
  end
  if M.bufnr and api.nvim_buf_is_valid(M.bufnr) then
    api.nvim_buf_delete(M.bufnr, { force = true })
  end
  M.winid = nil
  M.bufnr = nil
  M.expanded = {}
  extras.reset()
end

-- Toggle expansion of target under cursor
function M.toggle_target()
  if not (M.bufnr and api.nvim_win_is_valid(M.winid)) then
    return
  end
  local name = find_target_under_cursor()
  if not name then
    return
  end
  M.expanded[name] = not M.expanded[name]
  M.render()
end

function M.cycle_filter(direction)
  extras.cycle_filter(direction)
  M.render()
  set_cursor_to_first_target()
end

function M.apply_filter(key)
  extras.set_filter(key)
  M.render()
  set_cursor_to_first_target()
end

function M.run_action(action)
  if not (M.bufnr and api.nvim_win_is_valid(M.winid)) then
    return
  end
  local name = find_target_under_cursor()
  if not name then
    return
  end
  extras.run_action(action, name)
end

-- Render the panel contents
function M.render()
  if not (M.bufnr and api.nvim_buf_is_valid(M.bufnr)) then
    return
  end
  local lines = extras.render_lines(M.expanded)
  if #lines == 0 then
    lines = { "" }
  end
  api.nvim_buf_set_option(M.bufnr, 'modifiable', true)
  api.nvim_buf_set_lines(M.bufnr, 0, -1, false, lines)
  api.nvim_buf_set_option(M.bufnr, 'modifiable', false)
  apply_highlights(lines)
  -- ensure cursor in bounds
  if M.winid and api.nvim_win_is_valid(M.winid) then
    local cursor = api.nvim_win_get_cursor(M.winid)
    local row = cursor[1]
    if row > #lines then
      api.nvim_win_set_cursor(M.winid, { 1, 0 })
    end
  end
end

return M
