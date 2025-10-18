# Repository Guidelines

## Project Structure & Module Organization
- Core plugin lives in `lua/cmake/` following Neovim runtime layout.
- `lua/cmake/init.lua` wires user commands; feature logic stays in dedicated modules such as `compile_commands.lua`, `status.lua`, `test_runner.lua`, `diagnostics.lua`, `tui.lua`, and `tui_extras.lua`.
- Keep new functionality in standalone modules and avoid introducing globals—reuse the shared `M.state` table for persistent data.
- Place sample assets or scripts under `scripts/` if you add them; there is no separate automated test suite directory today.

## Build, Test, and Development Commands
- `nvim --clean --cmd "set rtp^=$(pwd)" -c "lua require('cmake').setup({})" +qa` — verify the plugin loads without runtime errors.
- `nvim --clean --cmd "set rtp^=$(pwd)" -c "cd path/to/cmake/project" -c "CMakeConfigureAndGenerate" -c "qa"` — smoke-test configure and generation against a sample project.
- Inside Neovim, drive flows with `:lua require('cmake.tui').toggle()`, then `:CMakeBuildCurrentTarget`, `:CMakeRunCurrentTarget`, `:CMakeRunTests`, and `:CMakeShowDiagnostics` to validate integrations.

## Coding Style & Naming Conventions
- Follow `.luarc.json`: two-space indentation, 80-character margin, Lua runtime semantics.
- Prefer `vim.api`, `vim.fn`, and `vim.loop` helpers; avoid raw global functions.
- Public commands use the `CMake*` prefix (e.g., `:CMakeBuildCurrentTarget`), while internal helpers use snake_case verbs such as `cmake_build_current_target`.
- Add succinct comments only when the intent is not obvious; keep modules single-purpose.

## Testing Guidelines
- No automated tests: validate manually on a real CMake project.
- Exercise configure, target selection, build, run, and test flows; confirm `:CMakeRunTests` fills the quickfix list and `:CMakeRerunFailedTests` replays failures.
- Capture `:messages` and the diagnostics buffer when documenting regressions; ensure virtual text and statusline state match the latest operation.

## Commit & Pull Request Guidelines
- Use Conventional Commits such as `feat:`, `fix:`, or `refactor:` with subjects under 72 characters; squash trivial fixups.
- PRs should summarize scope, list Neovim commands exercised during manual validation, link relevant issues, and include screenshots or terminal captures for TUI changes.
- Update `FEATURE_PROGRESS.md` when landing roadmap items; group related module work into the same PR.

## Configuration Tips
- Key globals: `g:cmake_build_tool`, `g:cmake_auto_sync_compile_commands`, `g:cmake_compile_commands_sync_method`, `g:cmake_ctest_executable`, `g:cmake_ctest_args`, `g:cmake_default_debugger`, `g:cmake_cache_file_path`, and `g:cmake_template_file`.
- Document new options in `README.md` and mirror help text inside the relevant module when adding settings.
