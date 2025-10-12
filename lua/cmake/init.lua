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
---@field debugger "lldb" | "gdb" | "nvim_dap_lldb_vscode"
---@field extra_lit_args string
---@field cache_file_path string
---@field global_cache_object table<string, CMakeDirectory>
---@field dir_cache_object CMakeDirectory?
---@field current_target_cache_object CMakeTarget?

function M.get_dco()
  return M.state.dir_cache_object
end

function M.get_ctco()
  return M.state.current_target_cache_object
end

function M.initialize_cache_file()
  local cwd = vim.fn.getcwd()

  local template_file = vim.g.cmake_template_file or vim.fn.expand(":p:h:h" .. "/CMakeLists.txt")
  local default_build_dir = vim.g.cmake_default_build_dir or "build"
  local extra_lit_args = vim.g.cmake_extra_lit_args or "-a"
  local debugger = vim.g.vim_cmake_debugger or "lldb"
  local cache_file_path = vim.g.cmake_cache_file_path or vim.env.HOME .. "/.vim_cmake.json"

  local global_cache_object = (function()
    if vim.fn.filereadable(cache_file_path) == 0 then
      vim.fn.writefile({ "{}" }, cache_file_path)
    end
    local file_contents = vim.fn.readfile(cache_file_path) or ""
    local json_string = table.concat(file_contents, "\n")
    return vim.fn.json_decode(json_string)
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
    debugger = debugger,
    extra_lit_args = extra_lit_args,
    cache_file_path = cache_file_path,
    global_cache_object = global_cache_object,
    dir_cache_object = dir_cache_object,
    current_target_cache_object = current_target_cache_object,
  }

  local ct = M.state.dir_cache_object.current_target
  M.state.current_target_cache_object = M.state.dir_cache_object.targets[ct]
end

function M.get_run_args()
  return M.get_ctco().args
end

function M.has_set_target()
  return M.state.current_target_cache_object ~= nil
end

function M.get_current_target_name()
  return M.state.dir_cache_object.current_target
end

function M.get_build_dir()
  return M.state.dir_cache_object.build_dir
end

local function is_absolute_path(path)
  return vim.startswith(path, "/")
end

function M.check_if_window_is_alive(win)
  return vim.fn.index(vim.api.nvim_list_wins(), win) > -1
end

function M.close_last_window_if_open()
  if M.check_if_window_is_alive(vim.g.cmake_last_window) then
    vim.api.nvim_win_close(vim.g.cmake_last_window, true)
  end
end

function M.check_if_buffer_is_alive(buf)
  return vim.fn.index(vim.api.nvim_list_bufs(), buf) > -1
end

function M.close_last_buffer_if_open()
  if M.check_if_buffer_is_alive(vim.g.cmake_last_buffer) then
    vim.api.nvim_buf_delete(vim.g.cmake_last_buffer, { force = true })
  end
end

function M.get_only_window()
  M.close_last_window_if_open()
  M.close_last_buffer_if_open()
  vim.cmd.vsplit()
  vim.cmd.wincmd("L")
  vim.cmd.enew()
  vim.g.cmake_last_window = vim.api.nvim_get_current_win()
  vim.g.cmake_last_buffer = vim.api.nvim_get_current_buf()
end

function M.cmake_set_current_target_run_args(run_args)
  if M.get_current_target_name() == nil then
    M.cmake_get_target_and_run_action(M.update_target)
    return
  end
  M.set_ctco("args", run_args)
  M.write_cache_file()
  M.dump_current_target()
end

function M._update_target_and_build(target_name)
  M.select_target(target_name)
  M._build_target_with_completion(target_name)
end

function M.cmake_build_current_target_with_completion(completion)
  M.parse_codemodel_json_with_completion(function()
    M._build_target_with_completion(M.get_current_target_name(), completion)
  end)
end

function M.get_buildable_targets()
  local names = {}
  for name, _ in pairs(M.state.dir_cache_object.targets) do
    table.insert(names, name)
  end
  return names
end

