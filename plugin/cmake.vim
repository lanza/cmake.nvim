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
