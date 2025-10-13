local cmake = require('cmake')
local api = vim.api

local M = {}

-- buffer and window handles
M.bufnr = nil
M.winid = nil
-- track which targets are expanded
M.expanded = {}

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
  -- set a non-selectable header via the winbar to indicate this is the CMake TUI
  -- use pcall in case winbar not supported
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


  vim.keymap.set("n", "<CR>", M.toggle_target, { noremap = true, silent = true, buffer = M.bufnr })
  vim.keymap.set("n", "q", M.close, { noremap = true, silent = true, buffer = M.bufnr })

  M.render()
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
end

-- Toggle expansion of target under cursor
function M.toggle_target()
  if not (M.bufnr and api.nvim_win_is_valid(M.winid)) then
    return
  end
  local row = api.nvim_win_get_cursor(M.winid)[1]
  local line = api.nvim_buf_get_lines(M.bufnr, row - 1, row, false)[1] or ''
  -- extract target name: prefix (non-space bytes) then spaces, then name
  local name = line:match('^%S+%s+(.+)$')
  if name then
    M.expanded[name] = not M.expanded[name]
    M.render()
  end
end

-- Render the panel contents
function M.render()
  if not (M.bufnr and api.nvim_buf_is_valid(M.bufnr)) then
    return
  end
  -- collect targets
  local targets = {}
  if cmake.state and cmake.state.dir_cache_object and cmake.state.dir_cache_object.targets then
    targets = cmake.state.dir_cache_object.targets
  end
  -- sort names
  local names = {}
  for name in pairs(targets) do
    table.insert(names, name)
  end
  table.sort(names)
  -- build lines
  local lines = {}
  for _, name in ipairs(names) do
    local expanded = M.expanded[name]
    local prefix = expanded and '▼' or '▶'
    table.insert(lines, prefix .. ' ' .. name)
    if expanded then
      local target = targets[name]
      -- show core fields
      table.insert(lines, '  relative: ' .. tostring(target.current_target_relative or ''))
      table.insert(lines, '  file: ' .. tostring(target.current_target_file or ''))
      table.insert(lines, '  is_exec: ' .. tostring(target.is_exec))
      -- args may be string or table
      if target.args then
        local args = target.args
        if type(args) == 'table' then
          args = table.concat(args, ' ')
        end
        table.insert(lines, '  args: ' .. tostring(args))
      end
      -- breakpoints
      if target.breakpoints and next(target.breakpoints) then
        table.insert(lines, '  breakpoints:')
        for bp, info in pairs(target.breakpoints) do
          local status = info.enabled and 'enabled' or 'disabled'
          table.insert(lines, '    ' .. tostring(bp) .. ': ' .. tostring(info.text) .. ' (' .. status .. ')')
        end
      end
    end
  end
  -- update buffer
  api.nvim_buf_set_option(M.bufnr, 'modifiable', true)
  api.nvim_buf_set_lines(M.bufnr, 0, -1, false, lines)
  api.nvim_buf_set_option(M.bufnr, 'modifiable', false)
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
