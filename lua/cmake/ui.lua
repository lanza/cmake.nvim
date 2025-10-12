local M = {}

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

function M.cmake_close_windows()
  M.close_last_window_if_open()
  M.close_last_buffer_if_open()
end

function M.setup(opts)
  vim.g.cmake_last_window = nil
  vim.g.cmake_last_buffer = nil
end

return M
