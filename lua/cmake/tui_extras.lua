local cmake = require("cmake")

local M = {}

local state = {
  filter_key = "all",
}

local filter_order = { "all", "executables", "libraries", "tests" }

local filters = {
  all = {
    label = "All targets",
    predicate = function(_)
      return true
    end,
  },
  executables = {
    label = "Executables",
    predicate = function(info)
      return info.kind == "executables"
    end,
  },
  libraries = {
    label = "Libraries",
    predicate = function(info)
      return info.kind == "libraries"
    end,
  },
  tests = {
    label = "Tests",
    predicate = function(info)
      return info.kind == "tests"
    end,
  },
}

local badges = {
  executables = "[EXE]",
  libraries = "[LIB]",
  tests = "[TST]",
  other = "[OTH]",
}

local function to_upper(str)
  return string.upper(str or "")
end

local function target_kind(target)
  local target_type = to_upper(target.target_type or (target.is_exec and "EXECUTABLE"))
  local name = target.current_target_name or target.name or ""
  if target.is_exec then
    return "executables", target_type
  end
  if target_type:find("LIBRARY", 1, true) then
    return "libraries", target_type
  end
  if target_type == "UTILITY" or target_type == "TEST" then
    return "tests", target_type
  end
  if string.match(name:lower(), "test") then
    return "tests", target_type ~= "" and target_type or "UNKNOWN"
  end
  return "other", target_type ~= "" and target_type or "UNKNOWN"
end

local function classify_target(target)
  local kind, target_type = target_kind(target)
  return {
    kind = kind,
    target_type = target_type,
    badge = badges[kind] or badges.other,
  }
end

function M.reset()
  state.filter_key = "all"
end

function M.cycle_filter(direction)
  direction = direction or 1
  local current_index = 1
  for idx, key in ipairs(filter_order) do
    if key == state.filter_key then
      current_index = idx
      break
    end
  end
  local next_index = ((current_index - 1 + direction) % #filter_order) + 1
  state.filter_key = filter_order[next_index]
  return state.filter_key
end

function M.set_filter(key)
  if filters[key] then
    state.filter_key = key
  end
  return state.filter_key
end

function M.get_filter()
  return state.filter_key
end

function M.get_filter_label()
  return filters[state.filter_key].label
end

local function sorted_target_names(targets)
  local names = {}
  local predicate = filters[state.filter_key].predicate
  for name, target in pairs(targets) do
    if type(target) == "table" and target.current_target_name then
      if predicate(classify_target(target)) then
        table.insert(names, name)
      end
    end
  end
  table.sort(names)
  return names
end

local function detail_lines(target, info)
  local lines = {}
  table.insert(lines, "  type: " .. (info.target_type or "UNKNOWN"))
  table.insert(lines, "  relative: " .. tostring(target.current_target_relative or ""))
  table.insert(lines, "  file: " .. tostring(target.current_target_file or ""))
  table.insert(lines, "  kind: " .. info.kind)
  if target.args then
    local args = target.args
    if type(args) == "table" then
      args = table.concat(args, " ")
    end
    if args ~= "" then
      table.insert(lines, "  args: " .. args)
    end
  end
  if target.breakpoints and next(target.breakpoints) then
    table.insert(lines, "  breakpoints:")
    for bp, info_bp in pairs(target.breakpoints) do
      local status = info_bp.enabled and "enabled" or "disabled"
      table.insert(lines, "    " .. tostring(bp) .. ": " .. tostring(info_bp.text) .. " (" .. status .. ")")
    end
  end
  return lines
end

function M.render_lines(expanded_map)
  local targets = {}
  if cmake.state and cmake.state.dir_cache_object and cmake.state.dir_cache_object.targets then
    targets = cmake.state.dir_cache_object.targets
  end

  local lines = {}
  local label = M.get_filter_label()
  table.insert(lines, "Filter: " .. label .. " (f next, a all, e exec, l libs, t tests)")
  table.insert(lines, "Actions: <CR> expand  b build  r run  d debug  q close")

  local names = sorted_target_names(targets)
  if #names == 0 then
    table.insert(lines, "  No targets match the current filter.")
    return lines
  end

  for _, name in ipairs(names) do
    local target = targets[name]
    local info = classify_target(target)
    local expanded = expanded_map and expanded_map[name]
    local prefix = expanded and "▼" or "▶"
    table.insert(lines, string.format("%s %s %s", prefix, info.badge, name))
    if expanded then
      for _, detail in ipairs(detail_lines(target, info)) do
        table.insert(lines, detail)
      end
    end
  end

  return lines
end

function M.extract_target_name(line)
  return line:match("^%S+ %[[^%]]+%]%s+(.+)$")
end

local function lookup_target(name)
  if not (cmake.state and cmake.state.dir_cache_object and cmake.state.dir_cache_object.targets) then
    return nil
  end
  return cmake.state.dir_cache_object.targets[name]
end

local function set_current_target(name)
  if not cmake.set_current_target then
    print("cmake.nvim: unable to set current target programmatically")
    return false
  end
  cmake.set_current_target(name)
  return true
end

local function ensure_executable(target)
  if target.is_exec then
    return true
  end
  print("cmake.nvim: target is not executable")
  return false
end

local debug_map = {
  gdb = function()
    cmake.cmake_debug_current_target_gdb()
  end,
  lldb = function()
    cmake.cmake_debug_current_target_lldb()
  end,
  dap = function()
    if cmake.cmake_debug_current_target_nvim_dap_lldb_vscode then
      cmake.cmake_debug_current_target_nvim_dap_lldb_vscode()
    else
      cmake.cmake_debug_current_target_lldb()
    end
  end,
}

local function pick_debugger()
  local preferred = vim.g.cmake_default_debugger or "gdb"
  return debug_map[preferred] or debug_map.gdb
end

local function run_build()
  cmake.cmake_build_current_target()
end

local function run_target()
  cmake.cmake_run_current_target()
end

function M.run_action(action, name)
  local target = lookup_target(name)
  if not target then
    print("cmake.nvim: no target named " .. name)
    return false
  end
  if not set_current_target(name) then
    return false
  end

  if action == "build" then
    run_build()
    return true
  elseif action == "run" then
    if not ensure_executable(target) then
      return false
    end
    run_target()
    return true
  elseif action == "debug" then
    if not ensure_executable(target) then
      return false
    end
    pick_debugger()()
    return true
  end

  print("cmake.nvim: unknown action " .. action)
  return false
end

return M
