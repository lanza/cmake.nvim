# Repository Guidelines

## Project Structure & Module Organization
The plugin lives under `lua/cmake/` and follows Neovim's runtime layout. `lua/cmake/init.lua` owns state management for build directories, targets, breakpoint storage, and registers all `:CMake*` user commands. `lua/cmake/ui.lua` and `lua/cmake/tui.lua` provide the split-based interfaces used by build output and the target browser. Keep helpers close to their callers; shared utilities belong in `lua/cmake/init.lua` until the module surface grows.

## Build, Test, and Development Commands
- `nvim --clean --cmd "set rtp^=$(pwd)" -c "lua require('cmake').setup({})" +qa` verifies the plugin loads without errors.
- `nvim --clean --cmd "set rtp^=$(pwd)" -c "cd path/to/cmake/project" -c "CMakeConfigureAndGenerate" -c "qa"` runs configuration against a sample project.
- During interactive debugging, call `:lua require('cmake.tui').toggle()` to inspect target metadata, then drive builds with `:CMakeBuildCurrentTarget`.

## Coding Style & Naming Conventions
The `.luarc.json` enforces two-space indentation and an 80-character margin; mirror that when formatting. Follow Neovim Lua idioms: prefer `vim.api`, `vim.fn`, and `vim.tbl_*` helpers over raw `vim` globals. Public user commands keep the `CMake*` prefix; internal functions use snake_case verbs such as `cmake_build_current_target`. Avoid introducing new globals; mutate the shared `M.state` table instead.

## Testing Guidelines
We do not have automated tests today; rely on manual validation. Exercise the primary flow—`:CMakeConfigureAndGenerate`, `:CMakePickTarget`, `:CMakeBuildCurrentTarget`, and `:CMakeRunCurrentTarget`—inside a known-good CMake project. Validate the debugger adapters by toggling `:CMakeDebugWithNvimGDB` or `:CMakeDebugWithNvimLLDB` and confirming breakpoints persist via `:CMakeListBreakpoints`. Capture the Neovim `:messages` output when reporting regressions.

## Commit & Pull Request Guidelines
Commits follow conventional prefixes (`feat:`, `fix:`, `refactor:`) as seen in the history; keep subject lines under 72 characters. Squash trivial fixups before opening a PR. Each PR should summarize scope, list the Neovim commands exercised during manual testing, and link any tracked issues. Include screenshots or terminal captures when UI changes affect the TUI panel layout.

## Configuration Tips
Tune behavior via globals: `g:cmake_build_tool` defaults to `vsplit` but accepts `vim-dispatch`. Use `g:cmake_cache_file_path` to point at an alternative cache, and `g:cmake_template_file` to bootstrap missing `CMakeLists.txt`. Document new globals in `README.md` when adding them.
