# Repository Guidelines

## Project Structure & Module Organization
The plugin lives under `lua/cmake/` and follows Neovim's runtime layout. `lua/cmake/init.lua` wires Neovim commands and delegates to feature modules: `compile_commands.lua` for database sync, `status.lua` for statusline + virtual text, `test_runner.lua` for CTest integration, `diagnostics.lua` for build parsing, and `tui.lua`/`tui_extras.lua` for the target browser. Keep new behavior in standalone modules and only touch `init.lua` to register commands or callbacks.

## Build, Test, and Development Commands
- `nvim --clean --cmd "set rtp^=$(pwd)" -c "lua require('cmake').setup({})" +qa` verifies the plugin loads without errors.
- `nvim --clean --cmd "set rtp^=$(pwd)" -c "cd path/to/cmake/project" -c "CMakeConfigureAndGenerate" -c "qa"` runs configuration against a sample project.
- Use `:lua require('cmake').statusline()` inside your statusline plugin to surface configure/build/test state, and rely on the inline virtual-text notifications for quick context.
- Drive flows from the target browser with `:lua require('cmake.tui').toggle()`, then build via `:CMakeBuildCurrentTarget`, run with `:CMakeRunCurrentTarget`, run tests with `:CMakeRunTests`, and inspect failures through `:CMakeShowDiagnostics`.

## Coding Style & Naming Conventions
The `.luarc.json` enforces two-space indentation and an 80-character margin; mirror that when formatting. Prefer Neovim helpers (`vim.api`, `vim.fn`, `vim.loop`) over raw globals. Public user commands keep the `CMake*` prefix; internal helpers use snake_case verbs such as `cmake_build_current_target`. When adding features, create a dedicated module and expose a narrow API so `init.lua` remains a dispatcher. Avoid introducing new globals—prefer module-level state or the existing `M.state` table.

## Testing Guidelines
We do not have automated tests; rely on manual validation against a real CMake project. Cover configure (`:CMakeConfigureAndGenerate`), target selection, build, run, and debugger flows. Exercise the new integrations: ensure `:CMakeRunTests` populates the quickfix list, `:CMakeRerunFailedTests` replays failures, and `:CMakeShowDiagnostics` reflects compiler output with accurate file/line links. Capture `:messages` plus the diagnostics buffer when reporting regressions.

## Commit & Pull Request Guidelines
Commits follow conventional prefixes (`feat:`, `fix:`, `refactor:`); keep subject lines under 72 characters and group related module work together. Squash trivial fixups before opening a PR. Each PR should summarize scope, list the Neovim commands exercised during manual testing (configure/build/tests/diagnostics as applicable), and link any tracked issues. Include screenshots or terminal captures when UI changes affect the TUI panel layout. Update `FEATURE_PROGRESS.md` when a roadmap item lands.

## Configuration Tips
Key globals include `g:cmake_build_tool` (`vsplit` or `vim-dispatch`), `g:cmake_auto_sync_compile_commands`, `g:cmake_compile_commands_sync_method`, and the test knobs `g:cmake_ctest_executable`/`g:cmake_ctest_args`. Set `g:cmake_default_debugger` to choose the default debugger. Use `g:cmake_cache_file_path` for an alternate cache and `g:cmake_template_file` to bootstrap missing `CMakeLists.txt`. Document any new options in `README.md` and keep module help text in sync.
