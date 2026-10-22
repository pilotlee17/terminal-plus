# Changelog

## 0.8.0 — 2026-10-22

First public Terminal+ release.

- Native macOS terminal panes with ordinary zsh sessions and no project or AI-tool requirement.
- Immediate pane creation, current-directory inheritance, adaptive splits and one-click arrangement; up to eight visible terminals.
- Header dragging with center swap and directional drop previews.
- Rectangle selection, Shift-add selection, select all and confirmed batch close.
- Double-click header to focus; double-click divider to equalize.
- Up to 30 layout undo/redo steps for dragging, divider adjustments and arrangement.
- Closing a pane selects its visual neighbor and never restores a terminated session through layout undo.
- Persistent layout and reconnect to surviving tmux processes after application exit.
- Corrupt-layout backup and protection against overwriting the source if backup fails.
- Isolated controller/session integration tests, PTY smoke checks and reproducible verification script.

### Distribution

Apple Silicon build; ad-hoc signed, not notarized. tmux must be installed separately. macOS 13 is the declared minimum; release validation was performed on macOS 27 with Swift 6.4. Intel and older macOS versions have not been validated.
