import AppKit
import ImageIO

// MARK: - Window

/// A floating panel that takes keyboard input without stealing focus from the app you're typing in,
/// so the paste lands back in that app.
final class HistoryPanel: NSPanel {
    var keyEquivalentHandler: ((NSEvent) -> Bool)?
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyEquivalentHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Draws the selected row in the accent color even though the search field keeps keyboard focus.
private final class ClipRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set {}
    }
}

// MARK: - Row

private final class ClipCellView: NSTableCellView {
    static let reuseID = NSUserInterfaceItemIdentifier("ClipCell")

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let pinView = NSImageView()
    private var iconWidth: NSLayoutConstraint!
    private var iconHeight: NSLayoutConstraint!

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.reuseID

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 4
        iconView.layer?.masksToBounds = true

        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.maximumNumberOfLines = 1
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        shortcutLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        shortcutLabel.setContentHuggingPriority(.required, for: .horizontal)
        shortcutLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        pinView.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned")?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))

        for view in [iconView, titleLabel, detailLabel, shortcutLabel, pinView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        iconWidth = iconView.widthAnchor.constraint(equalToConstant: 20)
        iconHeight = iconView.heightAnchor.constraint(equalToConstant: 20)
        NSLayoutConstraint.activate([
            iconWidth, iconHeight,
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: pinView.leadingAnchor, constant: -6),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 2),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: pinView.leadingAnchor, constant: -6),

            shortcutLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            pinView.trailingAnchor.constraint(equalTo: shortcutLabel.leadingAnchor, constant: -6),
            pinView.centerYAnchor.constraint(equalTo: centerYAnchor),
            pinView.widthAnchor.constraint(equalToConstant: 12),
            pinView.heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(item: ClipItem, index: Int, icon: NSImage?, isThumbnail: Bool) {
        titleLabel.stringValue = item.title.isEmpty ? " " : item.title
        detailLabel.stringValue = "\(item.detail) · \(relativeTime(item.date))"
        shortcutLabel.stringValue = index < 9 ? "⌘\(index + 1)" : ""
        pinView.isHidden = !item.pinned
        iconView.image = icon
        iconWidth.constant = isThumbnail ? 46 : 20
        iconHeight.constant = isThumbnail ? 38 : 20
        updateColors()
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { updateColors() }
    }

    private func updateColors() {
        let selected = backgroundStyle == .emphasized
        titleLabel.textColor = selected ? .white : .labelColor
        detailLabel.textColor = selected ? NSColor.white.withAlphaComponent(0.8) : .secondaryLabelColor
        shortcutLabel.textColor = selected ? NSColor.white.withAlphaComponent(0.8) : .tertiaryLabelColor
        iconView.contentTintColor = selected ? .white : .secondaryLabelColor
        pinView.contentTintColor = selected ? .white : .systemOrange
    }
}

private let relativeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter
}()

private func relativeTime(_ date: Date) -> String {
    if Date().timeIntervalSince(date) < 60 { return "just now" }
    return relativeFormatter.localizedString(for: date, relativeTo: Date())
}

// MARK: - Controller

