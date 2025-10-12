" cmake.vim - Vim plugin to create a CMake project system
" Maintainer: Nathan Lanza <https://github.com/lanza>
" Version:    0.2

if exists('g:loaded_vim_cmake')
  finish
else
  let g:loaded_vim_cmake = 1
endif

function s:set_if_empty(object, key, val)
  if !has_key(a:object, a:key)
    let a:object[a:key] = a:val
  endif
  return a:object[a:key]
endfunction

function s:get_name_relative_pairs()
  return s:get_cmake_dir_cache_object().name_relative_pairs
endfunction

let g:state = {
    \ "cmake_tool": "cmake",
    \ "cache_file_path": $HOME . '/.vim_cmake.json',
    \ "generator": 'Ninja',
    \ "build_command": "ninja_distcc",
    \ "template_file": expand(":p:h:h" . "/CMakeLists.txt"),
    \ "cache_object": v:null,
    \ "dir_cache_object": v:null,
    \ }

function s:get_cmake_dir_cache_object()
  return g:state.dir_cache_object
endfunction

function s:get_cmake_target_file()
  return s:get_cmake_dir_cache_object().current_target_file
endfunction
function s:set_cmake_target_file(value)
  let l:dco = s:get_cmake_dir_cache_object()
  let l:dco.current_target_file = a:value
  let g:state.current_target_cache_object = s:get_cmake_dir_cache_object().targets[a:value]
endfunction

function s:add_cmake_target_to_target_list(target_name)
  let l:file = s:get_cmake_build_dir() . '/' . g:tar_to_relative[a:target_name]
  let l:relative = g:tar_to_relative[a:target_name]

  call s:set_if_empty(s:get_cmake_dir_cache_object().targets, l:file, {
      \ "current_target_file" : l:file,
      \ "current_target_relative" : l:relative,
      \ "current_target_name" : a:target_name,
      \ "args": "",
      \ "breakpoints": {}
      \ })
endfunction

function s:get_cmake_target_relative()
  return g:state.current_a.current_target_relative.current_target_relative
endfunction
function s:set_cmake_target_relative(value)
  let g:state.current_target_cache_object.current_target_relative = a:value
endfunction

function s:get_cmake_target_name()
  return g:state.current_target_cache_object.current_target_name
endfunction
function s:set_cmake_target_name(value)
  let g:state.current_target_cache_object.current_target_name = a:value
endfunction

function s:set_cmake_target_args(value)
  let g:state.current_target_cache_object.args = a:value
endfunction
function s:get_cmake_target_args()
  return g:state.current_target_cache_object.args
endfunction

function s:set_cmake_target_breakpoints(value)
  let g:state.current_target_cache_object.breakpoints = a:value
endfunction
function s:get_cmake_target_breakpoints()
  return g:state.current_target_cache_object.breakpoints
endfunction

function s:set_cmake_arguments(value)
  let g:state.dir_cache_object.cmake_arguments = a:value
endfunction
function s:get_cmake_arguments()
  return g:state.dir_cache_object.cmake_arguments
endfunction

function s:get_cmake_build_dir()
  return g:state.dir_cache_object.build_dir
endfunction
function s:set_cmake_build_dir(value)
  let g:state.dir_cache_object.build_dir = a:value
endfunction

function s:get_cmake_source_dir()
  return g:state.dir_cache_object.source_dir
endfunction
function s:set_cmake_source_dir(value)
  let g:state.dir_cache_object.source_dir = a:value
endfunction

function s:get_cmake_cache_file()
  return g:state.cache_object
endfunction
function s:set_cmake_cache_file(value)
  let g:state.cache_object = a:value
endfunction

function s:get_state()
  return g:state
endfunction

" this needs to be wrapped due to the need to use on_exit to pipeline the config
function s:_do_parse_codemodel_json()
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


  let g:state.dir_cache_object.name_relative_pairs = []

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
      call add(s:get_name_relative_pairs(), {
            \ "name": l:name,
            \ "relative" : l:path,
            \ "is_exec": l:is_exec,
            \ "is_artifact": v:true
            \ })
      let g:tar_to_relative[l:name] = l:path
    else
      let l:type = l:target_file_data['type']
      call add(s:get_name_relative_pairs() , {
            \ "name": l:name,
            \ "is_exec": v:false,
            \ "is_artifact": v:false,
            \ })
    endif
  endfor
  return 1
