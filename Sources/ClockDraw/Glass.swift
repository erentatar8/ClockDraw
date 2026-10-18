import SwiftUI
import AppKit

// MARK: - Liquid Glass (macOS 26+) ve eski sürümler için yedek

// macOS 26 (Tahoe) ile gelen gerçek Liquid Glass API'si `.glassEffect`.
// İki katmanlı koruma var:
//   #if compiler(>=6.2)   → Xcode 26 SDK'sı yoksa bu kod hiç derlenmez (derleme hatası olmaz)
//   #available(macOS 26)  → derlendi ama eski macOS'ta çalışıyorsa çalışma anında yedeğe düş
// Yedek: buzlu cam materyali + ince beyaz kenar, görsel olarak yakın bir taklit.
extension View {
    @ViewBuilder
    func glass<S: Shape>(in shape: S, interactive: Bool = true) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(interactive ? Glass.regular.interactive() : Glass.regular, in: shape)
        } else {
            self.fallbackGlass(in: shape)
        }
        #else
        self.fallbackGlass(in: shape)
        #endif
    }

    private func fallbackGlass<S: Shape>(in shape: S) -> some View {
        self
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 0.8))
    }
}

// MARK: - Pencere arka planı

// Pencerenin arkasındaki masaüstünü bulanıklaştıran AppKit görünümü.
// .behindWindow → pencerenin ARKASINDAKİ içeriği bulanıklaştırır (yarı saydam his buradan geliyor).
struct WindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// Görseldeki koyu zemin + sağ altta hafif mor parıltı.
struct PanelBackground: View {
    var body: some View {
        ZStack {
            WindowBlur()
            Color.black.opacity(0.25)
            RadialGradient(colors: [Color.purple.opacity(0.22), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 320)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Pencereyi sürükleme tutamacı

// Başlık çubuğunu kaldırdığımız için pencereyi tutup taşıyacak bir yer lazım.
// Bu görünüm boş alana tıklanınca sürüklemeyi AppKit'e devrediyor (performDrag).
// Sadece üst çubuğun boşluklarına koyuyoruz, böylece saatin üstünde çizim yapınca pencere kaymıyor.
struct WindowDragHandle: NSViewRepresentable {
    final class HandleView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> NSView { HandleView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
