import SwiftUI
import Combine

enum Tool { case pen, wedge, eraser }

// Noktalar PİKSEL değil, 0–1 arası NORMALİZE koordinat olarak tutuluyor.
// Pencere 300px de olsa 800px de olsa (0.5, 0.5) her zaman saatin merkezi.
// Böylece boyutlandırınca çizimler saatle birlikte ölçeklenir.
// Codable: JSON'a yazılıp okunabilsin diye. CGPoint zaten Codable.
// id'yi `var` yaptık; `let id = UUID()` olsaydı decode ederken dosyadaki id yok sayılırdı.
struct Stroke: Identifiable, Codable {
    var id = UUID()
    var points: [CGPoint]
    var colorIndex: Int
}

// Tahtanın tamamı: hem kayıt dosyası hem de geri alma adımları bu yapıyı saklar.
struct Drawing: Codable {
    var strokes: [Stroke] = []
    var wedges: [Wedge] = []
}

final class DrawingModel: ObservableObject {
    static let palette: [Color] = [.red, .blue, .green]

    @Published var strokes: [Stroke] = []
    @Published var wedges: [Wedge] = []
    @Published var current: Stroke?
    @Published var currentWedge: Wedge?
    @Published var tool: Tool = .pen
    @Published var colorIndex = 0
    @Published var isPinned = false

    private var drawing: Drawing {
        get { Drawing(strokes: strokes, wedges: wedges) }
        set { strokes = newValue.strokes; wedges = newValue.wedges }
    }

