local api = vim.api
local uv = vim.loop

local M = {}

local ns = api.nvim_create_namespace("cmake_status")
local last_extmark = nil
local last_buf = nil

local function async(fn)
  if vim.in_fast_event() then
    vim.schedule(fn)
  else
    fn()
  end
end

local function highlight(group, fallback)
  if vim.fn.hlexists(group) == 1 then
    return group
  end
  return fallback or "Comment"
end

local function format_elapsed(start_ns)
  if not start_ns then
    return ""
  end
  local elapsed = (uv.hrtime() - start_ns) / 1e9
  if elapsed < 0 then
    return ""
  end
  return string.format(" (%.2fs)", elapsed)
end

local function set_virtual_text(text, hl)
  async(function()
    local buf = api.nvim_get_current_buf()
    if not api.nvim_buf_is_valid(buf) then
      return
    end
    if last_buf and api.nvim_buf_is_valid(last_buf) then
      api.nvim_buf_clear_namespace(last_buf, ns, 0, -1)
    end
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    local line = math.max(api.nvim_buf_line_count(buf) - 1, 0)
    last_extmark = api.nvim_buf_set_extmark(buf, ns, line, 0, {
      virt_text = { { text, highlight(hl, "Comment") } },
      virt_text_pos = "eol",
    })
    last_buf = buf
  end)
end

local function reset_virtual_text()
  async(function()
    if last_buf and api.nvim_buf_is_valid(last_buf) then
      api.nvim_buf_clear_namespace(last_buf, ns, 0, -1)
    end
    last_extmark = nil
    last_buf = nil
  end)
end

local state = {
  configure = {
    phase = "idle",
    started = nil,
    ok = nil,
    message = "",
    hl = nil,
    timer = nil,
  },
  build = {
    phase = "idle",
    started = nil,
    ok = nil,
    target = nil,
    message = "",
    hl = nil,
    timer = nil,
  },
  tests = {
    phase = "idle",
    started = nil,
    ok = nil,
    message = "",
    hl = nil,
    timer = nil,
  },
}

local function cancel_timer(entry)
  if entry.timer then
    entry.timer:stop()
    entry.timer:close()
    entry.timer = nil
  end
end

local function schedule_idle(entry, delay)
  cancel_timer(entry)
  local timer = uv.new_timer()
  timer:start(delay, 0, function()
    timer:stop()
    timer:close()
    entry.timer = nil
    entry.phase = "idle"
    entry.message = ""
    entry.ok = nil
    entry.hl = nil
    entry.started = nil
    M.refresh()
  end)
  entry.timer = timer
end

local function statusline_fragment(entry)
  if entry.phase == "idle" then
    return nil
  end
  local icon = entry.ok == false and "✘" or (entry.ok and "✔" or "…")
  return string.format("%s %s", icon, entry.message)
end

local function statusline_fragment(entry)
  if entry.phase == "idle" or entry.message == "" then
    return nil
  end
  local icon = entry.ok == false and "✘" or (entry.ok and "✔" or "…")
  return string.format("%s %s", icon, entry.message)
end

local function current_entry()
  local ordered = {
    { state.build, "running" },
    { state.configure, "running" },
    { state.tests, "running" },
    { state.build, "done" },
    { state.configure, "done" },
    { state.tests, "done" },
  }
  for _, spec in ipairs(ordered) do
    local entry, phase = spec[1], spec[2]
    if entry.phase == phase then
      return entry
    end
  end
  return nil
end

function M.refresh()
  local entry = current_entry()
  if not entry then
    reset_virtual_text()
    return
  end
  local fragment = statusline_fragment(entry)
  if fragment then
    set_virtual_text("[cmake] " .. fragment, entry.hl)
  else
    reset_virtual_text()
  end
end

local function update_configure(message, hl)
  state.configure.message = message
  state.configure.hl = hl
  local fragment = statusline_fragment(state.configure)
  if fragment then
    M.refresh()
  end
end

local function update_build(message, hl)
  state.build.message = message
  state.build.hl = hl
  local fragment = statusline_fragment(state.build)
  if fragment then
    M.refresh()
  end
end

function M.configure_started(description)
  cancel_timer(state.configure)
  state.configure.phase = "running"
  state.configure.ok = nil
  state.configure.started = uv.hrtime()
  state.configure.message = description or "configure"
  update_configure(state.configure.message .. " …", "DiagnosticHint")
  M.refresh()
end

function M.configure_finished(ok)
  cancel_timer(state.configure)
  state.configure.phase = "done"
  state.configure.ok = ok
  local suffix = ok and "done" or "failed"
  local elapsed = format_elapsed(state.configure.started)
  local message = string.format("configure %s%s", suffix, elapsed)
  update_configure(message, ok and "DiagnosticOk" or "DiagnosticError")
  state.configure.started = nil
  schedule_idle(state.configure, 3000)
  M.refresh()
end

function M.build_started(target)
  cancel_timer(state.build)
  state.build.phase = "running"
  state.build.ok = nil
  state.build.target = target
  state.build.started = uv.hrtime()
  local label = target and ("build " .. target) or "build"
  state.build.message = label
  update_build(label .. " …", "DiagnosticHint")
  M.refresh()
end

function M.build_dispatched(target)
  cancel_timer(state.build)
  state.build.phase = "done"
  state.build.ok = nil
  state.build.target = target
  state.build.started = nil
  local label = target and ("build " .. target .. " dispatched") or "build dispatched"
  update_build(label, "DiagnosticWarn")
  schedule_idle(state.build, 3000)
  M.refresh()
end

function M.build_finished(ok, extra)
  cancel_timer(state.build)
  state.build.phase = "done"
  state.build.ok = ok
  local label = state.build.target and ("build " .. state.build.target) or "build"
  local suffix = ok and "ok" or "failed"
  local elapsed = format_elapsed(state.build.started)
  local message = string.format("%s %s%s", label, suffix, elapsed)
  if extra then
    message = message .. " " .. extra
  end
  update_build(message, ok and "DiagnosticOk" or "DiagnosticError")
  state.build.started = nil
  schedule_idle(state.build, 3000)
  M.refresh()
end

function M.tests_started(label)
  cancel_timer(state.tests)
  state.tests.phase = "running"
  state.tests.ok = nil
  state.tests.started = uv.hrtime()
  local base = label or "tests"
  state.tests.message = base .. " …"
  state.tests.hl = "DiagnosticHint"
  M.refresh()
end

function M.tests_finished(ok, summary)
  cancel_timer(state.tests)
  state.tests.phase = "done"
  state.tests.ok = ok
  local elapsed = format_elapsed(state.tests.started)
  local message = string.format("tests %s%s", ok and "ok" or "failed", elapsed)
  if summary and summary ~= "" then
    message = message .. " " .. summary
  end
  state.tests.message = message
  state.tests.hl = ok and "DiagnosticOk" or "DiagnosticError"
  state.tests.started = nil
  schedule_idle(state.tests, 3000)
  M.refresh()
end

function M.statusline()
  local parts = {}
  local configure = statusline_fragment(state.configure)
  if configure then
    table.insert(parts, configure)
  end
  local build = statusline_fragment(state.build)
  if build then
    table.insert(parts, build)
  end
  local tests = statusline_fragment(state.tests)
  if tests then
    table.insert(parts, tests)
  end
  if #parts == 0 then
    return "[cmake] idle"
  end
  return "[cmake] " .. table.concat(parts, " | ")
end

return M