endf

function s:do_all_completions(...)
  for Completion in a:000
    if type(Completion) == v:t_func
      call Completion()
    endif
  endfor
endfunction

function s:compose_completions(outer, inner)
  call a:outer(a:inner)
endfunction

function s:parse_codemodel_json_with_completion(completion)
  let l:build_dir = s:get_cmake_build_dir()
  if !isdirectory(l:build_dir . '/.cmake/api/v1/reply')
    call s:assure_query_reply_with_completion(function('s:do_all_completions', [function('s:_do_parse_codemodel_json'), a:completion]))
  else
    call s:_do_parse_codemodel_json()
    call a:completion()
  endif
endfunction

function s:initialize_cache_file()
  " initialize some variables
  if exists("g:cmake_template_file")
    let g:state.template_file = g:cmake_template_file
  end
  if exists("g:cmake_default_build_dir")
    let g:state.default_build_dir = g:cmake_default_build_dir
  else
    let g:state.default_build_dir = "build"
  end
  if exists("g:cmake_extra_lit_args")
    let g:state.extra_lit_args = g:cmake_extra_lit_args
  else
    let g:state.extra_lit_args = "-a"
  endif
  if exists("g:vim_cmake_debugger")
    let g:state.debugger = g:vim_cmake_debugger
  endif

  " load cache file from disk
  if filereadable(g:state.cache_file_path)
    let l:contents = readfile(g:state.cache_file_path)
    let l:json_string = join(l:contents, "\n")

    call s:set_cmake_cache_file(json_decode(l:json_string))
  else
    call s:set_cmake_cache_file(json_decode('{}'))
  endif

  " load directory cache object
  if !has_key(g:state.cache_object, getcwd())
    let g:state.cache_object[getcwd()] = {}
  endif
  let g:state.dir_cache_object = g:state.cache_object[getcwd()]

  " initialize directory cache object
  let l:dco = g:state.dir_cache_object
  call s:set_if_empty(l:dco, "cmake_arguments", [])
  call s:set_if_empty(l:dco, "build_dir", g:state.default_build_dir)
  call s:set_if_empty(l:dco, "source_dir", ".")
  call s:set_if_empty(l:dco, "targets", {})
  call s:set_if_empty(l:dco, "name_relative_pairs", [])

  " initialize current target cache object
  call s:set_if_empty(l:dco, "current_target_file", v:null)

  if l:dco.current_target_file != v:null
    let g:state.current_target_cache_object = l:dco.targets[l:dco.current_target_file]
  else
    let g:state.current_target_cache_object = v:null
  endif
endfunction

function g:CMake_get_cache_file()
  return s:get_cmake_cache_file()
endfunction

call s:initialize_cache_file()

function s:make_query_files()
  let l:build_dir = s:get_cmake_build_dir()
  if !isdirectory(l:build_dir . '/.cmake/api/v1/query')
    call mkdir(l:build_dir . '/.cmake/api/v1/query', 'p')
  endif
  if !filereadable(l:build_dir . '/.cmake/api/v1/query/codemodel-v2')
    call writefile([' '], l:build_dir . '/.cmake/api/v1/query/codemodel-v2')
  endif
endfunction

function s:assure_query_reply_with_completion(completion)
  let l:build_dir = s:get_cmake_build_dir()
  if !isdirectory(l:build_dir . '/.cmake/api/v1/reply')
    call s:cmake_configure_and_generate_with_completion(a:completion)
  else
    call a:completion()
  endif
endfunction

function s:get_cmake_argument_string()
  call s:make_query_files()
  let l:arguments = []
  let l:arguments += s:get_cmake_arguments()
  let l:arguments += ['-G ' . s:get_state().generator]
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

