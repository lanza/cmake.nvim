local ui = require("cmake.ui")
local compile_commands = require("cmake.compile_commands")
local status = require("cmake.status")
local test_runner = require("cmake.test_runner")
local diagnostics = require("cmake.diagnostics")

local M = {}

---@class CMakeTarget
---@field args string[]
---@field breakpoints table<string, {text: string, enabled: boolean}>
---@field current_target_file string
---@field current_target_relative string
---@field current_target_name string
---@field is_exec boolean

---@class PhonyTarget
---@field name string

---@class CMakeDirectory
---@field cmake_arguments string[]
---@field build_dir string
---@field source_dir string
---@field targets table<string, CMakeTarget>
---@field phony_targets table<string, PhonyTarget>
---@field current_target_file string?

---@class CMakeState
---@field template_file string
---@field cmake_tool "cmake"
---@field generator "Ninja" | "Unix Makefiles"
---@field build_command "ninja" | "make"
---@field extra_lit_args string
---@field cache_file_path string
---@field global_cache_object table<string, CMakeDirectory>
---@field dir_cache_object CMakeDirectory?
---@field current_target_cache_object CMakeTarget?

---@private
local function read_json_file(file_path)
  local file_contents = vim.fn.readfile(file_path)
  local json_string = table.concat(file_contents, "\n")
  assert(string.len(json_string) > 0, "JSON file " .. file_path .. " is empty")
  return vim.fn.json_decode(json_string)
end

---@private
local function is_absolute_path(path)
  return vim.startswith(path, "/")
end

---@private
local function save_build_tool(tool)
  vim.g.saved_cmake_build_tool = vim.g.cmake_build_tool
  vim.g.cmake_build_tool = tool or "vsplit"
end

---@private
local function restore_build_tool()
  vim.g.cmake_build_tool = vim.g.saved_cmake_build_tool
  vim.g.saved_cmake_build_tool = nil
end

---@private
function M.get_dco()
  return M.state.dir_cache_object
end

---@private
function M.get_ctco()
  return M.state.current_target_cache_object
end

---@private
function M.get_gco()
  return M.state.global_cache_object
end

---@private
function M.get_source_dir()
  return M.get_dco().source_dir
end

---@private
function M.get_build_dir()
  return M.get_dco().build_dir
end

---@private
function M.has_set_target()
  return M.get_ctco() ~= nil
end

---@private
function M.get_current_target_file()
  return M.get_ctco().current_target_file
end

---@private
function M.get_current_target_name()
  return M.get_ctco().current_target_name
end

---@private
function M.get_current_target_run_args()
  return M.get_ctco().args
end

---@private
function M.write_cache_file()
  local cache_file = M.state.global_cache_object
  local serial = vim.fn.json_encode(cache_file)
  local split = vim.fn.split(serial, "\n")
  vim.fn.writefile(split, M.state.cache_file_path)
end

---@private
function M.has_query_reply()
  local build_dir = M.get_build_dir()
  local codemodel_path = vim.env.PWD .. "/" .. build_dir .. ".cmake/api/v1/reply/"
  return #vim.fs.find(function(name, _)
    return name:match("codemodel*")
  end, { path = codemodel_path }) > 0
end

---@private
function M.ensure_built_current_target(completion)
  M.ensure_selected_target(function()
    M.perform_build(completion)
  end)
end

