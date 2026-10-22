import AppKit
import TilesCore

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var controller: TilesController!
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate; app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        controller = TilesController(); controller.window?.delegate = self
        buildMenu(); controller.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { controller.showWindow(nil); return true }
    func applicationWillTerminate(_ notification: Notification) { controller.save(); controller.detachAll() }
    func windowWillClose(_ notification: Notification) { controller.save() }
    func windowDidResignKey(_ notification: Notification) { controller.finishDrag(at: nil) }
    func buildMenu() {
        let main = NSMenu()
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(); item.title = title
            let result = NSMenu(title: title); item.submenu = result; main.addItem(item); return result
        }
        func item(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = [.command]) {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
            entry.keyEquivalentModifierMask = modifiers; entry.target = controller; menu.addItem(entry)
        }
        let app = menu("Terminal+")
        item(app, "关于 Terminal+", #selector(TilesController.about), "")
        app.addItem(.separator())
        app.addItem(NSMenuItem(title: "退出 Terminal+（保留终端）", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let terminal = menu("终端")
        item(terminal, "新建终端", #selector(TilesController.newPanel), "n")
        item(terminal, "在指定目录新建…", #selector(TilesController.openDirectory), "o")
        item(terminal, "接回其他终端…", #selector(TilesController.restoreTerminal), "n", [.command, .shift])
        item(terminal, "左右分屏", #selector(TilesController.splitColumns), "d")
        item(terminal, "上下分屏", #selector(TilesController.splitRows), "d", [.command, .shift])
        item(terminal, "关闭当前终端…", #selector(TilesController.closeFocused), "w")
        item(terminal, "批量选择 / 完成", #selector(TilesController.toggleSelection), "s", [.command, .shift])
        let edit = menu("编辑")
        for (title, action, key) in [("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: NSSelectorFromString(action), keyEquivalent: key))
        }
        let view = menu("视图")
        item(view, "下一个终端", #selector(TilesController.nextPane), "]")
        item(view, "上一个终端", #selector(TilesController.previousPane), "[")
        item(view, "聚焦 / 还原", #selector(TilesController.toggleZoom), "\r", [.command, .shift])
        item(view, "整理布局", #selector(TilesController.arrangeLayout), "g", [.command, .shift])
        item(view, "撤销布局调整", #selector(TilesController.undoLayout), "z", [.command, .option])
        item(view, "重做布局调整", #selector(TilesController.redoLayout), "z", [.command, .option, .shift])
        item(view, "增大字号", #selector(TilesController.largerFont), "+")
        item(view, "减小字号", #selector(TilesController.smallerFont), "-")
        NSApp.mainMenu = main
    }
}

final class TilesController: NSWindowController, NSMenuItemValidation {
    let service: SessionService
    var state: TerminalState
    let stateURL: URL
    var panes: [UUID: PaneView] = [:]
    let surface = NSView()
    let footer = label("", size: 11, color: .secondaryLabelColor)
    var timer: Timer?
    var pendingSave: DispatchWorkItem?
    var zoomed = false
    var fontSize: CGFloat = 13
    var savedErrorShown = false
    private var savingAllowed = true
    var closingPanes = Set<UUID>()
    var pendingConnections = Set<UUID>()
    var layoutHistory = LayoutHistory()
    var reportError: ((String) -> Void)?
    private var splits: [UUID: TileSplitView] = [:]
    private var layoutButtons: [ActionButton] = []
    private var newButton: ActionButton!
    private var zoomButton: ActionButton!
    var selectionMode = false
    let selectionOverlay = PaneSelectionOverlay()
    let dropPreview = PaneDropPreview()
    private var draggedPane: UUID?
    private var rendering = false
    private var selectButton: ActionButton!
    private var closeSelectedButton: ActionButton!

    init(storageRoot: URL? = nil, service: SessionService = SessionService(), startTimer: Bool = true, reportError: ((String) -> Void)? = nil) {
        self.service = service; self.reportError = reportError
        // Keep the old storage root and tmux socket so running processes survive the upgrade.
        let root = storageRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Codex Tiles")
        stateURL = root.appendingPathComponent("terminal-layout.json")
        var loadError: String?
        if FileManager.default.fileExists(atPath: stateURL.path) {
            do { state = try TerminalState.load(from: stateURL) }
            catch {
                let backup = root.appendingPathComponent("terminal-layout-unreadable-\(UUID().uuidString).json")
                state = TerminalState()
                do {
                    try FileManager.default.copyItem(at: stateURL, to: backup)
                    loadError = "布局无法读取，原文件已备份。\n\(error.localizedDescription)"
                } catch {
                    savingAllowed = false
                    loadError = "布局无法读取且备份失败，已停止保存以保护原文件。请检查存储目录权限后重启。"
                }
            }
        } else if let legacy = try? StateStore.load(from: root.appendingPathComponent("workspaces.json")) {
            state = TerminalState(legacy: legacy)
        } else { state = TerminalState() }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Terminal+"; window.minSize = NSSize(width: 900, height: 440)
        window.backgroundColor = Theme.background; window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false; window.center()
        if storageRoot == nil { window.setFrameAutosaveName("CodexTilesMain") }
        super.init(window: window)
        buildUI(); renderLayout(); save()
        if startTimer { timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refreshStatuses() } }
        if let loadError { DispatchQueue.main.async { [weak self] in self?.showError(loadError) } }
    }
    required init?(coder: NSCoder) { fatalError() }

    func buildUI() {
        guard let root = window?.contentView else { return }
        let title = label("Terminal+", size: 17, weight: .semibold)
        selectButton = ActionButton("批量选择", symbol: "selection.pin.in.out") { [weak self] in self?.toggleSelection() }
        closeSelectedButton = ActionButton("关闭选中 (0)", symbol: "xmark") { [weak self] in self?.closeSelected() }
        closeSelectedButton.isHidden = true
        selectionOverlay.paneFrames = { [weak self] in
            guard let self else { return [:] }
            return Dictionary(uniqueKeysWithValues: self.panes.compactMap { id, view in
                view.isDescendant(of: self.surface) ? (id, self.selectionOverlay.convert(view.bounds, from: view)) : nil
            })
        }
        selectionOverlay.onChange = { [weak self] _ in self?.updateSelectionUI() }
        selectionOverlay.onCancel = { [weak self] in self?.toggleSelection() }
        selectionOverlay.onClose = { [weak self] in self?.closeSelected() }
        newButton = ActionButton("新建终端", symbol: "plus") { [weak self] in self?.newPanel() }
        newButton.toolTip = "自动选择宽敞位置和分屏方向 · ⌘N"
        zoomButton = ActionButton("聚焦", symbol: "arrow.up.left.and.arrow.down.right") { [weak self] in self?.toggleZoom() }
        layoutButtons = [newButton,
            ActionButton("左右", symbol: "rectangle.split.2x1") { [weak self] in self?.splitColumns() },
            ActionButton("上下", symbol: "rectangle.split.1x2") { [weak self] in self?.splitRows() },
            ActionButton("整理", symbol: "square.grid.2x2") { [weak self] in self?.arrangeLayout() }, zoomButton]
        let buttons = NSStackView(views: layoutButtons + [selectButton, closeSelectedButton])
        buttons.spacing = 8
        for view in [title, buttons, surface, footer] { root.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20), title.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            buttons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16), buttons.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            buttons.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 16),
            surface.topAnchor.constraint(equalTo: root.topAnchor, constant: 58), surface.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            surface.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12), surface.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -10),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18), footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12)
        ])
    }
    func renderLayout() {
        rendering = true
        defer { rendering = false }
        var created: [PaneView] = []
        for pane in state.panes where panes[pane.id] == nil {
            let view = PaneView(pane: pane, service: service)
            view.connectionDeferred = pendingConnections.contains(pane.id)
            view.terminal.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            view.onFocus = { [weak self] in self?.focus(pane.id, makeResponder: false) }
            view.onClose = { [weak self] in self?.closePane(pane.id) }
            view.onFailure = { [weak self] message in self?.showError(message) }
            view.header.onBegin = { [weak self] in self?.beginDrag(pane.id) ?? false }
            view.header.onUpdate = { [weak self] point in self?.updateDrag(at: point) }
            view.header.onEnd = { [weak self] point in self?.finishDrag(at: point) }
            view.header.onDoubleClick = { [weak self] in self?.toggleZoom() }
            panes[pane.id] = view
            created.append(view)
        }
        var activeSplits = Set<UUID>()
        func build(_ node: Layout) -> NSView {
            switch node {
            case .pane(let id): return panes[id]!
            case .split(let id, let axis, let ratio, let a, let b):
                activeSplits.insert(id)
                let split = splits[id] ?? TileSplitView(id: id, axis: axis, ratio: ratio)
                splits[id] = split
                let children = [build(a), build(b)]
                split.firstMinimum = a.minimumSize; split.secondMinimum = b.minimumSize
                if split.subviews.count != 2 || !zip(split.subviews, children).allSatisfy({ $0 === $1 }) {
                    split.subviews = children; split.restored = false
                }
                if abs(split.initialRatio - ratio) > 0.001 { split.restored = false }
                split.initialRatio = ratio
                split.onRatio = { [weak self] id, value in
                    guard let self, !self.zoomed, !self.rendering else { return }
                    self.state.layout = self.state.layout?.settingRatio(id, value); self.scheduleSave()
                }
                var previous: Layout?
                split.onInteractionBegin = { [weak self] in previous = self?.state.layout }
                split.onInteractionEnd = { [weak self] in
                    guard let self, let previous, let current = self.state.layout else { return }
                    self.layoutHistory.record(previous, current: current); self.scheduleSave()
                }
                return split
            }
        }
        if let layout = state.layout {
            let tree = zoomed ? state.focusedID.flatMap { panes[$0] } ?? build(layout) : build(layout)
            for view in surface.subviews where view !== tree { view.removeFromSuperview() }
            tree.frame = surface.bounds; tree.autoresizingMask = [.width, .height]
            if tree.superview !== surface { surface.addSubview(tree) }
            window?.contentView?.layoutSubtreeIfNeeded(); tree.frame = surface.bounds
            (tree as? TileSplitView)?.restore()
            if let id = state.focusedID { focus(id) }
            for view in created { view.connect() }
        } else {
            surface.subviews.forEach { $0.removeFromSuperview() }
            let message = label("终端已关闭 · 点击「新建终端」或按 ⌘N", size: 16, color: .secondaryLabelColor)
            surface.addSubview(message); message.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([message.centerXAnchor.constraint(equalTo: surface.centerXAnchor), message.centerYAnchor.constraint(equalTo: surface.centerYAnchor)])
        }
        if !zoomed { splits = splits.filter { activeSplits.contains($0.key) } }
        syncSelectionOverlay()
        updateSelectionUI()
        updateFooter()
    }
    private func syncSelectionOverlay() {
        if selectionMode {
            selectionOverlay.frame = surface.bounds
            selectionOverlay.autoresizingMask = [.width, .height]
            surface.addSubview(selectionOverlay)
            window?.makeFirstResponder(selectionOverlay)
        } else {
            selectionOverlay.removeFromSuperview()
        }
    }
    @objc func toggleSelection() {
        guard draggedPane == nil, closingPanes.isEmpty, window?.attachedSheet == nil else { return }
        guard !state.panes.isEmpty || selectionMode else { return }
        let wasZoomed = zoomed
        selectionMode.toggle(); selectionOverlay.selected = []; zoomed = false
        if wasZoomed { renderLayout() }
        else {
            syncSelectionOverlay(); updateSelectionUI()
            if !selectionMode, let id = state.focusedID { focus(id) }
        }
    }
    func updateSelectionUI() {
        selectionOverlay.selected.formIntersection(Set(state.panes.map(\.id)))
        selectButton.title = selectionMode ? "完成选择" : "批量选择"
        closeSelectedButton.isHidden = !selectionMode
        closeSelectedButton.title = "关闭选中 (\(selectionOverlay.selected.count))"
        closeSelectedButton.isEnabled = !selectionOverlay.selected.isEmpty && closingPanes.isEmpty
        selectionOverlay.locked = !closingPanes.isEmpty
        let editable = !selectionMode && closingPanes.isEmpty && draggedPane == nil
        layoutButtons.forEach { $0.isEnabled = editable }
        for button in layoutButtons.prefix(3) { button.isEnabled = editable && state.panes.count < 8 }
        zoomButton.isEnabled = editable && state.panes.count > 1
        zoomButton.title = zoomed ? "还原" : "聚焦"
        selectButton.isEnabled = closingPanes.isEmpty && draggedPane == nil && !state.panes.isEmpty
        updateFooter()
    }
    @objc func closeSelected() {
        guard selectionMode else { return }; closePanes(selectionOverlay.selected)
    }
    func focus(_ id: UUID, makeResponder: Bool = true) {
        guard state.panes.contains(where: { $0.id == id }) else { return }
        state.focusedID = id
        for (key, view) in panes { view.setFocused(key == id) }
        if makeResponder { window?.makeFirstResponder(panes[id]?.terminal) }
        updateFooter(); scheduleSave()
    }
    func updateFooter() {
        if draggedPane != nil {
            footer.stringValue = "拖到中央交换位置 · 拖到边缘放在左 / 右 / 上 / 下 · Esc 取消"
            return
        }
        if selectionMode {
            footer.stringValue = "已选 \(selectionOverlay.selected.count) 个 · 拖框圈选 / 点击切换 · Shift 追加圈选 · ⌘A 全选 · Esc 完成 · Delete 关闭选中"
            footer.toolTip = nil; return
        }
        let directory = state.focusedID.flatMap { panes[$0]?.currentDirectory } ?? ""
        footer.stringValue = "\(directory)   ·   拖动标题栏重排   ·   ⌘D 左右分屏   ⇧⌘D 上下分屏   ·   退出应用保留终端"
        footer.toolTip = directory
    }
    @objc func newPanel() { add(axis: nil) }
    @objc func splitColumns() { add(axis: .columns) }
    @objc func splitRows() { add(axis: .rows) }
    func add(axis: SplitAxis?, directory: String? = nil) {
        guard draggedPane == nil, closingPanes.isEmpty, !selectionMode, window?.attachedSheet == nil else { return }
        guard state.panes.count < 8 else { footer.stringValue = "已显示 8 个终端 · 可先关闭不需要的面板，或双击标题栏聚焦"; return }
        let focused = state.panes.first { $0.id == state.focusedID }
        let id = UUID()
        let path = directory ?? focused.flatMap { panes[$0.id]?.currentDirectory } ?? focused?.directory ?? FileManager.default.homeDirectoryForCurrentUser.path
        let newPane = Pane(id: id, title: "终端 " + id.uuidString.prefix(4).lowercased(), directory: path)
        var target = state.focusedID
        if axis == nil, !zoomed {
            target = (state.layout?.paneIDs ?? []).max { a, b in
                let x = panes[a]?.bounds.size ?? .zero, y = panes[b]?.bounds.size ?? .zero
                return x.width * x.height < y.width * y.height
            }
        }
        let size = target.flatMap { panes[$0]?.bounds.size } ?? surface.bounds.size
        let alreadyCramped = !zoomed && panes.values.contains { $0.bounds.width < 280 || $0.bounds.height < 160 }
        let direction = axis ?? (size.width / max(1, size.height) > 1.8 ? .columns : .rows)
        state.focusedID = target
        pendingConnections.insert(id)
        guard state.insert(newPane, axis: direction) else { pendingConnections.remove(id); return }
        layoutHistory.clear()
        let cramped = direction == .columns ? size.width < 570 : size.height < 330
        if cramped || alreadyCramped { state.layout = Layout.tiled(state.layout!.paneIDs, size: surface.bounds.size) }
        zoomed = false; renderLayout(); save()
        // Show the pane immediately. Resolve the source's current cwd before launching its shell.
        service.statuses { [weak self] statuses in
            guard let self else { return }
            self.pendingConnections.remove(id)
            guard let index = self.state.panes.firstIndex(where: { $0.id == id }), let view = self.panes[id] else { return }
            let inherited = focused.flatMap { statuses[$0.sessionName]?.directory }.flatMap { $0.hasPrefix("/") ? $0 : nil }
                ?? focused.flatMap { self.panes[$0.id]?.currentDirectory } ?? path
            let resolved = directory ?? inherited
            self.state.panes[index].directory = resolved
            view.pane.directory = resolved; view.currentDirectory = resolved; view.connectionDeferred = false
            view.connect(); self.updateFooter(); self.scheduleSave()
        }
    }
    @objc func arrangeLayout() {
        guard draggedPane == nil, closingPanes.isEmpty, !selectionMode, window?.attachedSheet == nil else { return }
        guard let layout = state.layout else { return }
        state.layout = Layout.tiled(layout.paneIDs, size: surface.bounds.size)
        if let current = state.layout { layoutHistory.record(layout, current: current) }
        zoomed = false; renderLayout(); save()
    }
    @objc func undoLayout() { restoreLayoutHistory(redo: false) }
    @objc func redoLayout() { restoreLayoutHistory(redo: true) }
    private func restoreLayoutHistory(redo: Bool) {
        guard draggedPane == nil, closingPanes.isEmpty, !selectionMode, window?.attachedSheet == nil, let current = state.layout else { return }
        guard let restored = redo ? layoutHistory.redo(current: current) : layoutHistory.undo(current: current) else { return }
        state.layout = restored; zoomed = false; renderLayout(); save()
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let editable = draggedPane == nil && closingPanes.isEmpty && !selectionMode && window?.attachedSheet == nil
        switch menuItem.action {
        case #selector(undoLayout): return editable && layoutHistory.canUndo
        case #selector(redoLayout): return editable && layoutHistory.canRedo
        case #selector(newPanel), #selector(splitColumns), #selector(splitRows), #selector(openDirectory), #selector(restoreTerminal): return editable && state.panes.count < 8
        case #selector(arrangeLayout), #selector(toggleZoom): return editable && state.panes.count > 1
        default: return true
        }
    }
    @objc func openDirectory() {
        guard draggedPane == nil, let window, window.attachedSheet == nil, !selectionMode, closingPanes.isEmpty else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.prompt = "新建终端"
        panel.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            self?.add(axis: nil, directory: url.path)
        }
    }
    @objc func restoreTerminal() {
        guard draggedPane == nil, let window, window.attachedSheet == nil, !selectionMode, closingPanes.isEmpty else { return }
        let parked = state.parked
        guard !parked.isEmpty else { showError("没有其他已保存的终端。"); return }
        let alert = NSAlert(); alert.messageText = "接回其他终端"
        alert.informativeText = "运行中的会话会直接接回；已退出的会话会在原目录打开普通终端。"
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 440, height: 28))
        picker.addItems(withTitles: parked.map { "\($0.title) · \($0.directory)" }); alert.accessoryView = picker
        alert.addButton(withTitle: "接回"); alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] result in
            guard result == .alertFirstButtonReturn, let self, parked.indices.contains(picker.indexOfSelectedItem) else { return }
            guard self.state.insert(parked[picker.indexOfSelectedItem], axis: .columns) else { self.showError("最多同时显示 8 个终端。"); return }
            self.layoutHistory.clear()
            self.zoomed = false; self.renderLayout(); self.save()
        }
    }
    @objc func toggleZoom() { guard draggedPane == nil, !state.panes.isEmpty, !selectionMode else { return }; zoomed.toggle(); renderLayout() }
    @objc func largerFont() { changeFont(1) }
    @objc func smallerFont() { changeFont(-1) }
    func changeFont(_ delta: CGFloat) { fontSize = min(24, max(10, fontSize + delta)); panes.values.forEach { $0.terminal.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular) } }
    @objc func nextPane() { cycle(1) }
    @objc func previousPane() { cycle(-1) }
    func cycle(_ delta: Int) {
        guard draggedPane == nil, !selectionMode else { return }
        let ids = state.layout?.paneIDs ?? []; guard !ids.isEmpty else { return }
        let next = ((ids.firstIndex(of: state.focusedID ?? ids[0]) ?? 0) + delta + ids.count) % ids.count
        focus(ids[next]); if zoomed { renderLayout() }
    }
    @objc func closeFocused() {
        if selectionMode { closeSelected() }
        else if let id = state.focusedID { closePane(id) }
    }
    func closePane(_ id: UUID) { closePanes([id]) }
    func closePanes(_ ids: Set<UUID>) {
        guard draggedPane == nil, closingPanes.isEmpty, let window, window.attachedSheet == nil else { return }
        // Freeze exact targets before presenting confirmation; later selection cannot expand it.
        let targets = state.panes.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = targets.count == 1 ? "关闭 \(targets[0].title)？" : "关闭选中的 \(targets.count) 个终端？"
        alert.informativeText = targets.map(\.title).joined(separator: "、") + "\n\n这会结束这些终端中的程序。其他终端不受影响，磁盘文件会保留。"
        alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "结束并关闭")
        alert.beginSheetModal(for: window) { [weak self] result in
            guard result == .alertSecondButtonReturn, let self, self.closingPanes.isEmpty else { return }
            self.performConfirmedClose(Set(targets.map(\.id)))
        }
    }
    // Called only after the sheet confirms this exact set, or by isolated integration tests.
    func performConfirmedClose(_ ids: Set<UUID>) {
        guard closingPanes.isEmpty else { return }
        let targets = state.panes.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }
        self.closingPanes = Set(targets.map(\.id)); self.updateSelectionUI()
        for pane in targets { self.panes[pane.id]?.setClosing(true) }
        var remaining = targets.count
        var errors: [String] = []
        for pane in targets {
            self.service.kill(pane) { [weak self] result in
                guard let self else { return }
                var didClose = true
                if case .failure(let error) = result {
                    let message = error.localizedDescription
                    if !message.contains("can't find") && !message.contains("no server") && !message.contains("No such file") {
                        didClose = false; errors.append("\(pane.title)：\(message)")
                        self.panes[pane.id]?.setClosing(false)
                        self.panes[pane.id]?.connect()
                    }
                }
                if didClose {
                    self.layoutHistory.clear()
                    self.panes[pane.id]?.closed = true; self.panes[pane.id]?.terminal.terminate()
                    self.panes.removeValue(forKey: pane.id); self.state.remove(pane.id)
                }
                remaining -= 1
                guard remaining == 0 else { return }
                self.closingPanes.removeAll(); self.zoomed = false
                if errors.isEmpty { self.selectionMode = false; self.selectionOverlay.selected = [] }
                self.renderLayout(); self.save()
                if !errors.isEmpty { self.showError("部分终端未能关闭，已保留，可重试。\n" + errors.joined(separator: "\n")) }
            }
        }
    }
    func refreshStatuses() {
        service.statuses { [weak self] statuses in
            guard let self else { return }
            var directoryChanged = false
            for view in self.panes.values where view.failure == nil && !view.starting && !self.closingPanes.contains(view.pane.id) {
                guard let status = statuses[view.pane.sessionName] else { continue }
                if view.terminal.process.running, view.status.stringValue != status.status { view.status.stringValue = status.status }
                if status.directory.hasPrefix("/"), view.currentDirectory != status.directory {
                    view.currentDirectory = status.directory
                    if let index = self.state.panes.firstIndex(where: { $0.id == view.pane.id }) { self.state.panes[index].directory = status.directory }
                    directoryChanged = true
                }
            }
            self.updateFooter()
            if directoryChanged { self.scheduleSave() }
        }
    }
    func scheduleSave() {
        pendingSave?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.save() }; pendingSave = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }
    func save() {
        pendingSave?.cancel()
        guard savingAllowed else { return }
        do { try state.save(to: stateURL) }
        catch { if !savedErrorShown { savedErrorShown = true; showError("布局未能保存：\(error.localizedDescription)") } }
    }
    func detachAll() { timer?.invalidate(); panes.values.forEach { $0.closed = true; $0.terminal.terminate() } }
    func showError(_ message: String) {
        if let reportError { reportError(message); return }
        let alert = NSAlert(); alert.messageText = "Terminal+"; alert.informativeText = message
        if let window, window.attachedSheet == nil { alert.beginSheetModal(for: window) }
    }
    @objc func about() { showError("Terminal+ 0.8.0\n简单的 macOS 终端分屏\n\n每个新面板打开 zsh，继承当前终端目录。\n运行什么命令由你决定，不要求 Git，不自动创建 worktree。\n退出应用后终端继续运行；重启 Mac 后重新打开 shell。") }

    func beginDrag(_ id: UUID) -> Bool {
        guard !selectionMode, !zoomed, closingPanes.isEmpty, window?.attachedSheet == nil,
              state.panes.count > 1, panes[id] != nil else { return false }
        draggedPane = id; updateSelectionUI()
        dropPreview.frame = surface.bounds; dropPreview.autoresizingMask = [.width, .height]
        dropPreview.preview = nil; surface.addSubview(dropPreview)
        updateFooter()
        return true
    }
    private func dropTarget(at windowPoint: NSPoint) -> (UUID, PanePlacement, NSRect)? {
        let point = dropPreview.convert(windowPoint, from: nil)
        guard dropPreview.bounds.contains(point) else { return nil }
        for id in state.layout?.paneIDs ?? [] where id != draggedPane {
            guard let view = panes[id], view.isDescendant(of: surface) else { continue }
            let frame = dropPreview.convert(view.bounds, from: view)
            if frame.contains(point) {
                let placement = PaneDropPreview.placement(at: point, in: frame)
                return (id, placement, PaneDropPreview.region(frame, placement: placement))
            }
        }
        return nil
    }
    func updateDrag(at point: NSPoint) {
        guard draggedPane != nil else { return }
        let target = dropTarget(at: point)
        dropPreview.placement = target?.1 ?? .center; dropPreview.preview = target?.2
    }
    func finishDrag(at point: NSPoint?) {
        guard let source = draggedPane else { return }
        let target = point.flatMap { dropTarget(at: $0) }
        let previous = state.layout
        draggedPane = nil; dropPreview.preview = nil; dropPreview.removeFromSuperview()
        if let (target, placement, _) = target, state.move(source, relativeTo: target, placement: placement) {
            if let previous, let current = state.layout { layoutHistory.record(previous, current: current) }
            renderLayout(); save()
        } else { focus(source) }
        updateSelectionUI()
    }
}