" close the current window and open a new one
" This is a hack for now because I don't feel like figuring out how to clean a
" dirty buffer and termopen refuses to open in a dirty buffer
function s:get_only_window()
  call s:close_last_window_if_open()
  call s:close_last_buffer_if_open()
  exe "vs | wincmd L | enew"
  let g:cmake_last_window = nvim_get_current_win()
  let g:cmake_last_buffer = nvim_get_current_buf()
endfunction

function s:cmake_configure_and_generate()
  call s:cmake_configure_and_generate_with_completion(s:noop)
endfunction

function s:cmake_configure_and_generate_with_completion(completion)
  if !filereadable(s:get_cmake_source_dir() . "/CMakeLists.txt")
    if exists("g:cmake_template_file")
      silent exec "! cp " . g:cmake_template_file . " " . s:get_cmake_source_dir() . "/CMakeLists.txt"
    else
      echom "Could not find a CMakeLists at directory " . s:get_cmake_source_dir()
      return
    endif
  endif
  let l:command = s:get_state().cmake_tool . " " . s:get_cmake_argument_string()
  echo l:command
  call s:get_only_window()
  call termopen(split(l:command), {'on_exit': a:completion})
  " let l:link_cc_path = getcwd() . '/' . s:get_source_dir() . '/compile_commands.json'
  " let l:build_cc_path = getcwd() . '/' . s:get_build_dir() . '/compile_commands.json'
  " exe 'silent !test -L ' . l:link_cc_path . ' || test -e ' . l:link_cc_path . ' || ln -s ' . l:build_cc_path . .'
endfunction


function s:cmake_build_current_target(...)
  if a:0 > 1
    echom "CMakeBuildCurrentTarget takes one argument -- the dispatcher for the build"
  end
  let l:previous = g:vim_cmake_build_tool
  if a:0 == 1
    let g:vim_cmake_build_tool = a:1
  endif
  call s:cmake_build_current_target_with_completion(s:noop)
  let g:vim_cmake_build_tool = l:previous
endfunction

function s:_do_build_current_target()
  call s:_do_build_current_target_with_completion(s:noop)
endfunction

function s:noop_function(...)
endfunction

let s:noop = function('s:noop_function')

function s:_update_target_and_build(target)
  call s:select_target(a:target)
  call s:_do_build_current_target()
endfunction


function s:_do_build_current_target_with_completion(completion)
  if s:get_cmake_target_file() == v:null
    call s:cmake_get_target_and_run_action(s:get_name_relative_pairs(), 's:_update_target_and_build')
    return
  endif

  call s:_build_target_with_completion(s:get_cmake_target_name(), a:completion)
endfunction

function s:_do_build_all_with_completion(completion)
  call s:_build_all_with_completion(a:completion)
endfunction

function s:cmake_build_all_with_completion(completion)
  call s:parse_codemodel_json_with_completion(function('s:compose_completions', [function('s:_do_build_all_with_completion'), a:completion]))
endfunction

function s:cmake_build_current_target_with_completion(completion)
  call s:parse_codemodel_json_with_completion(function('s:compose_completions', [function('s:_do_build_current_target_with_completion'), a:completion]))
endfunction

func s:is_absolute_path(path)
  let l:is_absolute = execute("lua print(vim.startswith('" . a:path . "', '/'))")
  if l:is_absolute =~ "true"
    return 1
  else
    return 0
  endif
endfunction

function s:_build_target(target)
  call s:_build_target_with_completion(a:target, v:null)
endfunction

let g:cmake_last_window = v:null
let g:cmake_last_buffer = v:null

