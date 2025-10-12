" cmake.vim - Vim plugin to create a CMake project system
" Maintainer: Nathan Lanza <https://github.com/lanza>
" Version:    0.2

if exists('g:loaded_vim_cmake')
  finish
else
  let g:loaded_vim_cmake = 1
endif

function s:get_name_relative_pairs()
  return v:lua.require("cmake").state.dir_cache_object.name_relative_pairs
endfunction

function s:get_cmake_target_file()
  return v:lua.require("cmake").get_dco("current_target_file")
endfunction

function s:get_cmake_target_args()
  return v:lua.require("cmake").get_ctco("args")
endfunction

function s:set_cmake_arguments(value)
  call v:lua.require("cmake").set_dco("cmake_arguments", a:value)
endfunction
function s:get_cmake_arguments()
  return v:lua.require("cmake").get_dco("cmake_arguments")
endfunction

function s:get_cmake_build_dir()
  return v:lua.require("cmake").get_dco("build_dir")
endfunction
function s:set_cmake_build_dir(value)
  call v:lua.require("cmake").set_dco("build_dir", a:value)
endfunction

function s:get_cmake_source_dir()
  return v:lua.require("cmake").get_dco("source_dir")
endfunction
function s:set_cmake_source_dir(value)
  call v:lua.require("cmake").set_dco("source_dir", a:value)
endfunction

function s:get_cmake_cache_file()
  return v:lua.require("cmake").state.cache_object
endfunction

function s:get_state(key)
  return v:lua.require("cmake").get_state(a:key)
endfunction

" this needs to be wrapped due to the need to use on_exit to pipeline the config
function g:cmake#ParseCodeModelJson()
  let l:build_dir = s:get_cmake_build_dir()
  let l:cmake_query_response = l:build_dir . '/.cmake/api/v1/reply/'
  let l:codemodel_file = globpath(l:cmake_query_response, 'codemodel*')
  let l:codemodel_contents = readfile(l:codemodel_file)
  let l:json_string = join(l:codemodel_contents, "\n")

  if len(l:json_string) == 0
    return
  endif

  let l:data = json_decode(l:json_string)

  let l:configurations = l:data['configurations']
  let l:first_config = l:configurations[0]
  let l:targets_dicts = l:first_config['targets']

  call v:lua.require("cmake").set_dco("name_relative_pairs", [])

  let g:tar_to_relative = {}

  for target in targets_dicts
    let l:jsonFile = target['jsonFile']
    let l:name = target['name']
    let l:file = readfile(l:cmake_query_response . l:jsonFile)
    let l:json_string = join(l:file, "\n")
    let l:target_file_data = json_decode(l:json_string)
    if has_key(l:target_file_data, 'artifacts')
      let l:artifacts = l:target_file_data['artifacts']
      let l:artifact = l:artifacts[0]
      let l:path = l:artifact['path']
      let l:type = l:target_file_data['type']
      let l:is_exec = l:type ==? "Executable"
      call v:lua.require("cmake").add_name_relative_pair( 
            \ l:name,
            \ l:path,
            \ l:is_exec,
            \ v:true)
      let g:tar_to_relative[l:name] = l:path
    else
      let l:type = l:target_file_data['type']
      call v:lua.require("cmake").add_name_relative_pair(
            \ l:name,
            \ v:false,
            \ v:false)
    endif
  endfor
  return 1
endf

call v:lua.require("cmake").initialize_cache_file()

function s:make_query_files()
  let l:build_dir = s:get_cmake_build_dir()
  if !isdirectory(l:build_dir . '/.cmake/api/v1/query')
    call mkdir(l:build_dir . '/.cmake/api/v1/query', 'p')
  endif
  if !filereadable(l:build_dir . '/.cmake/api/v1/query/codemodel-v2')
    call writefile([' '], l:build_dir . '/.cmake/api/v1/query/codemodel-v2')
  endif
endfunction

