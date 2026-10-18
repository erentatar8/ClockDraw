import AppKit

// Giriş noktası: SwiftUI `App` yapısını tamamen bıraktık, uygulamayı saf AppKit ile başlatıyoruz.
//
// Neden: SwiftUI `App` en az bir Scene ister. Biz de içi boş bir `Settings` sahnesi
// koymuştuk. Ama uygulama Dock'suz (.accessory) çalışıp başka pencere bulamayınca SwiftUI
// o boş "ClockDraw Settings" penceresini açıyordu. Arayüzün tamamı zaten AppDelegate'teki
// NSPanel'de olduğu için Scene'e hiç ihtiyacımız yok; SwiftUI'ı sadece panelin içini
// çizmek için (NSHostingView) kullanıyoruz.
@main
@MainActor   // AppKit nesneleri yalnızca ana iş parçacığında oluşturulmalı
enum ClockDrawMain {
    // delegate'i statik tutuyoruz: NSApplication.delegate "weak" bir referans,
    // güçlü bir sahibi olmazsa bellekten silinir.
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()          // olay döngüsü; uygulama kapanana kadar burada kalır
    }
}