---@private
function M.perform_build(completion)
  assert(M.has_set_target(), "Shouldn't call _build_target_with_completion without a set target")
  local build_dir = M.get_build_dir()
  if not is_absolute_path(build_dir) then
    build_dir = vim.fn.getcwd() .. "/" .. build_dir
  end

  local target = M.get_current_target_name()
  status.build_started(target)

  if vim.g.cmake_build_tool == "vsplit" then
    local command = "cmake --build " .. M.get_build_dir() .. " --target " .. target
    ui.get_only_window()
    local capture = diagnostics.start_capture({
      target = target,
      build_dir = M.get_build_dir(),
    })
    vim.fn.termopen(command, {
      on_stdout = capture.stdout,
      on_stderr = capture.stderr,
      on_exit = function(job_id, exit_code, event)
        if capture.finish then
          capture.finish(exit_code)
        end
        status.build_finished(exit_code == 0)
        if completion then
          completion(job_id, exit_code, event)
        end
      end,
    })
  elseif vim.g.cmake_build_tool == "vim-dispatch" then
    vim.o.makeprg = M.state.build_command .. " -C " .. build_dir .. " " .. target
    --   " completion not honored
    vim.cmd.Make()
    status.build_dispatched(target)
  else
    print("g:cmake_build_tool value is invalid. (vsplit or vim-dispatch)")
    status.build_finished(false, "(invalid build tool)")
  end
end

---@private
function M.get_cmake_argument_string()
  local build_dir = M.get_build_dir()
  if vim.fn.isdirectory(build_dir .. "/.cmake/api/v1/query") == 0 then
    vim.fn.mkdir(build_dir .. "/.cmake/api/v1/query", "p")
  end
  if vim.fn.filereadable(build_dir .. "/.cmake/api/v1/query/codemodel-v2") == 0 then
    vim.fn.writefile({ " " }, build_dir .. "/.cmake/api/v1/query/codemodel-v2")
  end
  local arguments = {
    "-G",
    M.state.generator,
    "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
  }

  for _, arg in ipairs(M.get_cmake_args()) do
    table.insert(arguments, arg)
  end

  local found_cmake_build_type = false
  local found_source_dir_arg = false
  local found_build_dir_arg = false

  for _, arg in ipairs(M.get_cmake_args()) do
    if string.match(arg, "-DCMAKE_BUILD_TYPE=") then
      found_cmake_build_type = true
    elseif string.match(arg, "-S") then
      found_source_dir_arg = true
    elseif string.match(arg, "-B") then
      found_build_dir_arg = true
    elseif vim.fn.isdirectory(arg) == 1 then
      found_source_dir_arg = true
    end
  end

  if not found_cmake_build_type then
    table.insert(arguments, "-DCMAKE_BUILD_TYPE=Debug")
  end
  if not found_source_dir_arg then
    table.insert(arguments, "-S")
    table.insert(arguments, M.get_dco().source_dir)
  end
  if not found_build_dir_arg then
    table.insert(arguments, "-B")
    table.insert(arguments, M.get_build_dir())
  end

  return table.concat(arguments, " ")
end

---@private
function M.get_cmake_args()
  return M.get_dco().cmake_arguments
end

---@private
function M.get_breakpoints()
  return M.get_ctco().breakpoints
end

function M.enable_breakpoint(break_string)
  local breakpoints = M.get_breakpoints()
  breakpoints[break_string] = {
    text = break_string,
    enabled = true,
  }
  M.write_cache_file()
end

---@private
function M.toggle_breakpoint(break_string)
  local breakpoints = M.get_breakpoints()
  if vim.fn.has_key(breakpoints, break_string) == 1 then
    breakpoints[break_string].enabled = not breakpoints[break_string].enabled
  else
    breakpoints[break_string] = {
      text = break_string,
      enabled = true,
    }
  end
  M.write_cache_file()
end

---@private
function M.should_break_at_main()
  local path = vim.env.HOME .. "/.config/cmake.nvim/dont_break_at_main"
  return vim.fn.filereadable(path) == 0
end

---@private
function M.start_debugger(config, job_id, exit_code, event)
  if exit_code ~= 0 then
    return
  end

  local commands = {}

  if M.should_break_at_main() then
    table.insert(commands, config.main_breakpoint)
  end

  if config.debugger ~= "gdb" then
    local breakpoints = M.get_breakpoints()
    for _, breakpoint in pairs(breakpoints) do
      if breakpoint.enabled then
        table.insert(commands, "b " .. breakpoint.text)
      end
    end
  end
  table.insert(commands, "run")

  local init_file = "/tmp/cmake.nvim_debugger_init"
  local _ = vim.fn.writefile(commands, init_file)

  ui.close_last_window_if_open()
  ui.close_last_buffer_if_open()

  vim.cmd(config.command_builder(init_file, M.get_current_target_file(), M.get_current_target_run_args()))