function s:get_cmake_argument_string()
  call s:make_query_files()
  let l:arguments = []
  let l:arguments += s:get_cmake_arguments()
  let l:arguments += ['-G ' . s:get_state("generator")]
  let l:arguments += ['-DCMAKE_EXPORT_COMPILE_COMMANDS=ON']

  let found_source_dir_arg = v:false
  let found_build_dir_arg = v:false
  let found_cmake_build_type = v:false
  for arg in s:get_cmake_arguments()
    if (arg =~ "CMAKE_BUILD_TYPE")
      let found_cmake_build_type = v:true
    elseif (arg =~ "-S")
      let found_source_dir_arg = v:true
    elseif (arg =~ "-B")
      let found_build_dir_arg = v:true
    elseif (isdirectory(arg) && filereadable(arg . "/CMakeLists.txt"))
      let found_source_dir_arg = v:true
    endif
  endfor

  if !found_cmake_build_type
    let l:arguments += ['-DCMAKE_BUILD_TYPE=Debug']
  endif

  if !found_build_dir_arg
    let l:arguments += ['-B', s:get_cmake_build_dir()]
  endif

  if !found_source_dir_arg
    let l:arguments += ['-S', s:get_cmake_source_dir()]
  endif

  let l:command = join(l:arguments, ' ')
  return l:command
endfunction

function g:CMake_configure_and_generate()
  call s:cmake_configure_and_generate()
endfunction

function s:check_if_window_is_alive(win)
  if index(nvim_list_wins(), a:win) > -1
    return v:true
  else
    return v:false
  endif
endfunction

function s:check_if_buffer_is_alive(buf)
  if index(nvim_list_bufs(), a:buf) > -1
    return v:true
  else
    return v:false
  endif
endfunction

function s:cmake_configure_and_generate()
  call g:cmake#ConfigureAndGenerateWithCompletion(s:noop)
endfunction

function g:cmake#ConfigureAndGenerateWithCompletion(completion)
  if !filereadable(s:get_cmake_source_dir() . "/CMakeLists.txt")
    if exists("g:cmake_template_file")
      silent exec "! cp " . g:cmake_template_file . " " . s:get_cmake_source_dir() . "/CMakeLists.txt"
    else
      echom "Could not find a CMakeLists at directory " . s:get_cmake_source_dir()
      return
    endif
  endif
  let l:command = s:get_state("cmake_tool") . " " . s:get_cmake_argument_string()
  echo l:command
  call v:lua.require("cmake").get_only_window()
  call termopen(split(l:command), {'on_exit': a:completion})
  " let l:link_cc_path = getcwd() . '/' . s:get_source_dir() . '/compile_commands.json'
  " let l:build_cc_path = getcwd() . '/' . s:get_build_dir() . '/compile_commands.json'
  " exe 'silent !test -L ' . l:link_cc_path . ' || test -e ' . l:link_cc_path . ' || ln -s ' . l:build_cc_path . .'
endfunction

function s:noop_function(...)
endfunction

let s:noop = function('s:noop_function')

let g:cmake_last_window = v:null
let g:cmake_last_buffer = v:null

if !exists('g:vim_cmake_build_tool')
  let g:vim_cmake_build_tool = 'vsplit'
endif

function s:cmake_clean()
  let l:command = 'cmake --build ' . s:get_cmake_build_dir() . ' --target clean'
  exe "vs | exe \"normal \<c-w>L\" | terminal " . l:command
endfunction

function s:cmake_get_target_and_run_action(name_relative_pairs, action)
  " echom "s:cmake_get_target_and_run_action([" . join(a:target_list, ",")  . "], " . a:action . ")"
  let l:names = []
  for target in a:name_relative_pairs
    let l:name = target.name
    call add(l:names, l:name)
  endfor

  if len(l:names) == 1
    " this has to be unwrapped because a:action is a string
    exec "call " . a:action . "(\"" . l:names[0] . "\")"
  else
    let &makeprg = s:get_state("build_command")
    call fzf#run({'source': l:names, 'sink': function(a:action), 'down': len(l:names) + 2})
  endif
endfunction

