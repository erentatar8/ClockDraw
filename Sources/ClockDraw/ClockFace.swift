import SwiftUI

// Vektörel saat kadranı. Her şey `side`'a (karenin kenarı) oranla çiziliyor,
// o yüzden hangi boyutta olursa olsun keskin ve orantılı kalır.
struct ClockFace: View {
    var body: some View {
        // 30 saniyede bir yeniden çiz → "şimdi" işareti kendiliğinden ilerler
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Canvas { ctx, size in
                let side = min(size.width, size.height)
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let R = side / 2 * 0.94

                // Kadran çemberi
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R)),
                    with: .color(.primary), lineWidth: side * 0.008
                )

                // 60 çentik: her 5'te bir kalın (saat), diğerleri ince (dakika)
                for i in 0..<60 {
                    let major = i % 5 == 0
                    let a = angle(Double(i) / 60)
                    var tick = Path()
                    tick.move(to: point(c, R * (major ? 0.86 : 0.92), a))
                    tick.addLine(to: point(c, R * 0.98, a))
                    ctx.stroke(tick,
                               with: .color(.primary.opacity(major ? 0.9 : 0.35)),
                               lineWidth: side * (major ? 0.007 : 0.003))
                }

                // Rakamlar
                for h in 1...12 {
                    let label = Text("\(h)")
                        .font(.system(size: side * 0.07, weight: .medium, design: .rounded))
                    ctx.draw(label, at: point(c, R * 0.74, angle(Double(h) / 12)))
                }

                // Şimdiki zaman: kadran çemberinin üstünde iki boncuk
                //   mavi (küçük)  → dakika: m/60 tur
                //   turuncu (büyük) → saat: (h + m/60)/12 tur
                // Saat boncuğu gerçek akrep gibi davranıyor: 6:47'de 7'ye yakın durur, 6:00'da tam 6'da.
                let comps = Calendar.current.dateComponents([.hour, .minute], from: context.date)
                let h = Double((comps.hour ?? 0) % 12)
                let m = Double(comps.minute ?? 0)

                func bead(_ frac: Double, diameter d: CGFloat, color: Color) {
                    let p = point(c, R, angle(frac))           // tam çemberin üstünde
                    let rect = CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)
                    ctx.fill(Path(ellipseIn: rect), with: .color(color))
                    // ince koyu kenar: boncuk beyaz çemberin üstünde net ayrışsın
                    ctx.stroke(Path(ellipseIn: rect), with: .color(.black.opacity(0.35)),
                               lineWidth: side * 0.003)
                }

                // Önce dakika, sonra saat: üst üste gelirlerse (ör. 12:00) turuncu üstte kalır
                bead(m / 60,            diameter: side * 0.026, color: .blue)
                bead((h + m / 60) / 12, diameter: side * 0.042, color: .orange)

                // Merkez noktası: merkezden dilim çizerken referans olsun diye duruyor
                let cd = side * 0.02
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - cd / 2, y: c.y - cd / 2, width: cd, height: cd)),
                         with: .color(.primary))
            }
        }
    }
}

// Açı dönüşümü: f ∈ [0,1) tam turun kesri.
//   f · 2π      → radyan
//   − π/2       → 0 noktasını sağdan (3) tepeye (12) kaydır
// Ekran koordinatında y aşağı doğru arttığı için artan açı = saat yönü.
private func angle(_ f: Double) -> Double { f * 2 * .pi - .pi / 2 }

// Kutupsaldan kartezyene: (r, θ) → (cx + r·cosθ, cy + r·sinθ)
private func point(_ c: CGPoint, _ r: CGFloat, _ a: Double) -> CGPoint {
    CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
}