function s:_build_target_with_completion(target, completion)
  if s:is_absolute_path(s:get_cmake_build_dir())
    let l:directory = s:get_cmake_build_dir()
  else
    let l:cwd = getcwd()
    let l:directory = cwd . '/' . s:get_cmake_build_dir()
  endif

  if g:vim_cmake_build_tool ==? 'vsplit'
    let l:command = 'cmake --build ' . s:get_cmake_build_dir() . ' --target ' . a:target
    call s:get_only_window()
    call termopen(l:command, { "on_exit": a:completion })
  elseif g:vim_cmake_build_tool ==? 'vim-dispatch'
    let &makeprg = s:get_state().build_command . ' -C ' . l:directory . ' ' . a:target
    " completion not honored
    Make
  elseif g:vim_cmake_build_tool ==? 'Makeshift'
    let &makeprg = s:get_state.build_command . ' ' . a:target
    let b:makeshift_root = l:directory
    " completion not honored
    MakeshiftBuild
  elseif g:vim_cmake_build_tool ==? 'make'
    let &makeprg = s:get_state().build_command . ' -C ' . l:directory . ' ' . a:target
    " completion not honored
    make
  elseif g:vim_cmake_build_tool ==? 'job'
    let l:cmd = s:get_state().build_command . ' -C ' . l:directory . ' ' . a:target
    call jobstart(cmd, {"on_exit": a:completion })
  else
    echo 'Your g:vim_cmake_build_tool value is invalid. Please set it to either vsplit, Makeshift, vim-dispatch or make.'
  endif
endfunction

if !exists('g:vim_cmake_build_tool')
  let g:vim_cmake_build_tool = 'vsplit'
endif

function s:cmake_clean()
  let l:command = 'cmake --build ' . s:get_cmake_build_dir() . ' --target clean'
  exe "vs | exe \"normal \<c-w>L\" | terminal " . l:command
endfunction

function s:cmake_build_all()
  call s:cmake_build_all_with_completion(s:noop)
endfunction

function s:_build_all_with_completion(completion)
  if g:vim_cmake_build_tool ==? 'vsplit'
    let l:command = 'cmake --build ' . s:get_cmake_build_dir()
    call s:get_only_window()
    call termopen(l:command, { "on_exit": a:completion })
  elseif g:vim_cmake_build_tool ==? 'Makeshift'
    let &makeprg = s:get_state().build_command
    let cwd = getcwd()
    let b:makeshift_root = cwd . '/' . s:get_cmake_build_dir()
    " completion not honored
    MakeshiftBuild
  elseif g:vim_cmake_build_tool ==? 'vim-dispatch'
    let cwd = getcwd()
    let &makeprg = s:get_state().build_command . ' -C ' . cwd . '/' . s:get_cmake_build_dir()
    " completion not honored
    Make
  elseif g:vim_cmake_build_tool ==? 'make'
    let cwd = getcwd()
    let &makeprg = s:get_state().build_command . ' -C ' . cwd . '/' . s:get_cmake_build_dir()
    " completion not honored
    make
  else
    echo 'Your g:vim_cmake_build_tool value is invalid. Please set it to either vsplit, Makeshift, vim-dispatch or make.'
  endif

endfunction

function s:write_cache_file()
  let cache = s:get_cmake_cache_file()
  let serial = encode_json(cache)
  let split = split(serial, '\n')
  call writefile(split, $HOME . '/.vim_cmake.json')
endfunction

function s:cmake_pick_target()
  call s:parse_codemodel_json_with_completion(function('s:_do_cmake_pick_target'))
endf

function s:cmake_pick_executable_target()
  call s:parse_codemodel_json_with_completion(function('s:_do_cmake_pick_executable_target'))
endf

function s:get_execs_from_name_relative_pairs()
  let l:filtered = filter(s:get_name_relative_pairs(), "v:val.is_exec")
endfunction

function s:_do_cmake_pick_executable_target()
  call s:cmake_get_target_and_run_action(s:get_execs_from_name_relative_pairs(), 's:select_target')
  call s:dump_current_target()
endfunction

function s:_do_cmake_pick_target()
  call s:cmake_get_target_and_run_action(s:get_name_relative_pairs(), 's:select_target')
  call s:dump_current_target()
endfunction

function s:cmake_close_windows()
  call s:close_last_window_if_open()
  call s:close_last_buffer_if_open()
endf

function s:close_last_window_if_open()
  if s:check_if_window_is_alive(g:cmake_last_window)
    call nvim_win_close(g:cmake_last_window, v:true)
  endif
endf

function s:close_last_buffer_if_open()
  if s:check_if_buffer_is_alive(g:cmake_last_buffer)
    call nvim_buf_delete(g:cmake_last_buffer, {"force": v:true})
  endif