function M.ensure_cmakelists_exists()
  local source_dir = M.get_source_dir()
  if vim.fn.filereadable(source_dir .. "/CMakeLists.txt") == 0 then
    if vim.g.cmake_template_file ~= nil then
      vim.cmd.system("cp " .. vim.g.cmake_template_file .. " " .. source_dir .. "/CMakeLists.txt")
    else
      print("Could not find a CMakeLists at directory " .. source_dir)
      return
    end
  end
end

function M.has_query_reply()
  local build_dir = M.get_build_dir()
  return #vim.fn.globpath(vim.fn.getcwd() .. "/" .. build_dir .. "/.cmake/api/v1/reply/", "codemodel*") > 0
end

function M.cmake_build_current_target(tool)
  local previous_build_tool = vim.g.vim_cmake_build_tool
  if tool ~= nil and tool ~= "" then
    vim.g.vim_cmake_build_tool = tool
  end

  -- build
  if M.has_query_reply() and M.has_set_target() then
    M.build_target(M.get_current_target_name())
    return
  end

  local parse_select_target_and_build = function()
    M.parse_codemodel_json()

    local names = M.get_buildable_targets()

    if #names == 0 then
      print("No buildable targets found")
      return
    end

    if #names == 1 then
      M.select_target(names[1])
      M.build_target(M.get_current_target_name())
    else
      vim.o.makeprg = M.state.build_command
      vim.ui.select(names, { prompt = 'Select Target:' }, function(target_name)
        M.select_target(target_name)
        M.build_target(M.get_current_target_name())
      end)
    end
  end

  -- parse, select, build
  if M.has_query_reply() then
    parse_select_target_and_build()
    vim.g.vim_cmake_build_tool = previous_build_tool
    return
  end

  -- if we haven't generated, do we at least have a CMakeLists.txt?
  M.ensure_cmakelists_exists()

  -- configure, generate, parse, select, build
  local command = M.state.cmake_tool .. " " .. M.get_cmake_argument_string()
  print(command)
  M.get_only_window()
  vim.fn.termopen(vim.fn.split(command), {
    on_exit =
        function(job_id, return_code, event_type)
          if return_code == 0 then
            parse_select_target_and_build()
          else
            print("CMake configuration failed, cannot build target")
          end
          vim.g.vim_cmake_build_tool = previous_build_tool
        end
  })
end

function M.build_target(target)
  assert(M.has_query_reply(), "Shouldn't call build_target without a query reply")
  assert(M.has_set_target(), "Shouldn't call build_target without a set target")
  M._build_target_with_completion(target, function() end)
end

function M._build_target_with_completion(target, completion)
  assert(M.has_set_target(), "Shouldn't call _build_target_with_completion without a set target")
  local build_dir = M.get_build_dir()
  if not is_absolute_path(build_dir) then
    build_dir = vim.fn.getcwd() .. "/" .. build_dir
  end

  if vim.g.vim_cmake_build_tool == "vsplit" then
    local command = "cmake --build " .. M.get_build_dir() .. " --target " .. target
    M.get_only_window()
    vim.fn.termopen(command, { on_exit = completion })
  elseif vim.g.vim_cmake_build_tool == "vim-dispatch" then
    vim.o.makeprg = M.state.build_command .. " -C " .. build_dir .. " " .. target
    --   " completion not honored
    vim.cmd.Make()
  elseif vim.g.vim_cmake_build_tool == "Makeshift" then
    print("Makeshift NYI")
    --   let &makeprg = s:get_state("build_command") . ' ' . a:target
    --   let b:makeshift_root = l:directory
    --   " completion not honored
    --   MakeshiftBuild
  elseif vim.g.vim_cmake_build_tool == "make" then
    --   let &makeprg = s:get_state("build_command") . ' -C ' . l:directory . ' ' . a:target
    --   " completion not honored
    --   make
  elseif vim.g.vim_cmake_build_tool == "job" then
    --   let l:cmd = s:get_state("build_command") . ' -C ' . l:directory . ' ' . a:target
    --   call jobstart(cmd, {"on_exit": a:completion })
  else
    print("g:vim_cmake_build_tool value is invalid. Please set it to either vsplit, Makeshift, vim-dispatch or make.")
  end
end

function M.configure_and_generate()
  M.configure_and_generate_with_completion(function() end)
end

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