end

---@private
function M.parse_codemodel_json()
  local build_dir = M.get_build_dir()
  local cmake_query_response_dir = build_dir .. "/.cmake/api/v1/reply/"
  local codemodel_file = vim.fn.globpath(cmake_query_response_dir, "codemodel*")

  assert(codemodel_file ~= nil, "Query reply should be set when calling parse_codemodel_json")

  local targets = read_json_file(codemodel_file).configurations[1].targets

  for _, target in pairs(targets) do
    local name = target.name
    local target_file_data = read_json_file(cmake_query_response_dir .. target.jsonFile)

    local artifacts = target_file_data.artifacts
    if artifacts then
      local relative_path = artifacts[1].path
      local is_exec = target_file_data.type == "EXECUTABLE"

      local filepath = M.state.dir_cache_object.build_dir .. "/" .. relative_path

      M.get_dco().targets[name] = {
        current_target_file = filepath,
        current_target_relative = relative_path,
        current_target_name = name,
        args = "",
        breakpoints = {},
        is_exec = is_exec,
        target_type = target_file_data.type,
      }
    else
      M.get_dco().phoney_targets[name] = {
        name = name,
      }
    end
  end

  return true
end

---@private
function M.configure_and_generate(completion)
  status.configure_started("configure")
  if vim.fn.filereadable(M.get_source_dir() .. "/CMakeLists.txt") == 0 then
    if vim.g.cmake_template_file ~= nil then
      vim.fn.filecopy(vim.g.cmake_template_file, M.get_source_dir() .. "/CMakeLists.txt")
    else
      print("Could not find a CMakeLists at directory " .. M.get_cmake_source_dir())
    end
  end

  local command = M.state.cmake_tool .. " " .. M.get_cmake_argument_string()
  ui.get_only_window()
  vim.fn.termopen(vim.fn.split(command), {
    on_exit = function(_, exit_code, _)
      if exit_code ~= 0 then
        print("CMake configuration/generation failed")
        status.configure_finished(false)
        return
      end
      status.configure_finished(true)
      compile_commands.auto_sync(M.get_build_dir(), M.get_source_dir())
      _ = completion and completion()
    end
  })
end

---@private
function M.ensure_generated(completion)
  if M.has_query_reply() then
    _ = completion and completion()
  else
    M.configure_and_generate(completion)
  end
end

---@private
function M.ensure_parsed(completion)
  if #M.get_dco().targets > 0 then
    _ = completion and completion()
  else
    M.ensure_generated(function()
      M.parse_codemodel_json()
      _ = completion and completion()
    end)
  end
end

---@private
function M.ensure_selected_target(completion)
  if M.has_set_target() then
    completion()
  else
    M.ensure_parsed(function()
      M.select_target(completion)
    end)
  end
end

---@private
function M.dump_current_target()
  local ctco = M.get_ctco()
  print("Current target set to " .. ctco.current_target_file .. " with args " .. ctco.args)
end

---@private
function M.set_current_target(target_name)
  assert(target_name ~= nil, "Invalid target to select_target")
  assert(target_name ~= "", "Invalid target to select_target")

  local dco = M.get_dco()
  dco.current_target_name = target_name
  M.state.current_target_cache_object = dco.targets[target_name]

  M.write_cache_file()
end

---@private
function M.get_buildable_targets()
  local names = {}
  for name, _ in pairs(M.get_dco().targets) do
    table.insert(names, name)
  end
  return names
end

