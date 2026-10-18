import AppKit
import SwiftUI
import Combine
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private let model = DrawingModel()
    private var cancellables = Set<AnyCancellable>()
    private var hasPositioned = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock'ta ikon gösterme, sadece menü çubuğunda yaşa (Info.plist'teki LSUIElement'in kod karşılığı)
        NSApp.setActivationPolicy(.accessory)

        // 1) Menü çubuğu ikonu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "ClockDraw")
            button.action = #selector(togglePanel)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])   // sağ tıkı da yakala
        }

        // 2) Yüzen panel: başlık çubuğu şeffaf, boyutlandırılabilir
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 430),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.isMovableByWindowBackground = false   // yoksa çizim yaparken pencere kayar
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 450, height: 490)   // araç çubuğu sığsın diye
        panel.setContentSize(NSSize(width: 460, height: 510))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Başlık çubuğunu silmiyoruz, görünmez yapıyoruz. Neden: .titled stilinde kalınca
        // köşe yuvarlaklığı, gölge ve kenarlardan boyutlandırma macOS'tan bedava geliyor.
        // .borderless'a geçseydik bunların hepsini elle yazmak gerekirdi.
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(b)?.isHidden = true
        }

        // Saydam pencere: arka planı SwiftUI'daki bulanık cam (PanelBackground) çizecek
        panel.isOpaque = false
        panel.backgroundColor = .clear

        panel.contentView = NSHostingView(rootView: ContentView(model: model) { [weak self] in
            self?.panel.orderOut(nil)
        })

        // 3) Geri al kısayolları (sadece bizim panelimize gelen olaylar)
        installUndoShortcuts()

        // 4) Raptiye durumunu dinle → pencere seviyesini güncelle
        model.$isPinned
            .sink { [weak self] pinned in self?.applyPin(pinned) }
            .store(in: &cancellables)
    }

    // Raptiye mantığı:
    //  - pinned  → .floating seviyesi (her şeyin üstünde) + başka uygulamaya geçince gizlenme
    //  - unpinned → normal seviye + uygulama arka plana düşünce otomatik gizlen (popover gibi)
    private func applyPin(_ pinned: Bool) {
        panel.level = pinned ? .floating : .normal
        panel.hidesOnDeactivate = !pinned
    }

    // Debounce'un 0.4 sn'lik penceresi içinde çıkılırsa son değişiklik kaybolmasın
    func applicationWillTerminate(_ notification: Notification) {
        model.save()
    }

    // Menü çubuğu ikonuna sağ tık → küçük menü (uygulamadan çıkmanın tek yolu bu,
    // çünkü Dock ikonu ve menü çubuğu menüsü yok)
    private func showStatusMenu() {
        let menu = NSMenu()

        let login = NSMenuItem(title: "Launch at Login",
                               action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off   // tik işareti
        menu.addItem(login)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit ClockDraw",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        guard let button = statusItem.button else { return }
        // Menüyü doğrudan butonun hemen altında aç. (Önceki "menu ata → performClick → menüyü sil"
        // hilesi aksiyonun İÇİNDEN çağrılınca güvenilir çalışmıyordu; tıklama zaten işleniyorken
        // ikinci bir tıklama simüle etmeye çalışıyordu.)
        let y = button.isFlipped ? button.bounds.maxY + 4 : -4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: button)
    }

    // Girişte başlatma: macOS 13+ ServiceManagement API'si. Uygulamayı Sistem Ayarları >
    // Genel > Giriş Öğeleri listesine ekler/çıkarır. Sadece gerçek bir .app paketiyle çalışır;
    // Xcode'dan Play ile açılan çıplak çalıştırılabilir dosyada hata verir.
    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
                // Kullanıcı onayı gerekiyorsa ilgili ayar sayfasını aç
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = """
            This only works with the packaged ClockDraw.app \
            (opened from the Applications folder).

            \(error.localizedDescription)
            """
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    // "Yerel olay dinleyicisi": uygulamamıza gelen her olay pencereye ulaşmadan önce
    // buradan geçer. nil döndürürsek olayı yutarız, e döndürürsek normal akışına devam eder.
    //
    // İki parmak "çift" hareketinin trackpad'de iki farklı anlamı olabilir, ikisini de yakalıyoruz:
    //   .smartMagnify          → iki parmakla çift DOKUNMA (bastırmadan). Sistem Ayarları >
    //                            Trackpad > "Akıllı büyütme" açık olmalı, yoksa macOS bu olayı hiç üretmez.
    //   .rightMouseDown (×2)   → iki parmakla çift TIKLAMA (bastırarak). İki parmak tık = sağ tık,
    //                            clickCount == 2 ise ikincisi.
    private func installUndoShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: [.smartMagnify, .rightMouseDown, .keyDown]) { [weak self] e in
            guard let self, e.window === self.panel else { return e }

            switch e.type {
            case .smartMagnify:
                self.model.undo(); return nil
            case .rightMouseDown where e.clickCount == 2:
                self.model.undo(); return nil
            case .keyDown where e.modifierFlags.contains(.command)
                             && e.charactersIgnoringModifiers?.lowercased() == "q":
                NSApp.terminate(nil); return nil
            case .keyDown where e.modifierFlags.contains(.command)
                             && e.charactersIgnoringModifiers?.lowercased() == "z":
                if e.modifierFlags.contains(.shift) { self.model.redo() } else { self.model.undo() }
                return nil
            default:
                return e
            }
        }
    }

    @objc private func togglePanel() {
        // Sağ tık ya da Control+tık → menü
        if let e = NSApp.currentEvent,
           e.type == .rightMouseUp || e.modifierFlags.contains(.control) {
            showStatusMenu()
            return
        }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            if !hasPositioned { positionUnderStatusItem(); hasPositioned = true }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    // İlk açılışta paneli ikonun hemen altına ortala. Sonrasında kullanıcı
    // nereye taşıdıysa orada kalsın diye bir daha konumlandırmıyoruz.
    private func positionUnderStatusItem() {
        guard let buttonFrame = statusItem.button?.window?.frame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: buttonFrame.midX - size.width / 2,
            y: buttonFrame.minY - size.height - 6
        ))
    }
}
