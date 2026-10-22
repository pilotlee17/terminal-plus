import AppKit
import SwiftTerm
import TilesCore

enum Theme {
    static let background = NSColor(srgbRed: 0.055, green: 0.064, blue: 0.083, alpha: 1)
    static let panel = NSColor(srgbRed: 0.085, green: 0.098, blue: 0.121, alpha: 1)
    static let border = NSColor(srgbRed: 0.17, green: 0.19, blue: 0.23, alpha: 1)
    static let accent = NSColor(srgbRed: 0.55, green: 0.87, blue: 0.70, alpha: 1)
    static let text = NSColor(srgbRed: 0.88, green: 0.91, blue: 0.94, alpha: 1)
}

final class TopAlignedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

func label(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular, color: NSColor = Theme.text) -> NSTextField {
    let value = NSTextField(labelWithString: text)
    value.font = .systemFont(ofSize: size, weight: weight); value.textColor = color
    value.lineBreakMode = .byTruncatingMiddle
    return value
}

final class ActionButton: NSButton {
    var actionBlock: () -> Void = {}
    init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
        super.init(frame: .zero)
        self.title = title; actionBlock = action; target = self; self.action = #selector(invoke)
        bezelStyle = .rounded; controlSize = .regular; font = .systemFont(ofSize: 12, weight: .medium)
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: title); imagePosition = .imageLeading }
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func invoke() { actionBlock() }
}

final class FocusTerminal: LocalProcessTerminalView {
    var onFocus: () -> Void = {}
    override func mouseDown(with event: NSEvent) { onFocus(); super.mouseDown(with: event) }
}

final class PaneView: NSView, LocalProcessTerminalViewDelegate {
    var pane: Pane
    var connectionDeferred = false
    var currentDirectory: String
    let terminal = FocusTerminal(frame: NSRect(x: 0, y: 0, width: 700, height: 440))
    let status = label("正在连接…", size: 10, color: .secondaryLabelColor)
    let service: SessionService
    var onFocus: () -> Void = {}
    var onClose: () -> Void = {}
    var onFailure: (String) -> Void = { _ in }
    var closed = false
    var starting = false
    var failure: String?
    let header = PaneDragHeader()
    private var retryButton: ActionButton!
    private var closeButton: ActionButton!
    private var closing = false

    init(pane: Pane, service: SessionService) {
        self.pane = pane; self.service = service; self.currentDirectory = pane.directory
        super.init(frame: NSRect(x: 0, y: 0, width: 700, height: 480))
        wantsLayer = true; layer?.backgroundColor = Theme.background.cgColor
        layer?.cornerRadius = 10; layer?.borderWidth = 1; layer?.borderColor = Theme.border.cgColor
        header.wantsLayer = true; header.layer?.backgroundColor = Theme.panel.cgColor
        header.toolTip = "拖动重排 · 双击聚焦 / 还原"
        header.onFocus = { [weak self] in self?.onFocus(); self?.window?.makeFirstResponder(self?.terminal) }
        let icon = label("›_", size: 18, weight: .semibold, color: Theme.accent)
        let title = label(pane.title, size: 12, weight: .semibold)
        let folder = ActionButton("", symbol: "folder") { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(URL(fileURLWithPath: self.currentDirectory))
        }
        folder.toolTip = "打开终端所在目录"
        let spacer = NSView()
        retryButton = ActionButton("", symbol: "arrow.clockwise") { [weak self] in self?.connect() }
        retryButton.toolTip = "重新连接会话；已退出的程序请关闭面板后新建"
        let close = ActionButton("", symbol: "xmark") { [weak self] in self?.onClose() }
        closeButton = close
        close.toolTip = "关闭面板与会话"
        let row = NSStackView(views: [icon, title, status, spacer, folder, retryButton, close])
        row.orientation = .horizontal; row.spacing = 7
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        for button in [folder, retryButton!, close] { button.setContentCompressionResistancePriority(.required, for: .horizontal) }
        header.addSubview(row); addSubview(header); addSubview(terminal)
        terminal.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        terminal.nativeBackgroundColor = Theme.background; terminal.nativeForegroundColor = Theme.text
        terminal.processDelegate = self
        terminal.onFocus = { [weak self] in self?.onFocus() }
        for view in [header, row, terminal] { view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor), header.leadingAnchor.constraint(equalTo: leadingAnchor), header.trailingAnchor.constraint(equalTo: trailingAnchor), header.heightAnchor.constraint(equalToConstant: 42),
            row.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12), row.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -8), row.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            terminal.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6), terminal.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), terminal.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8), terminal.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
        setAccessibilityLabel(pane.title)
    }
    required init?(coder: NSCoder) { fatalError() }
    func setFocused(_ value: Bool) { layer?.borderColor = (value ? Theme.accent.withAlphaComponent(0.8) : Theme.border).cgColor }
    func setClosing(_ value: Bool) {
        closing = value
        closeButton.isEnabled = !value; retryButton.isEnabled = !value
        status.stringValue = value ? "正在关闭…" : "关闭失败 · 可重试"
    }
    func connect() {
        guard !connectionDeferred, !closed, !closing, !starting, !terminal.process.running, !terminal.process.windingDown else { return }
        starting = true; failure = nil; status.stringValue = "正在连接…"
        service.prepare(pane) { [weak self] result in
            guard let self else { return }; self.starting = false
            guard !self.closed, !self.closing else { return }
            switch result {
            case .failure(let error):
                self.failure = error.localizedDescription; self.status.stringValue = "连接失败"; self.status.toolTip = error.localizedDescription
                self.onFailure("无法打开 \(self.pane.title)\n" + error.localizedDescription)
            case .success:
                guard let executable = self.service.tmux else { return }
                self.terminal.startProcess(executable: executable, args: self.service.baseArguments + ["attach-session", "-t", "=" + self.pane.sessionName], environment: self.service.environment.map { "\($0.key)=\($0.value)" })
                self.status.stringValue = "已连接"
                // Reattached TUI output can arrive before the first visible window frame.
                // Ask tmux for a complete repaint once the native view has been presented.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    guard let self, !self.closed, self.terminal.process.running else { return }
                    self.terminal.needsDisplay = true
                    self.service.redraw(self.pane)
                }
            }
        }
    }
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) { status.toolTip = title }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) { status.stringValue = "已断开 · 点击重连" }
    func processFailedToStart(source: TerminalView, error: LocalProcessError) { failure = String(describing: error); status.stringValue = "启动失败"; status.toolTip = failure }
}