endf

function s:_run_current_target(job_id, exit_code, event)
  call s:close_last_window_if_open()
  if a:exit_code == 0
    call s:get_only_window()
    exe "terminal \"" . s:get_cmake_target_file() . "\" " . s:get_cmake_target_args()
  endif
  let g:vim_cmake_build_tool = g:vim_cmake_build_tool_old
endf

function s:_update_target_and_run(target)
  " echom "_update_target_and_run(" . a:target . ")"
  call s:select_target(a:target)
  call s:_do_run_current_target()
endfunction

function s:_do_run_current_target()
  " echom "_do_run_current_target() with s:get_cmake_target_file() = " . s:get_cmake_target_file()
  if s:get_cmake_target_file() == '' || s:get_cmake_target_file() == v:null
    " because vimscript doesn't have asynch the below just recursively calls this
    call s:cmake_get_target_and_run_action(s:get_execs_from_name_relative_pairs(), 's:_update_target_and_run')
    return
  endif
  if g:vim_cmake_build_tool != "vsplit"
    let g:vim_cmake_build_tool_old = g:vim_cmake_build_tool
    let g:vim_cmake_build_tool = "vsplit"
  else
    let g:vim_cmake_build_tool_old = g:vim_cmake_build_tool
  endif
  call s:cmake_build_current_target_with_completion(function("s:_run_current_target"))
endfunction

function s:cmake_run_current_target()
  " echom "s:cmake_run_current_target()"
  call s:parse_codemodel_json_with_completion(function("s:_do_run_current_target"))
endfunction

function s:select_target(target_name)
  call s:add_cmake_target_to_target_list(a:target_name)

  let l:file = s:get_cmake_build_dir() . '/' . g:tar_to_relative[a:target_name]
  call s:set_cmake_target_file(l:file)

  call s:write_cache_file()
endfunction

function s:dump_current_target()
  echo "Current target set to '" . s:get_cmake_target_file() . "' with args '" . s:get_cmake_target_args() . "'"
endfunction

function s:cmake_run_target_with_name(target)
  let s:cmake_target_file = s:get_cmake_build_dir() . '/' . g:tar_to_relative[a:target]
  try
    exec '!cmake --build ' . s:get_cmake_build_dir() . ' --target ' . a:target
  catch /.*/
    echo 'Failed to build ' . a:target
  finally
    call s:get_only_window()
    exe "terminal " . s:cmake_target
  endtry
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
    let &makeprg = s:get_state().build_command
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

  call s:close_last_window_if_open()
  call s:close_last_buffer_if_open()

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

  call s:close_last_window_if_open()
  call s:close_last_buffer_if_open()

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
  call s:write_cache_file()
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

  call s:close_last_window_if_open()
  call s:close_last_buffer_if_open()

  if exists('l:init_file')
    let l:lldb_init_arg = ' /tmp/lldbinitvimcmake '
  else
    let l:lldb_init_arg = ''
  endif
  exec 'DebugLldb ' . s:get_cmake_target_file() . ' --lldbinit ' . l:lldb_init_arg . ' -- ' . s:get_cmake_target_args()
endfunction

function s:cmake_debug_current_target_nvim_dap_lldb_vscode()
  let l:state = s:get_state()
  let l:state.debugger = 'nvim_dap_lldb_vscode'
  call s:cmake_debug_current_target()
endf

function s:cmake_debug_current_target_lldb()
  let l:state = s:get_state()
  let l:state.debugger = 'lldb'
  call s:cmake_debug_current_target()
endf

function s:cmake_debug_current_target_gdb()
  let l:state = s:get_state()
  let l:state.debugger = 'gdb'
  call s:cmake_debug_current_target()
endf

function s:cmake_debug_current_target()
  call s:parse_codemodel_json_with_completion(function("s:_do_debug_current_target"))
endfunction

