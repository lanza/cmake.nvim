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

Set `g:cmake_auto_sync_compile_commands = true` to copy or link the `compile_commands.json`
from the active build directory into the source tree after configure/generate. Override
the behavior with `g:cmake_compile_commands_sync_method = "copy"` if symlinks are not
desirable.
