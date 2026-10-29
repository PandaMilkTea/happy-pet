import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let brain = PetBrain()
    private var panel: PetPanel?
    private var statusItem: NSStatusItem?
    private var followItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // 不在 Dock 里显示

        let panel = PetPanel(brain: brain)
        brain.window = panel
        brain.resetPosition()
        panel.orderFrontRegardless()
        self.panel = panel

        setupStatusItem()
        brain.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        brain.stop()
    }

    // MARK: - 菜单栏图标

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "pawprint.fill",
                accessibilityDescription: "桌面宠物"
            )
            button.image?.isTemplate = true
        }
        let menu = makeContextMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    // MARK: - 右键 / 状态栏菜单

    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()

        let poke = NSMenuItem(title: "戳一戳", action: #selector(pokePet), keyEquivalent: "")
        poke.target = self
        menu.addItem(poke)

        let follow = NSMenuItem(title: "跟随鼠标", action: #selector(toggleFollow), keyEquivalent: "")
        follow.target = self
        follow.state = brain.followMouse ? .on : .off
        menu.addItem(follow)
        followItem = follow

        let sleep = NSMenuItem(title: "睡一会儿 / 醒来", action: #selector(toggleSleep), keyEquivalent: "")
        sleep.target = self
        menu.addItem(sleep)

        menu.addItem(.separator())

        let reset = NSMenuItem(title: "回到屏幕右下角", action: #selector(resetPosition), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        followItem?.state = brain.followMouse ? .on : .off
    }

    // MARK: - Actions

    @objc private func pokePet() {
        brain.poke()
    }

    @objc private func toggleFollow() {
        brain.followMouse.toggle()
        followItem?.state = brain.followMouse ? .on : .off
    }

    @objc private func toggleSleep() {
        brain.toggleSleep()
    }

    @objc private func resetPosition() {
        brain.resetPosition()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - 启动

let delegate = AppDelegate()
let application = NSApplication.shared
application.delegate = delegate
application.run()