" TODO: Fix this breakpoint handling
function s:start_gdb(job_id, exit_code, event)
  if a:exit_code != 0
    return
  endif
  let l:commands = ['b main', 'r']
  let l:data = s:get_cmake_cache_file()
  if has_key(l:data, getcwd())
    let l:dir = l:data[getcwd()]['targets']
    if has_key(l:dir, s:get_cmake_build_dir() . '/' . s:get_cmake_target_file())
      let l:target = l:dir[s:get_cmake_build_dir() . '/' . s:get_cmake_target_file()]
      if has_key(l:target, 'breakpoints')
        let l:breakpoints = l:target['breakpoints']
        for b in l:breakpoints
          if b['enabled']
            let break = 'b ' . b['text']
            call add(l:commands, break)
          endif
        endfor
        call add(l:commands, 'r')
      endif
    endif
  endif

  let l:init_file = '/tmp/gdbinitvimcmake'
  let l:f = writefile(l:commands, l:init_file)

  call v:lua.require("cmake").close_last_window_if_open()
  call v:lua.require("cmake").close_last_buffer_if_open()

  let l:gdb_init_arg = ' -x /tmp/gdbinitvimcmake '
  let l:exec = 'GdbStart gdb -q ' . l:gdb_init_arg . ' --args ' . s:get_cmake_target_file() . " " . s:get_cmake_target_args()
  " echom l:exec
  exec l:exec
endfunction

function s:start_lldb(job_id, exit_code, event)
  if a:exit_code != 0
    return
  endif
  let l:commands = []

  if s:should_break_at_main()
    call add(l:commands, "breakpoint set --func-regex '^main$'")
  endif

  let l:data = s:get_cmake_cache_file()
  if has_key(l:data, getcwd())
    let l:breakpoints = l:data[getcwd()]["targets"][s:get_cmake_target_file()]["breakpoints"]
    for b in keys(l:breakpoints)
      echom b
      let l:bp = l:breakpoints[b]
      if l:bp['enabled']
        let break = 'b ' . l:bp['text']
        call add(l:commands, break)
      endif
    endfor
  endif

  call add(l:commands, 'r')

  let l:init_file = '/tmp/lldbinitvimcmake'
  let l:f = writefile(l:commands, l:init_file)

  call v:lua.require("cmake").close_last_window_if_open()
  call v:lua.require("cmake").close_last_buffer_if_open()

  if exists('l:init_file')
    let l:lldb_init_arg = ' -s /tmp/lldbinitvimcmake '
  else
    let l:lldb_init_arg = ''
  endif
  exec 'GdbStartLLDB lldb ' . s:get_cmake_target_file() . l:lldb_init_arg . ' -- ' . s:get_cmake_target_args()
endfunction

function s:toggle_file_line_column_breakpoint()
  let l:curpos = getcurpos()
  let l:line_number = l:curpos[1]
  let l:column_number = l:curpos[2]

  let l:filename = expand("#" . bufnr() . ":p")

  let l:break_string = l:filename . ":" . l:line_number . ":" . l:column_number

  call s:toggle_breakpoint(l:break_string)
endfunction

function s:toggle_break_at_main()
  if filereadable($HOME . ".config/vim_cmake/dont_break_at_main")
    silent !rm ~/.config/vim_cmake/dont_break_at_main
  else
    if !isdirectory($HOME . "/.config")
      silent !mkdir ~/.config
    end
    if !isdirectory($HOME . "/.config/vim_cmake")
      silent !mkdir ~/.config/vim_cmake
    end
    silent !touch ~/.config/vim_cmake/dont_break_at_main
  endif
endfunction

function s:should_break_at_main()
  return !filereadable($HOME . "/.config/vim_cmake/dont_break_at_main")
endfunction

function s:toggle_file_line_breakpoint()
  let l:curpos = getcurpos()
  let l:line_number = l:curpos[1]

  let l:filename = expand("#" . bufnr() . ":p")

  let l:break_string = l:filename . ":" . l:line_number

  call s:toggle_breakpoint(l:break_string)
endfunction

function g:CMake_list_breakpoints()
  let args = []
  let l:bps = s:get_cmake_cache_file()[getcwd()]["targets"][s:get_cmake_target_file()]["breakpoints"]
  for bp in keys(l:bps)
    let l:b = l:bps[bp]
    if l:b["enabled"]
      call add(args, bp)
    endif
  endfor

  echo join(args, "\n")
endfunction

function s:toggle_breakpoint(break_string)
  let l:data = s:get_cmake_cache_file()
  let l:breakpoints = l:data[getcwd()]['targets'][s:get_cmake_target_file()]["breakpoints"]
  if has_key(l:breakpoints, a:break_string)
    let l:breakpoints[a:break_string]["enabled"] = !l:breakpoints[a:break_string]["enabled"]
  else
    let l:breakpoints[a:break_string] = {
        \ "text": a:break_string,
        \ "enabled": v:true
        \ }
  endif
  call v:lua.require("cmake").write_cache_file()