function M.toggle_file_line_breakpoint()
  local curpos = vim.fn.getcurpos()
  local line_number = curpos[2]

  local file_name = vim.fn.expand("#" .. vim.fn.bufnr() .. ":p")

  local break_string = file_name .. ":" .. line_number

  M.toggle_breakpoint(break_string)
end

function M.toggle_file_line_column_breakpoint()
  local curpos = vim.fn.getcurpos()
  local line_number = curpos[2]
  local column_number = curpos[3]

  local file_name = vim.fn.expand("#" .. vim.fn.bufnr() .. ":p")

  local break_string = file_name .. ":" .. line_number .. ":" .. column_number

  M.toggle_breakpoint(break_string)
end

function M.get_breakpoints()
  return M.get_ctco().breakpoints
end

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

function M.should_break_at_main()
  local path = vim.env.HOME .. "/.config/vim_cmake/dont_break_at_main"
  return vim.fn.filereadable(path) == 0
end

function M.cmake_debug_current_target()
  M.parse_codemodel_json_with_completion(M._do_debug_current_target)
end

function M.cmake_debug_current_target_lldb()
  M.set_state("debugger", "lldb")
  M.cmake_debug_current_target()
end

function M.cmake_debug_current_target_gdb()
  M.set_state("debugger", "gdb")
  M.cmake_debug_current_target()
end

function M.cmake_debug_current_target_nvim_dap_lldb_vscode()
  M.set_state("debugger", "nvim_dap_lldb_vscode")
  M.cmake_debug_current_target()
end

function M.start_lldb(job_id, exit_code, event)
  if exit_code ~= 0 then
    return
  end

  local commands = {}

  if M.should_break_at_main() then
    table.insert(commands, "breakpoint set --name main")
  end

  local breakpoints = M.get_breakpoints()
  for _, breakpoint in pairs(breakpoints) do
    if breakpoint.enabled then
      table.insert(commands, "b " .. breakpoint.text)
    end
  end

  table.insert(commands, "run")

  local init_file = "/tmp/lldb_init_vim_cmake"
  local _ = vim.fn.writefile(commands, init_file)

  M.close_last_window_if_open()
  M.close_last_buffer_if_open()

  local lldb_init_arg = " -s " .. init_file

  vim.cmd("GdbStartLLDB lldb " ..
    M.get_current_target_name() .. lldb_init_arg .. " " .. " -- " .. M.get_run_args())
end

function M.start_gdb(job_id, exit_code, event)
  if exit_code ~= 0 then
    return
  end

  local commands = {}

  if M.should_break_at_main() then
    table.insert(commands, "breakpoint set --name main")
  end

  local breakpoints = M.get_breakpoints()
  for _, breakpoint in pairs(breakpoints) do
    if breakpoint.enabled then
      table.insert(commands, "b " .. breakpoint.text)
    end
  end

  table.insert(commands, "run")

  local init_file = "/tmp/gdb_init_vim_cmake"
  local _ = vim.fn.writefile(commands, init_file)

  M.close_last_window_if_open()
  M.close_last_buffer_if_open()

  local gdb_init_arg = " -s " .. init_file

  vim.cmd("GdbStartLLDB gdb -q " ..
    gdb_init_arg .. " --args " .. M.get_current_target_name() .. " " .. M.get_run_args())
end

local function read_json_file(file_path)
  local file_contents = vim.fn.readfile(file_path)
  local json_string = table.concat(file_contents, "\n")
  assert(string.len(json_string) > 0, "JSON file " .. file_path .. " is empty")
  return vim.fn.json_decode(json_string)
end

function M.parse_codemodel_json()
  local build_dir = M.get_build_dir()
  local cmake_query_response_dir = build_dir .. "/.cmake/api/v1/reply/"
  local codemodel_file = vim.fn.globpath(cmake_query_response_dir, "codemodel*")

  local targets = read_json_file(codemodel_file).configurations[1].targets

  for _, target in pairs(targets) do
    local name = target.name
    local target_file_data = read_json_file(cmake_query_response_dir .. target.jsonFile)

    local artifacts = target_file_data.artifacts
    if artifacts then
      local relative_path = artifacts[1].path
      local is_exec = target_file_data.type == "EXECUTABLE"

      local filepath = M.state.dir_cache_object.build_dir .. "/" .. relative_path

      M.state.dir_cache_object.targets[name] = {
        current_target_file = filepath,
        current_target_relative = relative_path,
        current_target_name = name,
        args = "",
        breakpoints = {},
        is_exec = is_exec,
      }
    else
      M.state.dir_cache_object.phoney_targets[name] = {
        name = name,
      }
    end
  end

  return true
