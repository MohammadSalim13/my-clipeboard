import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ClipboardStore()
    private let monitor = PasteboardMonitor()
    private var panel: HistoryPanelController!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var promptedForAccessibility = false

    private var autoPaste: Bool {
        get { UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoPaste") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)   // already running
            return
        }

        store.load()
        captureClipboard(atStartup: true)

        panel = HistoryPanelController(store: store)
        panel.onPick = { [weak self] item in self?.use(item) }
        store.onChange = { [weak self] in self?.panel.reloadIfVisible() }

        monitor.onChange = { [weak self] in self?.captureClipboard(atStartup: false) }
        monitor.start()

        setUpStatusItem()

        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(optionKey)) { [weak self] in
            self?.panel.toggle()
        }
        if hotKey == nil {
            showAlert("Option-V is already used by another app",
                      "You can still open your clipboard history from the menu bar icon.")
        }

        LoginItem.enableOnFirstLaunch()

        if !Paster.isTrusted {
            promptedForAccessibility = true
            Paster.requestAccess()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.show()   // opening the app again from Finder/Launchpad shows the list
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    // MARK: Clipboard

    private func captureClipboard(atStartup: Bool) {
        guard let item = ClipCapture.capture(from: .general) else { return }
        if atStartup && store.contains(fingerprint: item.fingerprint) { return }
        store.add(item)
    }

    /// Put the chosen item on the clipboard and paste it into the app you were using.
    private func use(_ item: ClipItem) {
        store.write(item, to: .general)
        monitor.skipCurrentChange()
        store.markUsed(id: item.id)

        guard autoPaste else { return }
        if Paster.isTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { Paster.pressCommandV() }
        } else if !promptedForAccessibility {
            promptedForAccessibility = true
            Paster.requestAccess()
        }
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Clipboard History")
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let show = menu.addItem(withTitle: "Show Clipboard History", action: #selector(showHistory), keyEquivalent: "v")
        show.keyEquivalentModifierMask = .option
        show.target = self

        menu.addItem(.separator())

        let paste = menu.addItem(withTitle: "Paste Automatically After Choosing", action: #selector(toggleAutoPaste), keyEquivalent: "")
        paste.target = self
        paste.state = autoPaste ? .on : .off

        let login = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off

        if !Paster.isTrusted {
            menu.addItem(.separator())
            let access = menu.addItem(withTitle: "Allow Auto-Paste (Accessibility)…", action: #selector(grantAccessibility), keyEquivalent: "")
            access.target = self
        }

        menu.addItem(.separator())
        let clear = menu.addItem(withTitle: "Clear History (keeps pinned)", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = store.items.contains { !$0.pinned }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Clipboard History", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func showHistory() {
        DispatchQueue.main.async { self.panel.show() }   // let the menu close first
    }

    @objc private func toggleAutoPaste() {
        autoPaste.toggle()
    }

    @objc private func toggleLogin() {
        do {
            try LoginItem.set(!LoginItem.isEnabled)
        } catch {
            showAlert("Couldn't change Open at Login", error.localizedDescription)
        }
    }

    @objc private func grantAccessibility() {
        Paster.requestAccess()
        Paster.openAccessibilitySettings()
    }

    @objc private func clearHistory() {
        store.clearUnpinned()
    }

    private func showAlert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