---@private
function M.select_target(action)
  local names = M.get_buildable_targets()

  if #names == 1 then
    local target_name = names[1]
    M.set_current_target(target_name)
    M.dump_current_target()
    _ = action and action(target_name)
  else
    vim.o.makeprg = M.state.build_command
    vim.ui.select(names, { prompt = 'Select Target:' }, function(target_name)
      M.set_current_target(target_name)
      M.dump_current_target()
      _ = action and action(target_name)
    end)
  end
end

---@private
function M.get_executable_targets()
  local names = {}
  for _, target in ipairs(M.state.dir_cache_object.targets) do
    if target.is_exec then
      local name = target.name
      table.insert(names, name)
    end
  end
  return names
end

---@private
function M.select_executable_target()
  local names = M.get_executable_targets()

  if #names == 1 then
    M.set_current_target(names[1])
    M.dump_current_target()
  else
    vim.o.makeprg = M.state.build_command
    vim.ui.select(names, { prompt = 'Select Target:' }, function(target_name)
      M.set_current_target(target_name)
      M.dump_current_target()
    end)
  end
end

function M.cmake_build_all()
  M.ensure_parsed(function()
    if vim.g.cmake_build_tool == "vsplit" then
      local command = "cmake --build " .. M.get_build_dir()
      ui.get_only_window()
      vim.fn.termopen(command)
    elseif vim.g.cmake_build_tool == "vim-dispatch" then
      local cwd = vim.fn.getcwd()
      vim.o.makeprg = M.state.build_command .. " -C " .. cwd .. "/" .. M.get_build_dir()
    else
      print("vim.g.cmake_build_tool value is invalid (vsplit or vim-dispatch)")
    end
  end)
end

function M.cmake_pick_target()
  M.ensure_parsed(M.select_target)
end

function M.cmake_pick_executable_target()
  M.ensure_parsed(M.select_executable_target)
end

function M.cmake_open_cache_file()
  vim.cmd.edit(M.get_build_dir() .. "/CMakeCache.txt")
end

function M.cmake_set_cmake_args(cmake_args)
  M.get_dco().cmake_arguments = cmake_args
  M.write_cache_file()
end

function M.cmake_build_current_target(tool)
  save_build_tool(tool)

  M.ensure_built_current_target(function()
    restore_build_tool()
  end)
end

function M.cmake_toggle_file_line_breakpoint()
  local curpos = vim.fn.getcurpos()
  local line_number = curpos[2]

  local file_name = vim.fn.expand("#" .. vim.fn.bufnr() .. ":p")

  local break_string = file_name .. ":" .. line_number

  M.toggle_breakpoint(break_string)
end

function M.cmake_toggle_file_line_column_breakpoint()
  local curpos = vim.fn.getcurpos()
  local line_number = curpos[2]
  local column_number = curpos[3]

  local file_name = vim.fn.expand("#" .. vim.fn.bufnr() .. ":p")

  local break_string = file_name .. ":" .. line_number .. ":" .. column_number

  M.toggle_breakpoint(break_string)
end

function M.cmake_debug_current_target_gdb()
  save_build_tool()
  M.ensure_built_current_target(function(job_id, exit_code, event)
    restore_build_tool()
    M.start_debugger({
      debugger = "gdb",
      main_breakpoint = "b main",
      run_command = "r",
      command_builder = function(init_file, target_file, run_args)
        return "GdbStart gdb -q " .. init_file .. " --args " .. target_file .. " " .. run_args
      end,
    }, job_id, exit_code, event)
  end)
end

function M.cmake_debug_current_target_nvim_dap_lldb_vscode()
  save_build_tool()
  M.ensure_built_current_target(function(job_id, exit_code, event)
    restore_build_tool()
    M.start_debugger({
      debugger = "nvim_dap_lldb_vscode",
      main_breakpoint = "breakpoint set --name main",
      run_command = "run",
      command_builder = function(init_file, target_file, run_args)
        return "DebugLldb " .. target_file .. " --lldbinit " .. init_file .. " -- " .. run_args
      end,
    }, job_id, exit_code, event)
  end)
end