end

function M.start_nvim_dap_lldb_vscode(job_id, exit_code, event)
  if exit_code ~= 0 then
    return
  end

  local commands = {}

  table.insert(commands, "breakpoint set --name main")

  local breakpoints = M.get_breakpoints()
  for _, breakpoint in pairs(breakpoints) do
    if breakpoint.enabled then
      table.insert(commands, "b " .. breakpoint.text)
    end
  end

  -- table.insert(commands, "run")

  local init_file = "/tmp/lldb_init_vim_cmake"
  local _ = vim.fn.writefile(commands, init_file)

  M.close_last_window_if_open()
  M.close_last_buffer_if_open()

  local command = "DebugLldb " ..
      M.get_current_target_name() .. " --lldbinit " .. init_file .. " -- " .. M.get_run_args()
  vim.cmd(command)
end

function M._do_debug_current_target()
  if M.get_current_target_name() == nil then
    M.cmake_get_target_and_run_action(M._update_target)
  end

  if M.get_debugger() == "gdb" then
    M.cmake_build_current_target_with_completion(M.start_gdb)
  elseif M.get_debugger() == "lldb" then
    M.cmake_build_current_target_with_completion(M.start_lldb)
  elseif M.get_debugger() == "nvim_dap_lldb_vscode" then
    M.cmake_build_current_target_with_completion(M.start_nvim_dap_lldb_vscode)
  else
    print("Debugger " .. M.get_debugger() .. " not supported")
    return
  end
end

function M.toggle_break_at_main()
  local path = vim.env.HOME .. "/.config/vim_cmake/dont_break_at_main"
  if vim.fn.filereadable(path) == 1 then
    vim.fn.delete(path)
    return
  end

  local config = vim.env.HOME .. "/.config"
  if vim.fn.isdirectory(config) == 0 then
    vim.fn.mkdir(config)
  end
  local vim_cmake = config .. "/vim_cmake"
  if vim.fn.isdirectory(vim_cmake) == 0 then
    vim.fn.mkdir(vim_cmake)
  end
  vim.fn.writefile({ " " }, path)
end

function M.list_breakpoints()
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

function M.get_debugger()
  return M.state.debugger
end

function M.get_source_dir()
  return M.get_dco().source_dir
end

function M.configure_and_generate_with_completion(completion)
  if vim.fn.filereadable(M.get_source_dir() .. "/CMakeLists.txt") == 0 then
    print("missing cmakelists.txt NYI")
    -- if exists("g:cmake_template_file")
    --   silent exec "! cp " . g:cmake_template_file . " " . v:lua.require("cmake").get_cmake_source_dir() . "/CMakeLists.txt" else
    --   echom "Could not find a CMakeLists at directory " . v:lua.require("cmake").get_cmake_source_dir()
    --   return
    -- endif
  end

  local command = M.state.cmake_tool .. " " .. M.get_cmake_argument_string()
  print(command)
  M.get_only_window()
  vim.fn.termopen(vim.fn.split(command), { on_exit = completion })
end

function M._update_target_and_run(target)
  M.select_target(target)
  M._do_run_current_target()
end

function M._do_run_current_target()
  local target_name = M.get_current_target_name()
  assert(target_name ~= nil and target_name ~= "", "This should never be unset")

  local target_file = M.get_dco().targets[target_name].current_target_file

  vim.g.vim_cmake_build_tool_old = vim.g.vim_cmake_build_tool
  if vim.g.vim_cmake_build_tool ~= "vsplit" then
    vim.g.vim_cmake_build_tool = "vsplit"
  end

  M.cmake_build_current_target_with_completion(function(_, exit_code, _)
    M.close_last_buffer_if_open()
    if exit_code == 0 then
      M.get_only_window()
      vim.cmd.terminal(target_file .. " " .. M.get_run_args())
    else
      print("Build failed, cannot run target")
    end
    vim.g.vim_cmake_build_tool = vim.g.vim_cmake_build_tool_old
  end)
