local api = vim.api

local M = {}

local state = {
  last = nil,
  view_buf = nil,
  view_win = nil,
}

local MAX_LOG_LINES = 800

local function classify(level)
  if not level then
    return "E"
  end
  local lower = level:lower()
  if lower:find("warn", 1, true) then
    return "W"
  end
  if lower:find("note", 1, true) then
    return "I"
  end
  return "E"
end

local function parse_line(line)
  if not line or line == "" then
    return nil
  end

  local file, lnum, col, level, message = line:match("^(.+):(%d+):(%d+):%s*(%w+):%s*(.+)")
  if file then
    local item = {
      filename = vim.trim(file),
      lnum = tonumber(lnum),
      col = tonumber(col),
      level = level,
      type = classify(level),
      text = vim.trim(message),
    }
    if item.type ~= "I" then
      return item
    end
    return nil
  end

  local file2, lnum2, level2, message2 = line:match("^(.+):(%d+):%s*(%w+):%s*(.+)")
  if file2 then
    local item = {
      filename = vim.trim(file2),
      lnum = tonumber(lnum2),
      col = 1,
      level = level2,
      type = classify(level2),
      text = vim.trim(message2),
    }
    if item.type ~= "I" then
      return item
    end
    return nil
  end

  local file3, lnum3, col3, level3, code3, message3 =
    line:match("^(.+)%((%d+),(%d+)%)%s*:%s*(%w+)%s*([%w%d]+)%s*:%s*(.+)")
  if file3 then
    local item = {
      filename = vim.trim(file3),
      lnum = tonumber(lnum3),
      col = tonumber(col3),
      level = level3 .. " " .. code3,
      type = classify(level3),
      text = vim.trim(message3),
    }
    if item.type ~= "I" then
      return item
    end
    return nil
  end

  return nil
end

local function trim_log(log)
  while #log > MAX_LOG_LINES do
    table.remove(log, 1)
  end
end

local function notify(message, level)
  vim.notify("cmake.nvim: " .. message, level or vim.log.levels.INFO)
end

local function store_capture(capture)
  state.last = capture

  local items = {}
  local has_error = false
  for _, entry in ipairs(capture.entries) do
    local item = {
      filename = entry.filename or "",
      lnum = entry.lnum or 1,
      col = entry.col or 1,
      text = entry.text or "",
      type = entry.type or "E",
    }
    if entry.type == "E" then
      has_error = true
    end
    table.insert(items, item)
  end

  if #items > 0 then
    vim.fn.setqflist({}, "r", {
      title = "CMake Build",
      items = items,
    })
    if has_error then
      vim.cmd("copen")
    end
    notify(string.format("Captured %d build diagnostic messages", #items),
      has_error and vim.log.levels.ERROR or vim.log.levels.WARN)
  end
end

local function ensure_view_buffer()
  if state.view_buf and api.nvim_buf_is_valid(state.view_buf) then
    if state.view_win and api.nvim_win_is_valid(state.view_win) then
      api.nvim_set_current_win(state.view_win)
    else
      local win = api.nvim_get_current_win()
      if api.nvim_win_get_buf(win) ~= state.view_buf then
        api.nvim_win_set_buf(win, state.view_buf)
      end
      state.view_win = win
    end
    return state.view_buf, state.view_win
  end

  vim.cmd("botright vsplit")
  local win = api.nvim_get_current_win()
  local buf = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(win, buf)
  api.nvim_buf_set_option(buf, "buftype", "nofile")
  api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  api.nvim_buf_set_option(buf, "swapfile", false)
  api.nvim_buf_set_option(buf, "filetype", "cmake_diagnostics")
  api.nvim_buf_set_name(buf, "cmake://diagnostics")
  vim.keymap.set("n", "q", function()
    if api.nvim_win_is_valid(win) then
      api.nvim_win_close(win, true)
    end
  end, { buffer = buf, noremap = true, silent = true })
  state.view_buf = buf
  state.view_win = win
  return buf, win
end

local function render_view(capture)
  local lines = {}
  table.insert(lines, string.format("Target: %s", capture.target or "unknown"))
  table.insert(lines, string.format("Exit code: %s", capture.exit_code ~= nil and tostring(capture.exit_code) or "unknown"))
  table.insert(lines, string.format("Diagnostics: %d", #capture.entries))
  table.insert(lines, "")

  if #capture.entries == 0 then
    table.insert(lines, "  No diagnostics captured for the last build.")
  else
    table.insert(lines, "  Messages:")
    for _, entry in ipairs(capture.entries) do
      local level = entry.type == "W" and "WARN" or "ERROR"
      local location = string.format("%s:%d:%d", entry.filename or "?", entry.lnum or 0, entry.col or 0)
      table.insert(lines, string.format("    %s %-5s %s", location, level, entry.text or ""))
    end
  end

  if #capture.raw_output > 0 then
    table.insert(lines, "")
    table.insert(lines, "  Raw output (tail):")
    for _, line in ipairs(capture.raw_output) do
      table.insert(lines, "    " .. line)
    end
  end

  return lines
end

function M.start_capture(opts)
  local capture = {
    target = opts and opts.target or nil,
    build_dir = opts and opts.build_dir or nil,
    entries = {},
    raw_output = {},
    exit_code = nil,
  }

  local function absorb(data, stream)
    for _, line in ipairs(data or {}) do
      if line and line ~= "" then
        table.insert(capture.raw_output, line)
        trim_log(capture.raw_output)
        local entry = parse_line(line)
        if entry then
          entry.stream = stream
          table.insert(capture.entries, entry)
        end
      end
    end
  end

  return {
    stdout = function(_, data, _)
      absorb(data, "stdout")
    end,
    stderr = function(_, data, _)
      absorb(data, "stderr")
    end,
    finish = function(exit_code)
      capture.exit_code = exit_code
      store_capture(capture)
    end,
  }
end

function M.show()
  if not state.last then
    notify("No build diagnostics captured yet", vim.log.levels.INFO)
    return
  end

  local buf = ensure_view_buffer()
  api.nvim_buf_set_option(buf, "modifiable", true)
  api.nvim_buf_set_lines(buf, 0, -1, false, render_view(state.last))
  api.nvim_buf_set_option(buf, "modifiable", false)
  api.nvim_buf_set_option(buf, "modified", false)
end

return M
