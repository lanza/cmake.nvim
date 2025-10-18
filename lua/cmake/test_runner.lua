local ui = require("cmake.ui")
local status = require("cmake.status")

local M = {}

local function is_absolute(path)
  return type(path) == "string" and vim.startswith(path, "/")
end

local function to_absolute(path)
  if not path or path == "" then
    return vim.fn.getcwd()
  end
  if is_absolute(path) then
    return path
  end
  return vim.fn.getcwd() .. "/" .. path
end

local function extend_args(destination, extra)
  if not extra then
    return
  end
  if type(extra) == "table" then
    for _, value in ipairs(extra) do
      table.insert(destination, value)
    end
    return
  end
  if type(extra) == "string" and extra ~= "" then
    for _, value in ipairs(vim.fn.split(extra)) do
      table.insert(destination, value)
    end
  end
end

local function build_command(opts)
  local command = { vim.g.cmake_ctest_executable or "ctest", "--output-on-failure" }
  extend_args(command, vim.g.cmake_ctest_args)
  extend_args(command, opts and opts.args)
  if opts and opts.rerun_failed then
    table.insert(command, "--rerun-failed")
  end
  return command
end

local function collect(accumulator, data)
  for _, line in ipairs(data or {}) do
    if line and line ~= "" then
      table.insert(accumulator, line)
    end
  end
end

local function parse_results(lines)
  local map = {}
  local stats = nil

  for _, line in ipairs(lines) do
    local passed, failed, total = line:match("(%d+)%s+tests passed,%s+(%d+)%s+tests failed out of%s+(%d+)")
    if passed then
      stats = {
        passed = tonumber(passed),
        failed = tonumber(failed),
        total = tonumber(total),
        line = line,
      }
    end

    local id, name, outcome =
      line:match("^%s*%d+/%d+%s+Test #%s*(%d+):%s*(.-)%s+%.+%*%*%*(%w+)")
    if not id then
      id, name, outcome = line:match("^%s*Test #%s*(%d+):%s*(.-)%s+%.+%*%*%*(%w+)")
    end
    if id and name then
      local entry = map[id] or {}
      entry.id = tonumber(id)
      entry.name = vim.trim(name)
      entry.status = outcome
      map[id] = entry
    end
  end

  local in_summary = false
  for _, line in ipairs(lines) do
    if line:match("^%s*The following tests FAILED:") then
      in_summary = true
    elseif in_summary then
      if line:match("^%s*$") then
        in_summary = false
      else
        local id, name, reason = line:match("^%s*(%d+)%s*%- %s*(.-)%s*%((.+)%)")
        if id and name then
          local entry = map[id] or {}
          entry.id = tonumber(id)
          entry.name = entry.name or vim.trim(name)
          entry.reason = reason
          map[id] = entry
        end
      end
    end
  end

  local results = {}
  for _, entry in pairs(map) do
    local status_string = entry.status and entry.status:lower() or nil
    local reason_string = entry.reason and entry.reason:lower() or nil
    if status_string and status_string ~= "passed" then
      table.insert(results, entry)
    elseif reason_string and reason_string ~= "passed" then
      entry.status = entry.reason
      table.insert(results, entry)
    end
  end

  table.sort(results, function(a, b)
    if a.id and b.id and a.id ~= b.id then
      return a.id < b.id
    end
    return (a.name or "") < (b.name or "")
  end)

  return results, stats
end

local function summary_text(stats, exit_code)
  if stats and stats.total then
    local failed = stats.failed or 0
    local total = stats.total or 0
    return string.format("%d/%d failed", failed, total)
  end
  if exit_code == 0 then
    return "all passed"
  end
  return string.format("exit %d", exit_code)
end

local function quickfix_items(results, stderr_lines)
  local items = {}
  for _, entry in ipairs(results) do
    local parts = { entry.name or "unknown test" }
    if entry.status then
      table.insert(parts, entry.status)
    end
    if entry.reason and entry.reason ~= entry.status then
      table.insert(parts, entry.reason)
    end
    table.insert(items, {
      filename = entry.name or "",
      lnum = 1,
      col = 1,
      text = table.concat(parts, " - "),
      type = "E",
    })
  end
  if #items == 0 then
    for _, line in ipairs(stderr_lines or {}) do
      if line ~= "" then
        table.insert(items, {
          filename = "",
          lnum = 1,
          col = 1,
          text = line,
          type = "E",
        })
      end
    end
  end
  return items
end

local function update_quickfix(items)
  if #items == 0 then
    vim.fn.setqflist({}, "r", { title = "CMake Tests" })
    return
  end
  vim.fn.setqflist({}, "r", {
    title = "CMake Tests",
    items = items,
  })
  vim.cmd("copen")
end

local function notify(message, level)
  vim.notify("cmake.nvim: " .. message, level or vim.log.levels.INFO)
end

local function start_ctest(opts)
  local build_dir = to_absolute(opts.build_dir)
  local command = build_command(opts)

  if vim.fn.isdirectory(build_dir) == 0 then
    status.tests_finished(false, "missing build dir")
    notify("Test build directory not found: " .. build_dir, vim.log.levels.ERROR)
    return
  end

  ui.get_only_window()

  status.tests_started(opts.label or "tests")

  local stdout_lines = {}
  local stderr_lines = {}

  local job_id = vim.fn.termopen(command, {
    cwd = build_dir,
    on_stdout = function(_, data, _)
      collect(stdout_lines, data)
    end,
    on_stderr = function(_, data, _)
      collect(stderr_lines, data)
    end,
    on_exit = function(_, code, _)
      vim.schedule(function()
        local results, stats = parse_results(stdout_lines)
        local items = quickfix_items(results, stderr_lines)
        update_quickfix(items)
        local summary = summary_text(stats, code)
        local ok = code == 0
        status.tests_finished(ok, summary)
        if ok then
          notify("Tests passed: " .. summary, vim.log.levels.INFO)
        else
          notify("Tests failed: " .. summary, vim.log.levels.ERROR)
        end
        if opts.on_complete then
          opts.on_complete({
            exit_code = code,
            results = results,
            stats = stats,
            stdout = stdout_lines,
            stderr = stderr_lines,
          })
        end
      end)
    end,
  })

  if job_id <= 0 then
    status.tests_finished(false, "spawn failed")
    notify("Failed to start ctest command", vim.log.levels.ERROR)
  end
end

function M.run_all(opts)
  opts = opts or {}
  opts.label = opts.label or "tests"
  start_ctest(opts)
end

function M.rerun_failed(opts)
  opts = opts or {}
  opts.label = opts.label or "rerun failed"
  opts.rerun_failed = true
  start_ctest(opts)
end

return M
