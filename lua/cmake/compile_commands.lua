local uv = vim.loop

local M = {}

local function is_absolute(path)
  return vim.startswith(path or "", "/")
end

local function to_absolute_path(path)
  if path == nil or path == "" then
    return vim.fn.getcwd()
  end
  if is_absolute(path) then
    return path
  end
  return vim.fn.getcwd() .. "/" .. path
end

local function unlink_if_exists(path)
  local stat = uv.fs_lstat(path)
  if stat then
    local ok = uv.fs_unlink(path)
    if not ok then
      vim.fn.delete(path)
    end
    return
  end
  if vim.fn.filereadable(path) == 1 then
    vim.fn.delete(path)
  end
end

local function status(prefix)
  return function(message)
    print("cmake.nvim: " .. prefix .. message)
  end
end

local info = status("")
local warn = status("warning: ")

function M.sync(build_dir, source_dir, opts)
  opts = opts or {}
  local method = opts.method or vim.g.cmake_compile_commands_sync_method or "link"

  local build_root = to_absolute_path(build_dir)
  local source_root = to_absolute_path(source_dir)
  local compile_commands = build_root .. "/compile_commands.json"

  if vim.fn.filereadable(compile_commands) == 0 then
    warn("compile_commands.json not found at " .. compile_commands)
    return false
  end

  local destination = source_root .. "/compile_commands.json"
  unlink_if_exists(destination)

  if method == "copy" or vim.fn.has("win32") == 1 then
    local ok, err = uv.fs_copyfile(compile_commands, destination)
    if not ok then
      warn("failed to copy compile_commands.json: " .. (err or "unknown error"))
      return false
    end
    info("copied compile_commands.json from " .. compile_commands)
    return true
  end

  local ok, err = uv.fs_symlink(compile_commands, destination)
  if not ok then
    local fallback_ok, fallback_err = uv.fs_copyfile(compile_commands, destination)
    if not fallback_ok then
      warn(string.format(
        "failed to link compile_commands.json (%s) and fallback copy failed (%s)",
        err or "unknown error",
        fallback_err or "unknown error"
      ))
      return false
    end
    info("symlink failed (" .. (err or "unknown error") .. "), copied compile_commands.json instead")
    return true
  end

  info("linked compile_commands.json from " .. compile_commands)
  return true
end

function M.auto_sync(build_dir, source_dir)
  if not vim.g.cmake_auto_sync_compile_commands then
    return true
  end
  return M.sync(build_dir, source_dir)
end

return M
