" cmake.vim - Vim plugin to create a CMake project system
" Maintainer: Nathan Lanza <https://github.com/lanza>
" Version:    0.2

if exists('g:loaded_vim_cmake')
  finish
else
  let g:loaded_vim_cmake = 1
endif

" this needs to be wrapped due to the need to use on_exit to pipeline the config
function g:cmake#ParseCodeModelJson()
  let l:build_dir = v:lua.require("cmake").get_cmake_build_dir()
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

" TODO: Fix this breakpoint handling
function s:start_gdb(job_id, exit_code, event)
  if a:exit_code != 0
    return
  endif
  let l:commands = ['b main', 'r']
  let l:data = v:lua.require("cmake").get_cmake_cache_file()
  if has_key(l:data, getcwd())
    let l:dir = l:data[getcwd()]['targets']
    if has_key(l:dir, v:lua.require("cmake").get_cmake_build_dir() . '/' . v:lua.require("cmake").get_cmake_target_file())
      let l:target = l:dir[v:lua.require("cmake").get_cmake_build_dir() . '/' . v:lua.require("cmake").get_cmake_target_file()]
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
  let l:exec = 'GdbStart gdb -q ' . l:gdb_init_arg . ' --args ' . v:lua.require("cmake").get_cmake_target_file() . " " . v:lua.require("cmake").get_cmake_target_args()
  " echom l:exec
  exec l:exec
endfunction

" TODO: Fix this breakpoint handling
function s:start_nvim_dap_lldb_vscode(job_id, exit_code, event)
  if a:exit_code != 0
    return
  endif
  let l:commands = ["breakpoint set --func-regex '^main$'", 'r']
  let l:data = v:lua.require("cmake").get_cmake_cache_file()
  if has_key(l:data, getcwd())
    let l:dir = l:data[getcwd()]['targets']
    if has_key(l:dir, v:lua.require("cmake").get_cmake_build_dir() . '/' . v:lua.require("cmake").get_cmake_target_file())
      let l:target = l:dir[v:lua.require("cmake").get_cmake_build_dir() . '/' . v:lua.require("cmake").get_cmake_target_file()]
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
  exec 'DebugLldb ' . v:lua.require("cmake").get_cmake_target_file() . ' --lldbinit ' . l:lldb_init_arg . ' -- ' . v:lua.require("cmake").get_cmake_target_args()
endfunction

