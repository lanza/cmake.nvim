# cmake.nvim

CMake integration for Neovim.

## Features

- Configure and build CMake projects
- Target selection and management
- Debugger integration (GDB, LLDB, nvim-dap)
- CTest integration
- Build diagnostics with quickfix support
- Interactive TUI for target browsing
- Statusline integration
- Automatic compile_commands.json sync

## Commands

### Configuration
- `:CMakeSetBuildDir <dir>` - Set build directory
- `:CMakeSetSourceDir <dir>` - Set source directory
- `:CMakeSetCMakeArgs <args>` - Set CMake arguments
- `:CMakeConfigureAndGenerate` - Run CMake configuration

### Building
- `:CMakeBuildCurrentTarget` - Build selected target
- `:CMakeBuildAll` - Build all targets
- `:CMakeClean` - Clean build artifacts

### Targets
- `:CMakePickTarget` - Select a build target
- `:CMakePickExecutableTarget` - Select an executable target
- `:CMakeRunCurrentTarget` - Build and run selected target
- `:CMakeSetCurrentTargetRunArgs <args>` - Set runtime arguments

### Testing
- `:CMakeRunTests` - Run CTest suite
- `:CMakeRerunFailedTests` - Rerun failed tests only

### Debugging
- `:CMakeDebugWithNvimGDB` - Debug with GDB
- `:CMakeDebugWithNvimLLDB` - Debug with LLDB
- `:CMakeDebugWithNvimDapLLDBVSCode` - Debug with nvim-dap
- `:CMakeToggleFileLineBreakpoint` - Toggle breakpoint at cursor
- `:CMakeToggleFileLineColumnBreakpoint` - Toggle column-specific breakpoint
- `:CMakeListBreakpoints` - List all breakpoints
- `:CMakeToggleBreakAtMain` - Toggle break-at-main behavior

### Diagnostics
- `:CMakeShowDiagnostics` - Show build diagnostics and errors
- `:CMakeSyncCompileCommands` - Sync compile_commands.json to source dir

## Setup

```lua
require('cmake').setup({
  build_tool = "vsplit",           -- "vsplit" or "vim-dispatch"
  default_build_dir = "build",
  global_cache_file = vim.env.HOME .. "/.cmake.nvim.json",
})
```

## Target Browser (TUI)

Open with `:lua require('cmake.tui').toggle()`

Keybindings:
- `f`/`F` - Cycle through filter modes
- `a` - Show all targets
- `e` - Show executable targets
- `l` - Show library targets
- `t` - Show test targets
- `b` - Build highlighted target
- `r` - Run highlighted target
- `d` - Debug highlighted target

## Statusline Integration

Add to your statusline or lualine:

```lua
require('cmake').statusline()
```

Example with lualine:

```lua
require('lualine').setup({
  sections = {
    lualine_c = {
      'filename',
      function() return require('cmake').statusline() end,
    },
  },
})
```

## Compile Commands

Set `g:cmake_auto_sync_compile_commands = true` to automatically sync `compile_commands.json` from build directory to source tree after configuration.

Override sync method with `g:cmake_compile_commands_sync_method = "copy"` (default is symlink).

## Configuration Options

- `g:cmake_auto_sync_compile_commands` - Auto-sync compile_commands.json (default: false)
- `g:cmake_compile_commands_sync_method` - Sync method: "symlink" or "copy" (default: "symlink")
- `g:cmake_ctest_executable` - CTest executable path (default: "ctest")
- `g:cmake_ctest_args` - Additional CTest arguments

## Cache File

Per-project settings (targets, args, directories) are stored in `~/.cmake.nvim.json` by default. Override with the `global_cache_file` setup option.