final class HistoryPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate,
                                    NSSearchFieldDelegate, NSWindowDelegate, NSMenuDelegate {
    var onPick: ((ClipItem) -> Void)?

    private let store: ClipboardStore
    private let panel: HistoryPanel
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let thumbnails = NSCache<NSString, NSImage>()
    private var rows: [ClipItem] = []
    private var menuTargetID: UUID?

    /// Physical key codes for 1…9, so ⌘1–9 work with any keyboard layout (e.g. Persian).
    private let digitKeyCodes: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

    init(store: ClipboardStore) {
        self.store = store
        panel = HistoryPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 470),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        super.init()
        thumbnails.countLimit = 120
        configurePanel()
        buildContent()
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() { panel.isVisible ? hide() : show() }

    func show() {
        searchField.stringValue = ""
        reload()
        position()
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(searchField)
        select(0)
        panel.invalidateShadow()
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }

    func reloadIfVisible() {
        if panel.isVisible { reload(keepSelection: true) }
    }

    // MARK: Setup

    private func configurePanel() {
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.delegate = self
        panel.keyEquivalentHandler = { [weak self] event in self?.handleKeyEquivalent(event) ?? false }
        panel.onCancel = { [weak self] in self?.hide() }
    }

    private func buildContent() {
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: 14)
        panel.contentView = background

        let heading = NSTextField(labelWithString: "Clipboard")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)

        let clearButton = NSButton(title: "Clear all", target: self, action: #selector(clearAll))
        clearButton.isBordered = false
        clearButton.font = .systemFont(ofSize: 12)
        clearButton.contentTintColor = .controlAccentColor
        clearButton.toolTip = "Remove everything except pinned items"

        searchField.placeholderString = "Search"
        searchField.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.resizingMask = .autoresizingMask
        column.width = 380
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .inset
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.refusesFirstResponder = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        let contextMenu = NSMenu()
        contextMenu.delegate = self
        tableView.menu = contextMenu

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.borderType = .noBorder

        emptyLabel.alignment = .center
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.preferredMaxLayoutWidth = 300

        let footer = NSTextField(labelWithString: "↩ Paste     ⌘1–9 Quick paste     ⌘P Pin     ⌘⌫ Delete")
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .tertiaryLabelColor
        footer.alignment = .center
        footer.lineBreakMode = .byTruncatingTail

        for view in [heading, clearButton, searchField, scrollView, emptyLabel, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: background.topAnchor, constant: 12),
            heading.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            clearButton.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -14),

            searchField.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 2),
            scrollView.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -2),

            footer.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 6),
            footer.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            footer.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),
            footer.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -10),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    /// Open under the text cursor if the app tells us where it is, otherwise at the mouse.
    private func position() {
        let size = panel.frame.size
        let anchor: NSRect
        if let caret = Caret.screenRect() {
            anchor = caret
        } else {
            let mouse = NSEvent.mouseLocation
            anchor = NSRect(x: mouse.x, y: mouse.y, width: 0, height: 0)
        }
        let center = NSPoint(x: anchor.midX, y: anchor.midY)
        let screen = NSScreen.screens.first { NSMouseInRect(center, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame

        var x = anchor.minX
        var y = anchor.minY - size.height - 6           // below the cursor
        if y < visible.minY { y = anchor.maxY + 6 }      // not enough room: above it
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        y = min(max(y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: Data

    private func reload(keepSelection: Bool = false) {
        let selectedID = keepSelection && rows.indices.contains(tableView.selectedRow) ? rows[tableView.selectedRow].id : nil
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        rows = query.isEmpty
            ? store.items
            : store.items.filter { $0.searchText.localizedCaseInsensitiveContains(query) || $0.title.localizedCaseInsensitiveContains(query) }
        tableView.reloadData()

        emptyLabel.isHidden = !rows.isEmpty
        emptyLabel.stringValue = store.items.isEmpty
            ? "Nothing copied yet.\nCopy something with ⌘C and it will show up here."
            : "No matches"

        if let selectedID, let index = rows.firstIndex(where: { $0.id == selectedID }) {
            select(index)
        } else {
            select(0)
        }
    }

    private func select(_ row: Int) {
        guard !rows.isEmpty else { return }
        let clamped = max(0, min(row, rows.count - 1))
        tableView.selectRowIndexes(IndexSet(integer: clamped), byExtendingSelection: false)
        tableView.scrollRowToVisible(clamped)
    }

    private func icon(for item: ClipItem) -> (NSImage?, Bool) {
        switch item.kind {
        case .image:
            if let thumbnail = thumbnail(for: item) { return (thumbnail, true) }
            return (symbol("photo"), false)
        case .files:
            if let path = item.filePaths.first, FileManager.default.fileExists(atPath: path) {
                return (NSWorkspace.shared.icon(forFile: path), false)
            }
            return (symbol("doc"), false)
        case .link:
            return (symbol("link"), false)
        case .text:
            return (symbol("text.alignleft"), false)
        case .other:
            return (symbol("square.dashed"), false)
        }
    }

    private func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        image?.isTemplate = true
        return image
    }

    private func thumbnail(for item: ClipItem) -> NSImage? {
        let key = item.id.uuidString as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let rep = item.imageRep,
              let source = CGImageSourceCreateWithData(rep.data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 120,
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width / 2, height: cgImage.height / 2))
        thumbnails.setObject(image, forKey: key)
        return image
    }

    // MARK: Actions

    private func pick(row: Int) {
        guard rows.indices.contains(row) else { return }
        let item = rows[row]
        hide()
        onPick?(item)
    }

    @objc private func rowClicked() {
        pick(row: tableView.clickedRow)
    }

    @objc private func clearAll() {
        store.clearUnpinned()
        reload()
    }

    private func deleteSelected() {
        let row = tableView.selectedRow
        guard rows.indices.contains(row) else { return }
        store.remove(id: rows[row].id)
        reload()
        select(min(row, rows.count - 1))
    }

    private func togglePinSelected() {
        let row = tableView.selectedRow
        guard rows.indices.contains(row) else { return }
        store.togglePin(id: rows[row].id)
        reload(keepSelection: true)
    }

    private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
        guard flags == .command else { return false }
        switch event.keyCode {
        case 51, 117: deleteSelected(); return true      // ⌘⌫ / ⌘⌦
        case 35: togglePinSelected(); return true         // ⌘P
        case 13: hide(); return true                      // ⌘W
        default:
            if let number = digitKeyCodes[event.keyCode] {
                pick(row: number - 1)
                return true
            }
            return false                                  // ⌘A, ⌘C… keep working in the search field
        }
    }

    // MARK: NSSearchFieldDelegate

    func controlTextDidChange(_ obj: Notification) { reload() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)):
            select(tableView.selectedRow - 1); return true
        case #selector(NSResponder.moveDown(_:)):
            select(tableView.selectedRow + 1); return true
        case #selector(NSResponder.insertNewline(_:)):
            pick(row: tableView.selectedRow); return true
        case #selector(NSResponder.cancelOperation(_:)):
            if searchField.stringValue.isEmpty {
                hide()
            } else {
                searchField.stringValue = ""
                reload()
            }
            return true
        default:
            return false
        }
    }

    // MARK: NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        rows.indices.contains(row) && rows[row].kind == .image ? 54 : 40
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { ClipRowView() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: ClipCellView.reuseID, owner: self) as? ClipCellView
            ?? ClipCellView(frame: .zero)
        let item = rows[row]
        let (image, isThumbnail) = icon(for: item)
        cell.configure(item: item, index: row, icon: image, isThumbnail: isThumbnail)
        return cell
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) { hide() }

    // MARK: Right-click menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = tableView.clickedRow
        guard rows.indices.contains(row) else { menuTargetID = nil; return }
        let item = rows[row]
        menuTargetID = item.id
        menu.addItem(withTitle: "Paste", action: #selector(contextPaste), keyEquivalent: "").target = self
        menu.addItem(withTitle: item.pinned ? "Unpin" : "Pin", action: #selector(contextTogglePin), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Delete", action: #selector(contextDelete), keyEquivalent: "").target = self
    }

    @objc private func contextPaste() {
        guard let id = menuTargetID, let item = store.item(id) else { return }
        hide()
        onPick?(item)
    }

    @objc private func contextTogglePin() {
        guard let id = menuTargetID else { return }
        store.togglePin(id: id)
        reload(keepSelection: true)
    }

    @objc private func contextDelete() {
        guard let id = menuTargetID else { return }
        store.remove(id: id)
        reload()
    }
}