end

function M.cmake_run_current_target()
  M.parse_codemodel_json_with_completion(M._do_run_current_target)
end

function M.cmake_pick_executable_target()
  M.parse_codemodel_json_with_completion(M._do_cmake_pick_executable_target)
end

function M.parse_codemodel_json_with_completion(completion)
  local build_dir = M.get_build_dir()
  if vim.fn.isdirectory(build_dir .. "/.cmake/api/v1/reply") == 0 then
    M.configure_and_generate_with_completion(function()
      M.parse_codemodel_json()
      completion()
    end)
  else
    M.parse_codemodel_json()
    completion()
  end
end

function M.cmake_build_all()
  M.parse_codemodel_json_with_completion(function(action)
    if vim.g.vim_cmake_build_tool == "vsplit" then
      local command = "cmake --build " .. M.get_build_dir()
      M.get_only_window()
      vim.fn.termopen(command, { on_exit = action })
    elseif vim.g.vim_cmake_build_tool == "Makeshift" then
      print("Makeshift NYI")
      --   let &makeprg = s:get_state("build_command")
      --   let cwd = getcwd()
      --   let b:makeshift_root = cwd . '/' . s:get_cmake_build_dir()
      --   " completion not honored
      --   MakeshiftBuild
    elseif vim.g.vim_cmake_build_tool == "vim-dispatch" then
      print("vim-dispatch NYI")
      --   let cwd = getcwd()
      --   let &makeprg = s:get_state("build_command") . ' -C ' . cwd . '/' . s:get_cmake_build_dir()
      --   " completion not honored
      --   Make
    elseif vim.g.vim_cmake_build_tool == "make" then
      print("make NYI")
      --   let cwd = getcwd()
      --   let &makeprg = s:get_state("build_command") . ' -C ' . cwd . '/' . s:get_cmake_build_dir()
      --   " completion not honored
      --   make
      -- else
      -- endif
    else
      print(
        "vim.g.vim_cmake_build_tool value is invalid. Please set it to either vsplit, Makeshift, vim-dispatch or make.")
    end
  end)
end

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

function M.cmake_close_windows()
  M.close_last_window_if_open()
  M.close_last_buffer_if_open()
end

function M._do_cmake_pick_executable_target(pairs)
  M.cmake_get_target_and_run_action(M.select_target)
  M.dump_current_target()
end

function M.cmake_pick_target()
  M.parse_codemodel_json_with_completion(function()
    M.cmake_get_target_and_run_action(M.select_target)
    M.dump_current_target()
  end)
end

function M.dump_current_target()
  print("Current target set to " .. M.get_ctco().current_target_file .. " with args " .. M.get_ctco().args)
end

function M.select_target(target_name)
  assert(target_name ~= nil, "Invalid target to select_target")
  assert(target_name ~= "", "Invalid target to select_target")

  M.state.dir_cache_object.current_target = target_name
  M.state.current_target_cache_object = M.state.dir_cache_object.targets[target_name]

  M.write_cache_file()
end

function M.cmake_get_target_and_run_action(action)
  local names = M.get_buildable_targets()

  if #names == 1 then
    action(names[1])
  else
    vim.o.makeprg = M.state.build_command
    vim.ui.select(names, { prompt = 'Select Target:' }, action)
  end
end

function M.add_dco_target_if_new(name, target_object)
  if M.state.dir_cache_object.targets[name] ~= nil then
    return
  end
  if target_object.args ~= nil then
    target_object.args = ""
  end
  M.state.dir_cache_object.targets[name] = target_object
end

function M.set_ctco(key, value)
  M.state.current_target_cache_object[key] = value
end

function M.set_state(key, value)
  M.state[key] = value
end

function M.write_cache_file()
  local cache_file = M.state.global_cache_object
  local serial = vim.fn.json_encode(cache_file)
  local split = vim.fn.split(serial, "\n")
  vim.fn.writefile(split, M.state.cache_file_path)
end

function M.set_state_child(key, child, value)
  if M.state[key] == nil then
    M.state[key] = {}
  end
  M.state[key][child] = value
end