final class TileSplitView: NSSplitView, NSSplitViewDelegate {
    let splitID: UUID
    var initialRatio: Double
    var firstMinimum = CGSize(width: 280, height: 160)
    var secondMinimum = CGSize(width: 280, height: 160)
    var onRatio: (UUID, Double) -> Void = { _, _ in }
    var onInteractionBegin: () -> Void = {}
    var onInteractionEnd: () -> Void = {}
    var restored = false
    init(id: UUID, axis: SplitAxis, ratio: Double) {
        splitID = id; initialRatio = ratio.isFinite ? min(0.85, max(0.15, ratio)) : 0.5
        super.init(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        isVertical = axis == .columns; dividerStyle = .thin; delegate = self
    }
    required init?(coder: NSCoder) { fatalError() }
    override var dividerThickness: CGFloat { 10 }
    override func drawDivider(in rect: NSRect) { Theme.background.setFill(); rect.fill() }
    override func mouseDown(with event: NSEvent) {
        onInteractionBegin()
        defer { onInteractionEnd() }
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2, subviews.count == 2 {
            let edge = isVertical ? subviews[0].frame.maxX : subviews[0].frame.maxY
            let coordinate = isVertical ? point.x : point.y
            if coordinate >= edge && coordinate <= edge + dividerThickness {
                setPosition(available / 2, ofDividerAt: 0); return
            }
        }
        super.mouseDown(with: event)
    }
    private var available: CGFloat { max(0, (isVertical ? bounds.width : bounds.height) - dividerThickness) }
    private var limits: (CGFloat, CGFloat) {
        let first = isVertical ? firstMinimum.width : firstMinimum.height
        let second = isVertical ? secondMinimum.width : secondMinimum.height
        if available >= first + second { return (first, available - second) }
        // Small windows still allow dragging without invalid, crossed constraints.
        return (available * 0.15, available * 0.85)
    }
    func restore() {
        guard subviews.count == 2 else { return }
        if !restored {
            setPosition(min(limits.1, max(limits.0, available * initialRatio)), ofDividerAt: 0)
            restored = true
        }
        subviews.compactMap { $0 as? TileSplitView }.forEach { $0.restore() }
    }
    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard restored, subviews.count == 2 else { return }
        let total = available
        let size = isVertical ? subviews[0].frame.width : subviews[0].frame.height
        if total > 0 { onRatio(splitID, size / total) }
    }
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat { limits.0 }
    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat { limits.1 }
}
