import SwiftUI

public struct ForestCanvasView: View {
    public var progress: Double
    public var activeDays: Int
    public var seed: Int

    public init(progress: Double, activeDays: Int, seed: Int = 42) {
        self.progress = max(0, min(progress, 1))
        self.activeDays = activeDays
        self.seed = seed
    }

    public var body: some View {
        Canvas { context, size in
            let sky = Path(CGRect(origin: .zero, size: size))
            context.fill(sky, with: .linearGradient(
                Gradient(colors: [Color(red: 0.82, green: 0.93, blue: 0.90), Color(red: 0.47, green: 0.68, blue: 0.55)]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)
            ))

            drawSun(in: &context, size: size)
            drawMist(in: &context, size: size)
            drawGround(in: &context, size: size)

            let maxTrees = 95
            let treeCount = Int(8 + Double(maxTrees - 8) * progress)
            for layer in 0..<3 {
                let layerProgress = min(1, progress + Double(layer) * 0.15)
                let count = Int(Double(treeCount) * [0.30, 0.35, 0.35][layer])
                drawTreeLayer(layer, count: count, layerProgress: layerProgress, in: &context, size: size)
            }

            if progress >= 1.0 {
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.08)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(alignment: .topLeading) {
            Text(forestName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(radius: 5)
                .padding(18)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
    }

    private var forestName: String {
        switch progress {
        case 0..<0.25: "Quiet Clearing"
        case 0.25..<0.5: "Young Grove"
        case 0.5..<0.75: "Focus Forest"
        case 0.75..<1: "Deep Woods"
        default: "Ancient Deep Forest"
        }
    }

    private func drawSun(in context: inout GraphicsContext, size: CGSize) {
        let sunRect = CGRect(x: size.width * 0.74, y: size.height * 0.11, width: size.width * 0.18, height: size.width * 0.18)
        context.fill(Path(ellipseIn: sunRect), with: .color(Color(red: 1, green: 0.88, blue: 0.45).opacity(0.35 + progress * 0.25)))
    }

    private func drawMist(in context: inout GraphicsContext, size: CGSize) {
        for i in 0..<4 {
            let y = size.height * (0.28 + CGFloat(i) * 0.12)
            var path = Path()
            path.move(to: CGPoint(x: -20, y: y))
            path.addCurve(to: CGPoint(x: size.width + 20, y: y + 8), control1: CGPoint(x: size.width * 0.25, y: y - 18), control2: CGPoint(x: size.width * 0.65, y: y + 24))
            context.stroke(path, with: .color(.white.opacity(0.10)), lineWidth: 22)
        }
    }

    private func drawGround(in context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height * 0.78))
        path.addCurve(to: CGPoint(x: size.width, y: size.height * 0.76), control1: CGPoint(x: size.width * 0.32, y: size.height * 0.68), control2: CGPoint(x: size.width * 0.68, y: size.height * 0.86))
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        context.fill(path, with: .color(Color(red: 0.18, green: 0.36, blue: 0.20)))
    }

    private func drawTreeLayer(_ layer: Int, count: Int, layerProgress: Double, in context: inout GraphicsContext, size: CGSize) {
        let yBase = [0.60, 0.72, 0.84][layer] * size.height
        let minHeight = [34.0, 48.0, 62.0][layer]
        let maxHeight = [70.0, 96.0, 132.0][layer]
        let alpha = [0.34, 0.58, 0.88][layer]
        let darkness = 0.24 - progress * 0.10 - Double(layer) * 0.035
        let green = 0.45 - progress * 0.16 - Double(layer) * 0.05
        let color = Color(red: darkness, green: green, blue: 0.20).opacity(alpha)

        for i in 0..<count {
            var rng = SeededRandom(seed: UInt64(seed + layer * 1000 + i * 37))
            let daySlot = Int(Double(i % 7))
            let dayHasGrowth = daySlot < max(activeDays, Int(ceil(progress * 7)))
            if !dayHasGrowth && rng.nextDouble() > 0.18 { continue }

            let x = CGFloat(rng.nextDouble()) * size.width
            let h = CGFloat(minHeight + rng.nextDouble() * (maxHeight - minHeight)) * CGFloat(0.65 + layerProgress * 0.55)
            let w = h * CGFloat(0.38 + rng.nextDouble() * 0.15)
            let y = yBase + CGFloat(rng.nextDouble() * 24 - 12)
            drawPine(at: CGPoint(x: x, y: y), width: w, height: h, color: color, in: &context)
        }
    }

    private func drawPine(at base: CGPoint, width: CGFloat, height: CGFloat, color: Color, in context: inout GraphicsContext) {
        let trunk = CGRect(x: base.x - width * 0.055, y: base.y - height * 0.25, width: width * 0.11, height: height * 0.25)
        context.fill(Path(roundedRect: trunk, cornerRadius: width * 0.03), with: .color(Color(red: 0.20, green: 0.13, blue: 0.08).opacity(0.55)))

        for level in 0..<3 {
            let factor = CGFloat(1.0 - Double(level) * 0.22)
            let topY = base.y - height + CGFloat(level) * height * 0.23
            let bottomY = base.y - CGFloat(2 - level) * height * 0.16
            var p = Path()
            p.move(to: CGPoint(x: base.x, y: topY))
            p.addLine(to: CGPoint(x: base.x - width * factor, y: bottomY))
            p.addLine(to: CGPoint(x: base.x + width * factor, y: bottomY))
            p.closeSubpath()
            context.fill(p, with: .color(color))
        }
    }
}

struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0x12345678 : seed }
    mutating func nextDouble() -> Double {
        state = 2862933555777941757 &* state &+ 3037000493
        return Double((state >> 33) & 0xFFFF_FFFF) / Double(UInt32.max)
    }
}
