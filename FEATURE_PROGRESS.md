# TUI Revamp Ideas

- **Segmented layout:** Split the window into a headline bar (project + preset),
  a scrollable target grid, and a contextual detail pane so users can skim and
  inspect without leaving the view.
- **Visual hierarchy:** Apply dedicated highlight groups for status
  (configure/build/test), dim inactive targets, and use color-coded badges to
  flag runnable, failing, or cached targets.
- **Iconography with fallbacks:** Render Nerd Font glyphs for build/test/debug
  actions and fall back to ASCII when unavailable; pair them with aligned
  columns to reduce clutter.
- **Interactive key hints:** Keep a footer ribbon that lists dynamic keybinds
  (e.g., `b` Build, `r` Run, `d` Debug, `/` Filter) and update it based on focus
  for discoverability.
- **Context panel:** Show current target’s commands, last exit code, timing, and
  artifact paths in a right-side pane; include quick toggles for `args`, `env`,
  and `cwd`.
- **Real-time progress bars:** Use inline ASCII progress bars or spinner widgets
  during long builds/tests, with timestamps and elapsed time readouts.
- **Theme adaptability:** Respect `vim.o.background`, expose a `tui.theme`
  option, and let users override highlight groups for light/dark palettes.
- **Compact notifications:** Replace verbose log lines with concise toast-style
  overlays inside the TUI, expandable with a single key for full logs.