function M.cmake_debug_current_target_lldb()
  save_build_tool()
  M.ensure_built_current_target(function(job_id, exit_code, event)
    restore_build_tool()
    M.start_debugger({
      debugger = "lldb",
      main_breakpoint = "breakpoint set --name main",
      run_command = "run",
      command_builder = function(init_file, target_file, run_args)
        return "GdbStartLLDB lldb " .. target_file .. " -s " .. init_file .. " -- " .. run_args
      end,
    }, job_id, exit_code, event)
  end)
end

function M.cmake_toggle_break_at_main()
  local path = vim.env.HOME .. "/.config/cmake.nvim/dont_break_at_main"
  if vim.fn.filereadable(path) == 1 then
    vim.fn.delete(path)
    return
  end

  local config = vim.env.HOME .. "/.config"
  if vim.fn.isdirectory(config) == 0 then
    vim.fn.mkdir(config)
  end
  local cmake_nvim = config .. "/cmake.nvim"
  if vim.fn.isdirectory(cmake_nvim) == 0 then
    vim.fn.mkdir(cmake_nvim)
  end
  vim.fn.writefile({ " " }, path)
end

function M.cmake_list_breakpoints()
  local breakpoint_list = {}
  local breakpoints = M.get_breakpoints()
  print("Enabled:")
  for _, breakpoint in pairs(breakpoints) do
    if breakpoint.enabled then
      print("    " .. breakpoint.text)
    end
  end
  print("Disabled:")
  for _, breakpoint in pairs(breakpoints) do
    if not breakpoint.enabled then
      print("    " .. breakpoint.text)
    end
  end

  print(table.concat(breakpoint_list, "\n"))
end

function M.cmake_run_current_target()
  save_build_tool()
  M.ensure_built_current_target(function(_, exit_code, _)
    restore_build_tool()
    if exit_code ~= 0 then
      print("Build failed, not running")
      return
    end
    ui.get_only_window()
    local target_file = M.get_current_target_file()
    vim.fn.jobstart(target_file .. " " .. M.get_current_target_run_args(), {
      term = true,
    })
  end)
end

function M.cmake_configure_and_generate()
  M.configure_and_generate()
end

function M.cmake_sync_compile_commands()
  compile_commands.sync(M.get_build_dir(), M.get_source_dir())
end

function M.cmake_run_tests()
  M.ensure_generated(function()
    test_runner.run_all({
      build_dir = M.get_build_dir(),
    })
  end)
end

function M.cmake_rerun_failed_tests()
  M.ensure_generated(function()
    test_runner.rerun_failed({
      build_dir = M.get_build_dir(),
    })
  end)
end

function M.cmake_show_diagnostics()
  diagnostics.show()
end

function M.cmake_edit_run_args()
  M.ensure_selected_target(function()
    vim.ui.input({
      prompt = "Run Arguments: ",
      default = M.get_current_target_run_args(),
    }, function(new_run_args)
      if new_run_args == nil then
        return
      end
      M.get_ctco().args = new_run_args
      M.dump_current_target()
      M.write_cache_file()
    end)
  end)
end

function M.cmake_edit_build_dir()
  vim.ui.input({
    prompt = "Build Directory: ",
    default = M.get_build_dir(),
  }, function(new_build_dir)
    if new_build_dir == nil then
      return
    end
    M.get_dco().build_dir = new_build_dir
    M.write_cache_file()
  end)
end

function M.cmake_edit_source_dir()
  vim.ui.input({
    prompt = "Source Directory: ",
    default = M.get_dco().source_dir,
  }, function(new_source_dir)
    if new_source_dir == nil then
      return
    end
    M.get_dco().source_dir = new_source_dir
    M.write_cache_file()
  end)
end

function M.cmake_edit_cmake_args()
  vim.ui.input({
    prompt = "CMake Arguments: ",
    default = table.concat(M.get_cmake_args(), " "),
  }, function(new_cmake_args)
    if new_cmake_args == nil then
      return
    end
    M.get_dco().cmake_arguments = vim.fn.split(new_cmake_args, " ")
    M.write_cache_file()
  end)