function M.cmake_open_cache_file()
  vim.cmd.edit(M.get_build_dir() .. "/CMakeCache.txt")
end

function M.cmake_set_cmake_args(cmake_args)
  M.get_dco().cmake_arguments = cmake_args
  M.write_cache_file()
end

function M.get_cmake_args()
  return M.get_dco().cmake_arguments
end

function M.edit_run_args()
  vim.ui.input({
    prompt = "Run Arguments: ",
    default = M.get_run_args(),
  }, function(input)
    if input == nil then
      return
    end
    M.cmake_set_current_target_run_args(input)
  end)
end

function M.edit_build_dir()
  vim.ui.input({
    prompt = "Build Directory: ",
    default = M.get_build_dir(),
  }, function(input)
    if input == nil then
      return
    end
    M.cmake_update_build_dir(input)
  end)
end

function M.edit_source_dir()
  vim.ui.input({
    prompt = "Source Directory: ",
    default = M.get_dco().source_dir,
  }, function(input)
    if input == nil then
      return
    end
    M.cmake_update_source_dir(input)
  end)
end

function M.edit_cmake_args()
  vim.ui.input({
    prompt = "CMake Arguments: ",
    default = table.concat(M.get_cmake_args(), " "),
  }, function(input)
    if input == nil then
      return
    end
    M.cmake_set_cmake_args(vim.fn.split(input, " "))
  end)
end

function M.cmake_load()
  -- do nothing ... just enables my new build dir grep command to work
end

function M.get_build_tools()
  return { "vsplit", "vim-dispatch", "Makeshift", "make", "job" }
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

function M.run_lit_on_file()
  local full_path = vim.fn.expand("%:p")
  local lit_path = "llvm-lit"
  local bin_lit_path = M.get_build_dir() .. "/bin/llvm-lit"
  if vim.fn.filereadable(bin_lit_path) == 1 then
    lit_path = bin_lit_path
  end
  M.get_only_window()
  vim.fn.termopen({ lit_path, M.state.extra_lit_args, full_path })
end

function M.setup(opts)
  print("SETUP")
  vim.g.cmake_last_window = nil
  vim.g.cmake_last_buffer = nil

  if not vim.g.vim_cmake_build_tool then
    vim.g.vim_cmake_build_tool = 'vsplit'
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
  { nargs = "?" }) -- { nargs = "?", complete = M.get_build_tools })

vim.api.nvim_create_user_command("CMakeClean", M.cmake_clean, { nargs = 0, })
vim.api.nvim_create_user_command("CMakeBuildAll", M.cmake_build_all, { nargs = 0, })

vim.api.nvim_create_user_command("CMakeCreateFile", M.cmake_create_file, { nargs = 1 })
vim.api.nvim_create_user_command("CMakeCloseWindow", M.cmake_close_windows, { nargs = 0, })
vim.api.nvim_create_user_command("CMakeRunLitOnFile", M.run_lit_on_file, { nargs = 0, })
vim.api.nvim_create_user_command("CMakeLoad", M.cmake_load, { nargs = 0, })

vim.api.nvim_create_user_command("CMakeConfigureAndGenerate", M.configure_and_generate, { nargs = 0, })

vim.api.nvim_create_user_command("CMakeToggleFileLineColumnBreakpoint", M.toggle_file_line_column_breakpoint,
  { nargs = 0, })
vim.api.nvim_create_user_command("CMakeToggleFileLineBreakpoint", M.toggle_file_line_breakpoint, { nargs = 0, })

vim.api.nvim_create_user_command("CMakeListBreakpoints", M.list_breakpoints, { nargs = 0, })
vim.api.nvim_create_user_command("CMakeToggleBreakAtMain", M.toggle_break_at_main, { nargs = 0, })

vim.api.nvim_create_user_command("CMakeDebugWithNvimLLDB", M.cmake_debug_current_target_lldb, { nargs = 0, })
vim.api.nvim_create_user_command("CMakeDebugWithNvimGDB", M.cmake_debug_current_target_gdb, { nargs = 0, })
vim.api.nvim_create_user_command("CMakeDebugWithNvimDapLLDBVSCode", M.cmake_debug_current_target_nvim_dap_lldb_vscode,
  { nargs = 0, })


return M