    // MARK: Otomatik kayıt
    // Kaydet butonu yok: tahta her değiştiğinde dosyaya yazılır, açılışta okunur.
    // Temizleyip kapatırsan dosyaya boş tahta yazılır, açılışta boş gelir.
    // Konum: ~/Library/Application Support/ClockDraw/strokes.json
    private static let saveURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClockDraw", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("strokes.json")
    }()

    // Uygulamanın eski adı SaatPlan'dı. Yeni dosya henüz yoksa son çizimi oradan okuyoruz;
    // ilk değişiklikte yeni konuma yazılır, böylece isim değişikliğinde çizim kaybolmaz.
    private static let legacyURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("SaatPlan/strokes.json")

    private var cancellables = Set<AnyCancellable>()

    init() {
        let url = FileManager.default.fileExists(atPath: Self.saveURL.path) ? Self.saveURL : Self.legacyURL
        if let data = try? Data(contentsOf: url) {
            if let saved = try? JSONDecoder().decode(Drawing.self, from: data) {
                drawing = saved
            } else if let old = try? JSONDecoder().decode([Stroke].self, from: data) {
                strokes = old   // eski sürümün dosyası sadece çizgi dizisiydi
            }
        }
        // debounce: değişiklikler 0.4 sn durulunca tek seferde diske yazılır.
        // dropFirst: açılışta okuduğumuz değeri hemen geri yazmaya gerek yok.
        Publishers.CombineLatest($strokes, $wedges)
            .dropFirst()
            .debounce(for: .seconds(0.4), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
    }

    // .atomic: önce geçici dosyaya yazar, sonra yerine taşır → çökme dosyayı bozmaz.
    func save() {
        guard let data = try? JSONEncoder().encode(drawing) else { return }
        try? data.write(to: Self.saveURL, options: .atomic)
    }

    // MARK: Geri al / ileri al
    // "Anlık görüntü yığını": her değişiklikten ÖNCE tahtanın kopyası undoStack'e itilir.
    // Drawing bir struct (değer tipi), kopya gerçekten bağımsızdır.
    @Published private(set) var undoStack: [Drawing] = []
    @Published private(set) var redoStack: [Drawing] = []
    private let historyLimit = 100

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private func snapshot() {
        undoStack.append(drawing)
        if undoStack.count > historyLimit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(drawing)
        drawing = prev
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(drawing)
        drawing = next
    }

    // MARK: Sürükleme durumu

    private enum EraseTarget { case undecided, strokes, wedges }
    private var eraseTarget = EraseTarget.undecided
    private var erasedThisDrag = false

    private var wedgeAnchor = 0.0   // sürüklemenin başladığı açı (tur kesri, 5 dk'ya yapışık)
    private var wedgeLast = 0.0     // bir önceki olaydaki açı
    private var wedgeTotal = 0.0    // başlangıçtan beri toplam dönüş (işaretli: + saat yönü)

    func dragChanged(to p: CGPoint) {
        switch tool {
        case .pen:
            if current == nil {
                current = Stroke(points: [p], colorIndex: colorIndex)
            } else {
                current?.points.append(p)
            }

        case .wedge:
            let f = turnFraction(of: p)
            guard currentWedge != nil else {
                wedgeAnchor = snapToFiveMinutes(f)
                wedgeLast = f
                wedgeTotal = 0
                currentWedge = Wedge(start: wedgeAnchor, span: 0, colorIndex: colorIndex)
                return
            }
            // Açıyı "sarmadan açma" (unwrapping): iki olay arasındaki farkı [-0.5, 0.5]
            // aralığına indiriyoruz. Böylece 12'nin üstünden geçerken 0.99 → 0.01 sıçraması
            // +0.02 olarak okunur, −0.98 olarak değil. Farkları toplayınca da toplam dönüşü
            // buluyoruz; işareti yönü veriyor.
            var d = f - wedgeLast
            d -= d.rounded()
            wedgeLast = f
            wedgeTotal = max(-0.999, min(0.999, wedgeTotal + d))

            let t = snapToFiveMinutes(wedgeTotal)
            // Saat yönünün tersine çektiysen dilimi ters çevir: bitişi başlangıç yap.
            currentWedge?.start = t >= 0 ? wedgeAnchor : positiveMod(wedgeAnchor + t)
            currentWedge?.span = abs(t)

        case .eraser:
            // Sürüklemenin ilk temasında neyi sildiğimize karar veriyoruz.
            // Yoksa dilimin içindeki bir çizgiyi silerken dilim de giderdi.
            if eraseTarget == .undecided {
                if strokes.contains(where: { $0.isHit(by: p, radius: 0.025) }) {
                    eraseTarget = .strokes
                } else if wedges.contains(where: { $0.contains(p) }) {
                    eraseTarget = .wedges
                } else {
                    return
                }
            }
            // Tek bir silgi sürüklemesi = tek bir geri alma adımı.
            switch eraseTarget {
            case .strokes:
                guard strokes.contains(where: { $0.isHit(by: p, radius: 0.025) }) else { return }
                if !erasedThisDrag { snapshot(); erasedThisDrag = true }
                strokes.removeAll { $0.isHit(by: p, radius: 0.025) }
            case .wedges:
                guard wedges.contains(where: { $0.contains(p) }) else { return }
                if !erasedThisDrag { snapshot(); erasedThisDrag = true }
                wedges.removeAll { $0.contains(p) }
            case .undecided:
                break
            }
        }
    }

    func dragEnded() {
        if let c = current {
            snapshot()
            strokes.append(c)
        }
        if let w = currentWedge, w.span > 0 {
            snapshot()
            wedges.append(w)
        }
        current = nil
        currentWedge = nil
        erasedThisDrag = false
        eraseTarget = .undecided
    }

    func clear() {
        guard !strokes.isEmpty || !wedges.isEmpty else { return }
        snapshot()          // "hepsini temizle" de geri alınabilir
        drawing = Drawing()
        current = nil
        currentWedge = nil
    }
}

extension Stroke {
    // Bir çizgi, ardışık noktalar arasındaki doğru parçalarından oluşur.
    // İmleç herhangi bir parçaya r'den yakınsa → vuruldu.
    func isHit(by p: CGPoint, radius r: CGFloat) -> Bool {
        if points.count == 1 {
            return hypot(points[0].x - p.x, points[0].y - p.y) < r
        }
        return zip(points, points.dropFirst()).contains { a, b in
            distance(from: p, toSegment: a, b) < r
        }
    }
}

// Noktanın doğru parçasına uzaklığı (lineer cebir: izdüşüm).
//   t = (AP · AB) / |AB|²   → P'nin AB doğrusu üzerindeki izdüşümünün parametresi
//   t'yi [0,1]'e kırp       → izdüşüm parçanın dışına düşerse en yakın uç noktaya yapış
//   uzaklık = |P − (A + t·AB)|
func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
    let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
    let ap = CGPoint(x: p.x - a.x, y: p.y - a.y)
    let len2 = ab.x * ab.x + ab.y * ab.y
    guard len2 > 0 else { return hypot(ap.x, ap.y) }
    let t = max(0, min(1, (ap.x * ab.x + ap.y * ab.y) / len2))
    let proj = CGPoint(x: a.x + t * ab.x, y: a.y + t * ab.y)
    return hypot(p.x - proj.x, p.y - proj.y)
}
