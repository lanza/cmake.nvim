local M = {}

--- Ensures that object[key] has a default value.
--- If object[key] is nil, sets it to val, then returns it.
---@param object table The table to modify
---@param key any The key to check in the table
---@param val any The default value to assign if key is missing
---@return any The value at object[key] after ensuring it's set
function M.set_if_empty(object, key, val)
  if object[key] == nil then
    object[key] = val
  end
  return object
end

M.state = {
  cmake_tool = "cmake",
  cache_file_path = vim.env.HOME .. "/.vim_cmake.json",
  generator = "Ninja",
  build_command = "ninja",
  template_file = vim.fn.expand(":p:h:h" .. "/CMakeLists.txt"),
  cache_object = nil,
  dir_cache_object = nil,
}

function M.set_dco(key, value)
  M.state.dir_cache_object[key] = value
end

function M.get_dco(key)
  return M.state.dir_cache_object[key]
end

function M.get_current_target_file()
  return M.state.dir_cache_object.current_target_file
end

function M.add_dco_target_if_new(name, target_object)
  -- print(vim.inspect(M.get_dco("targets")))
  if M.state.dir_cache_object.targets[name] ~= nil then
    return
  end
  if target_object.args ~= nil then
    target_object.args = ""
  end
  M.state.dir_cache_object.targets[name] = target_object
  -- print(vim.inspect(M.get_dco("targets")))
end

function M.set_ctco(key, value)
  -- print("Before: " .. vim.inspect(M.state.current_target_cache_object))
  M.state.current_target_cache_object[key] = value
  -- print("After: " .. vim.inspect(M.state.current_target_cache_object))
  -- print("DCO: " .. vim.inspect(M.state.dir_cache_object))
  -- print("CO: " .. vim.inspect(M.state.cache_object["/private/tmp/g4f8"]))
end

function M.get_ctco(key)
  return M.state.current_target_cache_object[key]
end

function M.set_dco_if_empty(key, value)
  if M.state.dir_cache_object[key] == nil then
    M.state.dir_cache_object[key] = value
  end
end

function M.get_state(key)
  return M.state[key]
end

function M.bind_dco()
  M.state.dir_cache_object = M.state.cache_object[vim.fn.getcwd()]
end

function M.bind_ctco()
  local ctf = M.state.dir_cache_object.current_target_file
  M.state.current_target_cache_object = M.state.dir_cache_object.targets[ctf]
end

function M.set_state(key, value)
  M.state[key] = value
end

function M.write_cache_file()
  local cache_file = M.state.cache_object
  local serial = vim.fn.json_encode(cache_file)
  local split = vim.fn.split(serial, "\n")
  vim.fn.writefile(split, vim.env.HOME .. "/.vim_cmake.json")
end

function M.set_state_child(key, child, value)
  -- print("Before: " .. vim.inspect(M.state[key]))
  if M.state[key] == nil then
    M.state[key] = {}
  end
  M.state[key][child] = value
  -- print("After: " .. vim.inspect(M.state[key]))
  -- print("DCO: " .. vim.inspect(M.state.dir_cache_object))
  -- print("CO: " .. vim.inspect(M.state.cache_object["/private/tmp/g4f8"]))
end

function M.add_name_relative_pair(name, is_exec, is_artifact, relative)
  table.insert(M.state.dir_cache_object.name_relative_pairs, {
    name = name,
    relative = relative,
    is_exec = is_exec,
    is_artifact = is_artifact,
  })
end

function M.setup(opts) end

return M
