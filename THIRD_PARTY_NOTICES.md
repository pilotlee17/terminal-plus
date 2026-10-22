# Third-party notices

Dependency versions and revisions are pinned in `Package.resolved`.

| Dependency | License | Usage |
| --- | --- | --- |
| [SwiftTerm 1.99.1](https://github.com/migueldeicaza/SwiftTerm) | MIT | Terminal rendering and local PTY client |
| [swift-png 4.5.1](https://github.com/tayloraswift/swift-png) | Apache-2.0 | SwiftTerm dependency; portable graphics |
| [h 1.0.1](https://github.com/rarestype/h) | Apache-2.0 | Transitive dependency |
| [swift-argument-parser 1.8.2](https://github.com/apple/swift-argument-parser) | Apache-2.0 | Tooling pin; not compiled or bundled in this macOS app |

Full bundled dependency license texts and available NOTICE files are copied from the resolved checkouts into `Terminal+.app/Contents/Resources/Licenses` by the build script. SwiftTerm's license includes its upstream xterm.js attribution. No dependency sources are modified.

[tmux](https://github.com/tmux/tmux) is an external prerequisite, installed separately. It is not bundled in the app.
