# Release verification — 0.8.0

Date: 2026-10-22. Environment: Apple Silicon, macOS 27, Swift 6.4, Homebrew tmux. The package requires Swift 6.2+ and intentionally uses Swift 5 language mode for its existing AppKit/GCD implementation.

## Reproduce

```bash
brew install tmux
bash scripts/verify.sh
bash scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 'dist/Terminal+.app'
```

AppKit integration tests require a logged-in macOS desktop session. Tests use temporary directories and UUID-named tmux sockets, never the production application socket. Missing tmux causes the verification script to fail before running tests.

## Automated result

37 XCTest cases passed, zero failures: 21 core tests and 16 AppKit/session integration tests. Four real PTY smoke-check groups also passed. Swift Testing may additionally print “0 tests”; this does not replace the XCTest totals.

| Area | Exercised checks | Result |
| --- | --- | --- |
| Creation | Plain shell without Git, create seven additional panes rapidly, eight-pane cap, immediate state insertion, actual cwd after `cd`, eight attached clients on the correct socket | Pass |
| Layout | One through eight panes, narrow/portrait canvases, order and identity invariants, recursive minimum sizes, resize at 900×440 and 1800×1000 | Pass |
| Dragging | Center swap and four edge placements, all source/target pairs in a nested layout, preview geometry, drag threshold, cancellation, button hit testing | Pass |
| Selection | Rectangle intersection, individual toggle, Shift-add selection, locked selection, empty gap | Pass |
| Close | Close selected subset, exact session targeting, survivor PID unchanged, last pane/empty state, pending-create close race, reopen after all closed | Pass |
| Layout history | Undo/redo, no-op handling, 30-entry bound, no revival of closed panes, focus follows visual neighbor | Pass |
| View reuse | Existing terminal views survive arrangement, zoom, selection and resizing | Pass |
| Persistence | JSON round trips, legacy migration, reopen preserves shell PID, invalid/duplicate split IDs and ratios rejected, corrupt layout backed up | Pass |
| Error handling | Missing directory, process timeout and escalation, large output, inherited pipes do not block next control command | Pass |
| PTY | Unicode, literal quoted/metacharacter paths, independent input/output, terminal resize, detach preserves process and scrollback | Pass |
| Legacy compatibility | Historical worktree model tests retained; current application does not invoke worktree operations | Pass |

Seven synchronous pane insertions took approximately 0.14 seconds in the final local test. This measures model/view insertion on this machine, not shell readiness, animation frame rate or a cross-device performance guarantee.

## Native release and package checks

- Release 0.8.0 built successfully; strict/deep code-signature verification passed.
- Native menu and keyboard checks: Arrange → undo restored the saved layout exactly; redo reapplied the arrangement; undo restored the original view.
- The release ZIP was extracted outside the repository and the extracted app launched successfully, reconnecting the seven visible panes.
- All 12 pre-existing session names and shell PIDs were unchanged through app restarts and layout checks.
- The archive contains only the app, bundled license/NOTICE files and its signature. It contains no session snapshots or build directories.
- Public source files and every bundle file were checked for local home paths; debug paths are stripped from the shipped executable. A credential-pattern scan found no matching secrets in the source allowlist.
- SHA-256 is included alongside the ZIP. The app links only system frameworks/libraries; tmux remains an external executable.

## Boundaries

- The declared deployment target is macOS 13; this release has only been run on Apple Silicon/macOS 27. Intel and older supported macOS versions have not been validated.
- macOS reboot destroys tmux processes; persistence reconnects live sessions after application exit, not across an OS restart.
- No automated visual golden-image comparison, prolonged soak, accessibility audit or full IME compatibility matrix was run.
- Corrupt-layout backup success is tested. The backup-failure guard was code-reviewed; filesystem permission-denial injection was not run.
- tmux is an external prerequisite. This release is ad-hoc signed and not notarized.
- Private local logs, session snapshots and screenshots are excluded from the public repository. Only this sanitized report is published.
