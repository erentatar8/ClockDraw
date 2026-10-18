import SwiftUI

struct ContentView: View {
    @ObservedObject var model: DrawingModel
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            ToolbarView(model: model, onClose: onClose)
            DrawingBoard(model: model)
                .aspectRatio(1, contentMode: .fit)   // tahta hep kare kalır
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Üstteki boşluğun sebebi: SwiftUI görünmez başlık çubuğunu (~28pt) "güvenli alan"
        // sayıp içeriği onun altından başlatıyordu. Güvenli alanı yok sayınca butonlar yukarı çıkıyor.
        .ignoresSafeArea()
        .background(PanelBackground())
        .preferredColorScheme(.dark)                 // görseldeki koyu tema
    }
}

// MARK: - Üst çubuk (eski başlık çubuğunun yerine)

struct ToolbarView: View {
    @ObservedObject var model: DrawingModel
    var onClose: () -> Void

    private let size: CGFloat = 36

    var body: some View {
        HStack(spacing: 10) {
            // Sol: kapat + raptiye (görseldeki gibi ayrı yuvarlak cam butonlar)
            circleButton("xmark", action: onClose)

            circleButton(model.isPinned ? "pin.fill" : "pin",
                         tint: model.isPinned ? .orange : .primary) {
                model.isPinned.toggle()
            }
            .help(model.isPinned ? "Unpin" : "Keep on top")

            // Orta: boşluk = pencereyi tutup taşıma alanı
            WindowDragHandle()
                .frame(maxWidth: .infinity, maxHeight: size)

            // Geri al / ileri al: kalemlerden ayrı kendi kapsülünde
            HStack(spacing: 2) {
                capsuleItem("arrow.uturn.backward", tint: .primary, selected: false,
                            action: model.undo)
                    .disabled(!model.canUndo)
                    .opacity(model.canUndo ? 1 : 0.35)
                    .help("Undo (⌘Z or two-finger double-tap)")
                capsuleItem("arrow.uturn.forward", tint: .primary, selected: false,
                            action: model.redo)
                    .disabled(!model.canRedo)
                    .opacity(model.canRedo ? 1 : 0.35)
                    .help("Redo (⇧⌘Z)")
            }
            .padding(.horizontal, 6)
            .frame(height: size)
            .glass(in: Capsule())

            // Sağ: kalemler + silgi tek bir cam kapsülde, aralarında ince ayraç
            HStack(spacing: 2) {
                // Renk seçimi hem kalem hem dilim için geçerli.
                // Dilim aracı açıkken renge basarsan dilimde kalırsın, sadece renk değişir.
                ForEach(DrawingModel.palette.indices, id: \.self) { i in
                    capsuleItem("pencil.tip",
                                tint: DrawingModel.palette[i],
                                selected: model.tool != .eraser && model.colorIndex == i) {
                        if model.tool == .eraser { model.tool = .pen }
                        model.colorIndex = i
                    }
                }
                Divider().frame(height: 16).opacity(0.5)
                capsuleItem("chart.pie.fill",
                            tint: model.tool == .wedge ? DrawingModel.palette[model.colorIndex] : .primary,
                            selected: model.tool == .wedge) {
                    model.tool = model.tool == .wedge ? .pen : .wedge
                }
                .help("Time block: drag from one time to another (snaps to 5 min)")
                capsuleItem("eraser", tint: .primary, selected: model.tool == .eraser) {
                    model.tool = .eraser
                }
            }
            .padding(.horizontal, 6)
            .frame(height: size)
            .glass(in: Capsule())

            circleButton("trash", action: model.clear)
                .help("Clear all")
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func circleButton(_ icon: String, tint: Color = .primary,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glass(in: Circle())
    }

    private func capsuleItem(_ icon: String, tint: Color, selected: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(selected ? Color.white.opacity(0.16) : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Çizim tahtası (saat + çizim katmanı)

struct DrawingBoard: View {
    @ObservedObject var model: DrawingModel

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)

            ZStack {
                ClockFace()

                Canvas { ctx, size in
                    // Önce dilimler (altta), sonra çizgiler (üstte)
                    let wedges = model.wedges + (model.currentWedge.map { [$0] } ?? [])
                    for w in wedges { drawWedge(w, in: ctx, side: size.width) }

                    let all = model.strokes + (model.current.map { [$0] } ?? [])
                    for stroke in all { draw(stroke, in: ctx, side: size.width) }
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(
                // minimumDistance: 0 → tek tık da nokta olarak çizilsin
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        // piksel → normalize: (x/side, y/side)
                        model.dragChanged(to: CGPoint(x: v.location.x / side,
                                                      y: v.location.y / side))
                    }
                    .onEnded { _ in model.dragEnded() }
            )
        }
    }

    // normalize → piksel: (x·side, y·side). Kalınlık da side'a oranlı.
    private func draw(_ stroke: Stroke, in ctx: GraphicsContext, side: CGFloat) {
        let color = DrawingModel.palette[stroke.colorIndex]
        let width = side * 0.012
        let pts = stroke.points.map { CGPoint(x: $0.x * side, y: $0.y * side) }

        if pts.count == 1 {
            let p = pts[0]
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - width / 2, y: p.y - width / 2,
                                            width: width, height: width)),
                     with: .color(color))
            return
        }

        var path = Path()
        path.addLines(pts)
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
}