end

function M.cmake_load()
  -- do nothing ... just enables my new build dir grep command to work
end

function M.cmake_set_current_target_run_args(run_args)
  M.ensure_selected_target(function()
    M.get_ctco().args = run_args
    M.write_cache_file()
    M.dump_current_target()
  end)
end

function M.cmake_create_file(args)
  print("create_cmake_file NYI")
  -- if len(a:000) > 2 || len(a:000) == 0
  --   echo 'CMakeCreateFile requires 1 or 2 arguments: e.g. Directory File for `Directory/File.{cpp,h}`'
  --   return
  -- endif

  -- if len(a:000) == 2
  --   let l:header = "include/" . a:1 . "/" . a:2 . ".h"
  --   let l:source = "lib/" . a:1 . "/" . a:2 . ".cpp"
  --   silent exec "!touch " . l:header
  --   silent exec "!touch " . l:source
  -- elseif len(a:000) == 1
  --   let l:header = "include/" . a:1 . ".h"
  --   let l:source = "lib/" . a:1 . ".cpp"
  --   silent exec "!touch " . l:header
  --   silent exec "!touch " . l:source
  -- end
end

function M.cmake_clean()
  local command = "cmake --build " .. M.get_build_dir() .. " --target clean"
  vim.fn.vsplit()
  vim.fn.wincmd("L")
  vim.fn.terminal(command)
end

function M.cmake_update_build_dir(build_dir)
  M.get_dco().build_dir = build_dir
  M.write_cache_file()
end

function M.cmake_update_source_dir(source_dir)
  M.get_dco().source_dir = source_dir
  M.write_cache_file()
end

function M.cmake_run_lit_on_file()
  local full_path = vim.fn.expand("%:p")
  local lit_path = "llvm-lit"
  local bin_lit_path = M.get_build_dir() .. "/bin/llvm-lit"
  if vim.fn.filereadable(bin_lit_path) == 1 then
    lit_path = bin_lit_path
  end
  ui.get_only_window()
  vim.fn.termopen({ lit_path, M.state.extra_lit_args, full_path })
end

function M.initialize_cache_file()
  local cwd = vim.fn.getcwd()

  local template_file = vim.g.cmake_template_file or vim.fn.expand(":p:h:h" .. "/CMakeLists.txt")
  local default_build_dir = vim.g.cmake_default_build_dir or "build"
  local extra_lit_args = vim.g.cmake_extra_lit_args or "-a"
  local cache_file_path = vim.g.cmake_cache_file_path or vim.env.HOME .. "/.cmake.nvim.json"

  local global_cache_object = (function()
    if vim.fn.filereadable(cache_file_path) == 0 then
      vim.fn.writefile({ "{}" }, cache_file_path)
    end
    return read_json_file(cache_file_path)
  end)()

  if global_cache_object[cwd] == nil then
    global_cache_object[cwd] = {
      cmake_arguments = {},
      build_dir = default_build_dir,
      source_dir = ".",
      targets = {},
      phoney_targets = {},
      current_target = nil,
    }
  end
  local dir_cache_object = global_cache_object[cwd]

  local current_target_cache_object = dir_cache_object.targets[dir_cache_object.current_target]

  M.state = {
    template_file = template_file,
    cmake_tool = "cmake",
    generator = "Ninja",
    build_command = "ninja",
    extra_lit_args = extra_lit_args,
    cache_file_path = cache_file_path,
    global_cache_object = global_cache_object,
    dir_cache_object = dir_cache_object,
    current_target_cache_object = current_target_cache_object,
  }

  local ct = M.state.dir_cache_object.current_target
  M.state.current_target_cache_object = M.state.dir_cache_object.targets[ct]
end

function M.setup(opts)
  ui.setup(opts)

  if not vim.g.cmake_build_tool then
    vim.g.cmake_build_tool = 'vsplit'
  end

  M.initialize_cache_file()
