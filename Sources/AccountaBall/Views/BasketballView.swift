import SwiftUI

struct BasketballView: View {
    var size: CGFloat = 60
    var showFace: BallFace = .none
    var rotation: Double = 0

    enum BallFace {
        case none, happy, angry, calm
    }

    var body: some View {
        ZStack {
            // Base orange circle
            Circle()
                .fill(Color.orange)
                .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 1))

            // Basketball seam lines
            basketballSeams

            // Face overlay
            if showFace != .none {
                faceOverlay
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(rotation))
    }

    private var basketballSeams: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var path = Path()
            // Horizontal equator
            path.move(to: CGPoint(x: 0, y: h / 2))
            path.addLine(to: CGPoint(x: w, y: h / 2))
            // Vertical center
            path.move(to: CGPoint(x: w / 2, y: 0))
            path.addLine(to: CGPoint(x: w / 2, y: h))
            // Left curve
            path.move(to: CGPoint(x: w * 0.25, y: 0))
            path.addCurve(to: CGPoint(x: w * 0.25, y: h),
                          control1: CGPoint(x: w * 0.5, y: h * 0.3),
                          control2: CGPoint(x: w * 0.5, y: h * 0.7))
            // Right curve
            path.move(to: CGPoint(x: w * 0.75, y: 0))
            path.addCurve(to: CGPoint(x: w * 0.75, y: h),
                          control1: CGPoint(x: w * 0.5, y: h * 0.3),
                          control2: CGPoint(x: w * 0.5, y: h * 0.7))
            ctx.stroke(path, with: .color(.black.opacity(0.7)), lineWidth: max(1.5, size.width / 30))
        }
    }

    private var faceOverlay: some View {
        VStack(spacing: size * 0.08) {
            HStack(spacing: size * 0.2) {
                Circle().fill(.black).frame(width: size * 0.12, height: size * 0.12)
                Circle().fill(.black).frame(width: size * 0.12, height: size * 0.12)
            }
            .offset(y: -size * 0.05)

            if showFace == .calm {
                Rectangle()
                    .fill(Color.black)
                    .frame(width: size * 0.30, height: max(1.5, size / 30))
            } else {
                Path { path in
                    if showFace == .happy {
                        path.addArc(center: CGPoint(x: size * 0.17, y: 0),
                                    radius: size * 0.17,
                                    startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                    } else {
                        path.addArc(center: CGPoint(x: size * 0.17, y: size * 0.1),
                                    radius: size * 0.17,
                                    startAngle: .degrees(0), endAngle: .degrees(180), clockwise: true)
                    }
                }
                .stroke(Color.black, lineWidth: max(1.5, size / 30))
                .frame(width: size * 0.34, height: size * 0.2)
            }
        }
    }
}