endfunction

" TODO: Fix this breakpoint handling
function s:start_nvim_dap_lldb_vscode(job_id, exit_code, event)
  if a:exit_code != 0
    return
  endif
  let l:commands = ["breakpoint set --func-regex '^main$'", 'r']
  let l:data = s:get_cmake_cache_file()
  if has_key(l:data, getcwd())
    let l:dir = l:data[getcwd()]['targets']
    if has_key(l:dir, s:get_cmake_build_dir() . '/' . s:get_cmake_target_file())
      let l:target = l:dir[s:get_cmake_build_dir() . '/' . s:get_cmake_target_file()]
      if has_key(l:target, 'breakpoints')
        let l:breakpoints = l:target['breakpoints']
        for b in l:breakpoints
          if b['enabled']
            let break = 'b ' . b['text']
            call add(l:commands, break)
          endif
        endfor
      endif
    endif
  endif

  let l:init_file = '/tmp/lldbinitvimcmake'
  let l:f = writefile(l:commands, l:init_file)

  call v:lua.require("cmake").close_last_window_if_open()
  call v:lua.require("cmake").close_last_buffer_if_open()

  if exists('l:init_file')
    let l:lldb_init_arg = ' /tmp/lldbinitvimcmake '
  else
    let l:lldb_init_arg = ''
  endif
  exec 'DebugLldb ' . s:get_cmake_target_file() . ' --lldbinit ' . l:lldb_init_arg . ' -- ' . s:get_cmake_target_args()
endfunction

function s:cmake_debug_current_target_nvim_dap_lldb_vscode()
  echom "in dap function"
  call v:lua.require("cmake").set_state("debugger", "nvim_dap_lldb_vscode")
  call s:cmake_debug_current_target()
endf

function s:cmake_debug_current_target_lldb()
  call v:lua.require("cmake").set_state("debugger", "lldb")
  call s:cmake_debug_current_target()
endf

function s:cmake_debug_current_target_gdb()
  call v:lua.require("cmake").set_state("debugger", "gdb")
  call s:cmake_debug_current_target()
endf

function s:cmake_debug_current_target()
  call v:lua.require("cmake").parse_codemodel_json_with_completion(function("s:_do_debug_current_target"))
endfunction

function s:_do_debug_current_target()
  if s:get_cmake_target_file() == v:null
    call s:cmake_get_target_and_run_action(s:get_execs_from_namae_relative_pairs(), 's:update_target')
  endif

  if s:get_state("debugger") ==? 'gdb'
    call v:lua.require("cmake").cmake_build_current_target_with_completion(function('s:start_gdb'))
  elseif v:lua.require("cmake").get_state("debugger") ==? 'lldb'
    call v:lua.require("cmake").cmake_build_current_target_with_completion(function('s:start_lldb'))
  else
    call v:lua.require("cmake").cmake_build_current_target_with_completion(function('s:start_nvim_dap_lldb_vscode'))
  endif
endfunction

function s:cmake_set_cmake_args(...)
  let l:arguments = a:000
  call s:set_cmake_arguments(l:arguments)
  call v:lua.require("cmake").write_cache_file()
endfunction

function g:GetCMakeArgs()
  return s:get_cmake_arguments()
endfunction

function g:GetCMakeCurrentTargetRunArgs()
  let c = s:get_cmake_single_target_cache()
  return c.args
endfunction

function s:get_cmake_single_target_cache()
  let c = v:lua.require("cmake").get_dco("targets")
  return c[s:get_cmake_target_file()]
endfunction

function s:cmake_create_file(...)
  if len(a:000) > 2 || len(a:000) == 0
    echo 'CMakeCreateFile requires 1 or 2 arguments: e.g. Directory File for `Directory/File.{cpp,h}`'
    return
  endif

  if len(a:000) == 2
    let l:header = "include/" . a:1 . "/" . a:2 . ".h"
    let l:source = "lib/" . a:1 . "/" . a:2 . ".cpp"
    silent exec "!touch " . l:header
    silent exec "!touch " . l:source
  elseif len(a:000) == 1
    let l:header = "include/" . a:1 . ".h"
    let l:source = "lib/" . a:1 . ".cpp"
    silent exec "!touch " . l:header
    silent exec "!touch " . l:source
  end
