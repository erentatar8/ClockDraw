import SwiftUI

// Dilim: kadranda iki saat arasındaki pasta dilimi.
// Açılar "tur kesri" olarak tutuluyor: 0 = 12, 0.25 = 3, 0.5 = 6, 0.75 = 9.
// 12 saatlik kadranda 1 tur = 720 dakika.
struct Wedge: Identifiable, Codable {
    var id = UUID()
    var start: Double       // başlangıç (tur kesri, 0..1)
    var span: Double        // saat yönünde genişlik (0..1)
    var colorIndex: Int

    var minutes: Int { Int((span * 720).rounded()) }

    // Nokta dilimin içinde mi? İki koşul: kadranın içinde olmalı VE açısı
    // [start, start+span] aralığına düşmeli. Aralık 12'nin üstünden taşabilir
    // (ör. 11'den 1'e), o yüzden farkı mod 1 alıyoruz.
    func contains(_ p: CGPoint) -> Bool {
        guard hypot(p.x - 0.5, p.y - 0.5) <= clockRadius else { return false }
        return positiveMod(turnFraction(of: p) - start) <= span
    }
}

// Kadranın normalize yarıçapı. ClockFace'te R = side/2 · 0.94 → 0.47
let clockRadius: CGFloat = 0.47

// Normalize noktanın merkeze göre açısı, tur kesri olarak.
//   atan2(dy, dx)   → −π..π, 0 = sağ (3), ekranda y aşağı arttığı için artış = saat yönü
//   + π/2           → 0'ı tepeye (12) taşı
//   / 2π, mod 1     → 0..1
func turnFraction(of p: CGPoint) -> Double {
    let a = atan2(Double(p.y - 0.5), Double(p.x - 0.5))
    return positiveMod((a + .pi / 2) / (2 * .pi))
}

func positiveMod(_ x: Double) -> Double { x - floor(x) }

// 1 tur = 144 adet 5 dakika → en yakın 5 dakikaya yuvarla
func snapToFiveMinutes(_ f: Double) -> Double { (f * 144).rounded() / 144 }

func durationText(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    switch (h, m) {
    case (0, _): return "\(m)m"
    case (_, 0): return "\(h)h"
    default:     return "\(h)h \(m)m"
    }
}

// Dilimi verilen Canvas'a çizer. side: tahtanın piksel kenarı.
func drawWedge(_ w: Wedge, in ctx: GraphicsContext, side: CGFloat) {
    let color = DrawingModel.palette[w.colorIndex]
    let c = CGPoint(x: side / 2, y: side / 2)
    let R = clockRadius * side

    func pt(_ f: Double, _ r: CGFloat) -> CGPoint {
        let a = f * 2 * .pi - .pi / 2
        return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
    }

    // Yayı küçük doğru parçalarıyla örnekliyoruz (her ~1°'ye bir nokta).
    // Path.addArc'ın "clockwise" parametresi SwiftUI'ın ters y ekseninde kafa karıştırıcı;
    // noktaları kendimiz hesaplayınca yön garanti doğru.
    let steps = max(2, Int(w.span * 360))
    var path = Path()
    path.move(to: c)
    for i in 0...steps {
        path.addLine(to: pt(w.start + w.span * Double(i) / Double(steps), R))
    }
    path.closeSubpath()

    ctx.fill(path, with: .color(color.opacity(0.28)))
    ctx.stroke(path, with: .color(color.opacity(0.85)),
               style: StrokeStyle(lineWidth: side * 0.005, lineJoin: .round))

    // Süre etiketi: dilimin orta açısında, yarıçapın %55'inde.
    // 15 dk'dan dar dilimlere yazmıyoruz, sığmıyor.
    guard w.minutes >= 15 else { return }
    let label = Text(durationText(w.minutes))
        .font(.system(size: side * 0.042, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
    ctx.draw(label, at: pt(w.start + w.span / 2, R * 0.55))
}