function s:_do_debug_current_target()
  if s:get_cmake_target_file() == v:null
    call s:cmake_get_target_and_run_action(s:get_execs_from_namae_relative_pairs(), 's:update_target')
  endif

  if s:get_state().debugger ==? 'gdb'
    call s:cmake_build_current_target_with_completion(function('s:start_gdb'))
  elseif s:get_state().debugger ==? 'lldb'
    call s:cmake_build_current_target_with_completion(function('s:start_lldb'))
  else
    call s:cmake_build_current_target_with_completion(function('s:start_nvim_dap_lldb_vscode'))
  endif
endfunction

function s:cmake_set_cmake_args(...)
  let l:arguments = a:000
  call s:set_cmake_arguments(l:arguments)
  call s:write_cache_file()
endfunction

function g:GetCMakeArgs()
  return s:get_cmake_arguments()
endfunction

function s:cmake_set_current_target_run_args(args)
  if s:get_cmake_target_file() ==? v:null
    call s:cmake_get_target_and_run_action(s:get_name_relative_pairs(), 's:update_target')
    return
  endif
  call s:set_cmake_target_args(a:args)
  call s:write_cache_file()
  call s:dump_current_target()
endfunction

function g:GetCMakeCurrentTargetRunArgs()
  let c = s:get_cmake_single_target_cache()
  call s:set_if_empty(c, "args", "")
  return c.args
endfunction

function s:get_cmake_single_target_cache()
  let c = v:lua.require("cmake").get_cmake_targets_object()
  call s:set_if_empty(c, s:get_cmake_target_file(), {})
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
  call s:write_cache_file()
endfunction

function s:cmake_update_source_dir(...)
  let dir = a:1
  call s:set_cmake_source_dir(dir)
  call s:write_cache_file()
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

function s:run_lit_on_file()
  let l:full_path = expand("%:p")
  if filereadable(s:get_cmake_build_dir() . "/bin/llvm-lit")
    let l:lit_path = s:get_cmake_build_dir() . "/bin/llvm-lit"
  else
    let l:lit_path = "llvm-lit"
  endif
  call s:get_only_window()
  call termopen([l:lit_path, s:get_state().extra_lit_args, l:full_path])
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

command! -nargs=0 CMakePickTarget call s:cmake_pick_target()
command! -nargs=0 CMakePickExecutableTarget call s:cmake_pick_executable_target()
command! -nargs=0 CMakeRunCurrentTarget call s:cmake_run_current_target()
command! -nargs=* -complete=shellcmd CMakeSetCurrentTargetRunArgs call s:cmake_set_current_target_run_args(<q-args>)
command! -nargs=? -complete=customlist,s:get_build_tools CMakeBuildCurrentTarget call s:cmake_build_current_target(<f-args>)

command! -nargs=1 -complete=shellcmd CMakeClean call s:cmake_clean()
command! -nargs=0 CMakeBuildAll call s:cmake_build_all()

command! -nargs=0 CMakeToggleFileLineColumnBreakpoint call s:toggle_file_line_column_breakpoint()
command! -nargs=0 CMakeToggleFileLineBreakpoint call s:toggle_file_line_breakpoint()
command! -nargs=0 CMakeListBreakpoints call g:CMake_list_breakpoints()
command! -nargs=0 CMakeToggleBreakAtMain call s:toggle_break_at_main()

command! -nargs=* -complete=shellcmd CMakeCreateFile call s:cmake_create_file(<f-args>)

command! -nargs=1 -complete=shellcmd CMakeCloseWindow call s:cmake_close_windows()

command! -nargs=0 CMakeRunLitOnFile call s:run_lit_on_file()

command! -nargs=0 CMakeLoad call s:cmake_load()

command! CMakeEditCurrentTargetRunArgs call feedkeys(":CMakeSetCurrentTargetRunArgs " . eval("g:GetCMakeCurrentTargetRunArgs()"))
command! CMakeEditCMakeArgs call feedkeys(":CMakeSetCMakeArgs " . eval("join(g:GetCMakeArgs(), ' ')"))
command! CMakeEditBuildDir call feedkeys(":CMakeSetBuildDir " . eval("g:GetCMakeBuildDir()"))
command! CMakeEditSourceDir call feedkeys(":CMakeSetSourceDir " . eval("g:GetCMakeSourceDir()"))