endfunction

function s:cmake_update_build_dir(...)
  let dir = a:1
  call s:set_cmake_build_dir(dir)
  call v:lua.require("cmake").write_cache_file()
endfunction

function s:cmake_update_source_dir(...)
  let dir = a:1
  call s:set_cmake_source_dir(dir)
  call v:lua.require("cmake").write_cache_file()
endfunction

function g:GetCMakeSourceDir()
  return s:get_cmake_source_dir()
endfunction

function g:GetCMakeBuildDir()
  return s:get_cmake_build_dir()
endfunction

function s:cmake_open_cache_file()
  exe 'e ' . s:get_cmake_build_dir() . '/CMakeCache.txt'
endf

function s:get_build_tools(...)
  return ["vim-dispatch", "vsplit", "Makeshift", "make", "job"]
endfunction

function s:cmake_load()
  " do nothing ... just enables my new build dir grep command to work
endfunction

command! -nargs=0 CMakeOpenCacheFile call s:cmake_open_cache_file()

command! -nargs=* -complete=shellcmd CMakeSetCMakeArgs call s:cmake_set_cmake_args(<f-args>)
command! -nargs=1 -complete=shellcmd CMakeSetBuildDir call s:cmake_update_build_dir(<f-args>)
command! -nargs=1 -complete=shellcmd CMakeSetSourceDir call s:cmake_update_source_dir(<f-args>)

command! -nargs=0  CMakeConfigureAndGenerate call s:cmake_configure_and_generate()

command! -nargs=0 CMakeDebugWithNvimLLDB call s:cmake_debug_current_target_lldb()
command! -nargs=0 CMakeDebugWithNvimGDB call s:cmake_debug_current_target_gdb()
command! -nargs=0 CMakeDebugWithNvimDapLLDBVSCode call s:cmake_debug_current_target_nvim_dap_lldb_vscode()

command! -nargs=0 CMakePickTarget call v:lua.require("cmake").cmake_pick_target()
command! -nargs=0 CMakePickExecutableTarget call v:lua.require("cmake").cmake_pick_executable_target()
command! -nargs=0 CMakeRunCurrentTarget call v:lua.require("cmake").cmake_run_current_target()
command! -nargs=* -complete=shellcmd CMakeSetCurrentTargetRunArgs call v:lua.require("cmake").cmake_set_current_target_run_args(<q-args>)
command! -nargs=? -complete=customlist,s:get_build_tools CMakeBuildCurrentTarget call v:lua.require("cmake").cmake_build_current_target(<f-args>)

command! -nargs=1 -complete=shellcmd CMakeClean call s:cmake_clean()
command! -nargs=0 CMakeBuildAll call v:lua.require("cmake").cmake_build_all()

command! -nargs=0 CMakeToggleFileLineColumnBreakpoint call s:toggle_file_line_column_breakpoint()
command! -nargs=0 CMakeToggleFileLineBreakpoint call s:toggle_file_line_breakpoint()
command! -nargs=0 CMakeListBreakpoints call g:CMake_list_breakpoints()
command! -nargs=0 CMakeToggleBreakAtMain call s:toggle_break_at_main()

command! -nargs=* -complete=shellcmd CMakeCreateFile call s:cmake_create_file(<f-args>)

command! -nargs=1 -complete=shellcmd CMakeCloseWindow call v:lua.require("cmake").cmake_close_windows()

command! -nargs=0 CMakeRunLitOnFile call v:lua.require("cmake").run_lit_on_file()

command! -nargs=0 CMakeLoad call s:cmake_load()

command! CMakeEditCurrentTargetRunArgs call feedkeys(":CMakeSetCurrentTargetRunArgs " . eval("g:GetCMakeCurrentTargetRunArgs()"))
command! CMakeEditCMakeArgs call feedkeys(":CMakeSetCMakeArgs " . eval("join(g:GetCMakeArgs(), ' ')"))
command! CMakeEditBuildDir call feedkeys(":CMakeSetBuildDir " . eval("g:GetCMakeBuildDir()"))
command! CMakeEditSourceDir call feedkeys(":CMakeSetSourceDir " . eval("g:GetCMakeSourceDir()"))


