A simple CMake addon for neovim

Provides these commands:
* CMakeSetBuildDir
    * Obvious
* CMakeSetSourceDir
    * Obvious
* CMakeArgs
    * Poorly named and implemented command that sets the args for the
      cmake invocation
* CMakeTargetArgs
    * Poorly named and implemented command that sets the args for the
      currently selected command for use with CMakeRun
* CMakeCompileFile
    * Broken?
* CMakeDebug
    * Select a target to launch in the nvim-gdb debugger --
        https://github.com/sakhnik/nvim-gdb
* CMakeRunCurrentTarget
* CMakeRunTarget
* CMakePickTarget
* CMakeBuild
* CMakeBuildTarget
* CMakeBuildNonArtifacts
* CMakeConfigureAndGenerate
* CMDBConfigureAndGenerate
* CMakeBreakpoints
* CMakeSyncCompileCommands
* CMakeRunTests
* CMakeRerunFailedTests
* CMakeShowDiagnostics

Set `g:cmake_auto_sync_compile_commands = true` to copy or link the `compile_commands.json`
from the active build directory into the source tree after configure/generate. Override
the behavior with `g:cmake_compile_commands_sync_method = "copy"` if symlinks are not
desirable.

Use `:lua require('cmake.tui').toggle()` to open the target browser. Filter targets with
`f`/`F` to cycle or `a`/`e`/`l`/`t` for direct selection, and trigger actions on the
highlighted target with `b` (build), `r` (run), or `d` (debug).

Surface build/configure progress in your statusline via
`%{v:lua.require('cmake').statusline()}`, and watch for inline virtual-text updates on the
active buffer as commands complete.

## Statusline integration

To display the current CMake state in lualine, add the statusline function as a custom
component inside your `lualine.setup` call:

```lua
require('lualine').setup({
  sections = {
    lualine_c = {
      'filename',
      function()
        return require('cmake').statusline()
      end,
    },
  },
})
```

Place the component in whichever section works for your layout; the helper returns an
empty string when idle so it will not clutter your statusline.

Run the project's CTest suite with `:CMakeRunTests`; failures populate the quickfix list
and are highlighted in the statusline. Use `:CMakeRerunFailedTests` to retry only the most
recently failing cases (leveraging `ctest --rerun-failed`). Configure the executable and
extra arguments with `g:cmake_ctest_executable` and `g:cmake_ctest_args` if needed.

Inspect the most recent build's diagnostics with `:CMakeShowDiagnostics`. Detected GCC
/ Clang / MSVC-style errors and warnings are listed alongside a tail of the raw log, and
errors populate the quickfix list automatically when present.