end

vim.api.nvim_create_user_command("CMakeOpenCacheFile", M.cmake_open_cache_file, { nargs = 0, })

vim.api.nvim_create_user_command("CMakeSetCMakeArgs", function(args) M.cmake_set_cmake_args(args.args) end,
  { nargs = "*", })
vim.api.nvim_create_user_command("CMakeSetBuildDir", function(args) M.cmake_update_build_dir(args.args) end,
  { nargs = 1, complete = "dir" })
vim.api.nvim_create_user_command("CMakeSetSourceDir", function(args) M.cmake_update_source_dir(args.args) end,
  { nargs = 1, complete = "dir" })

vim.api.nvim_create_user_command("CMakePickTarget", M.cmake_pick_target, { nargs = 0, })
vim.api.nvim_create_user_command("CMakePickExecutableTarget", M.cmake_pick_executable_target, { nargs = 0, })
vim.api.nvim_create_user_command("CMakeRunCurrentTarget", M.cmake_run_current_target, { nargs = 0, })
vim.api.nvim_create_user_command("CMakeSetCurrentTargetRunArgs",
  function(args) M.cmake_set_current_target_run_args(args.args) end, { nargs = "*", })
vim.api.nvim_create_user_command("CMakeBuildCurrentTarget", function(args) M.cmake_build_current_target(args.args) end,
  { nargs = "?", complete = function() return { "vsplit", "vim-dispatch", "Makeshift", "make", "job" } end })

vim.api.nvim_create_user_command("CMakeClean", M.cmake_clean, { nargs = 0, })
vim.api.nvim_create_user_command("CMakeBuildAll", M.cmake_build_all, { nargs = 0, })
vim.api.nvim_create_user_command("CMakeRunTests", M.cmake_run_tests, { nargs = 0, })
vim.api.nvim_create_user_command("CMakeRerunFailedTests", M.cmake_rerun_failed_tests, { nargs = 0, })
vim.api.nvim_create_user_command("CMakeShowDiagnostics", M.cmake_show_diagnostics, { nargs = 0, })

vim.api.nvim_create_user_command("CMakeCreateFile", M.cmake_create_file, { nargs = 1 })
vim.api.nvim_create_user_command("CMakeCloseWindow", ui.cmake_close_windows, { nargs = 0, })
vim.api.nvim_create_user_command("CMakeRunLitOnFile", M.cmake_run_lit_on_file, { nargs = 0, })
vim.api.nvim_create_user_command("CMakeLoad", M.cmake_load, { nargs = 0, })

vim.api.nvim_create_user_command("CMakeConfigureAndGenerate", M.cmake_configure_and_generate, { nargs = 0, })

vim.api.nvim_create_user_command("CMakeToggleFileLineColumnBreakpoint", M.cmake_toggle_file_line_column_breakpoint,
  { nargs = 0, })
vim.api.nvim_create_user_command("CMakeToggleFileLineBreakpoint", M.cmake_toggle_file_line_breakpoint, { nargs = 0, })

vim.api.nvim_create_user_command("CMakeListBreakpoints", M.cmake_list_breakpoints, { nargs = 0, })
vim.api.nvim_create_user_command("CMakeToggleBreakAtMain", M.cmake_toggle_break_at_main, { nargs = 0, })

vim.api.nvim_create_user_command("CMakeDebugWithNvimLLDB", M.cmake_debug_current_target_lldb, { nargs = 0, })
vim.api.nvim_create_user_command("CMakeDebugWithNvimGDB", M.cmake_debug_current_target_gdb, { nargs = 0, })
vim.api.nvim_create_user_command("CMakeDebugWithNvimDapLLDBVSCode", M.cmake_debug_current_target_nvim_dap_lldb_vscode,
  { nargs = 0, })
vim.api.nvim_create_user_command("CMakeSyncCompileCommands", M.cmake_sync_compile_commands, { nargs = 0, })


function M.statusline()
  return status.statusline()
end


return M
