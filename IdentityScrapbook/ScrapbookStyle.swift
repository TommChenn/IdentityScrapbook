import SwiftUI

enum ScrapbookStyle {
    static let ink = Color(red: 0.18, green: 0.22, blue: 0.20)
    static let accent = Color(red: 0.24, green: 0.40, blue: 0.32)
    static let paper = Color(red: 0.98, green: 0.96, blue: 0.91)

    static func coverColor(_ style: String) -> Color {
        switch style {
        case "peach": Color(red: 0.88, green: 0.66, blue: 0.53)
        case "lavender": Color(red: 0.72, green: 0.69, blue: 0.82)
        default: Color(red: 0.64, green: 0.74, blue: 0.60)
        }
    }
}

struct ScrapbookPaper: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            dark ? Color(red: 0.14, green: 0.17, blue: 0.16) : ScrapbookStyle.paper
            Canvas { context, size in
                var lines = Path()
                for x in stride(from: 0.0, through: size.width, by: 24) {
                    lines.move(to: CGPoint(x: x, y: 0))
                    lines.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: 0.0, through: size.height, by: 24) {
                    lines.move(to: CGPoint(x: 0, y: y))
                    lines.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(lines, with: .color(dark ? .white.opacity(0.045) : ScrapbookStyle.ink.opacity(0.055)), lineWidth: 0.5)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ScrapbookTape: View {
    var angle: Double = -4
    var body: some View {
        Rectangle()
            .fill(Color(red: 0.80, green: 0.70, blue: 0.48).opacity(0.55))
            .overlay {
                HStack(spacing: 5) {
                    ForEach(0..<10, id: \.self) { _ in
                        Rectangle().fill(.white.opacity(0.14)).frame(width: 1)
                    }
                }
            }
            .frame(width: 76, height: 22)
            .rotationEffect(.degrees(angle))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct ScrapbookCover: View {
    let name: String
    let style: String
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Image(systemName: "leaf").font(.title2)
                Spacer()
                Image(systemName: "sparkle").font(.caption)
            }
            .accessibilityHidden(true)
            Text(name)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 18).padding(.horizontal, 12)
                .background(ScrapbookStyle.paper.opacity(0.88), in: RoundedRectangle(cornerRadius: 2))
                .overlay(alignment: .top) { ScrapbookTape(angle: -3).offset(y: -10) }
            HStack {
                Rectangle().frame(width: 28, height: 1)
                Text("cover.subtitle").font(.caption2)
            }
            .accessibilityHidden(true)
        }
        .foregroundStyle(ScrapbookStyle.ink)
        .padding(.leading, 28).padding(.trailing, 18).padding(.vertical, 24)
        .frame(maxWidth: .infinity, minHeight: textSize.isAccessibilitySize ? 0 : 240, alignment: .topLeading)
        .background(ScrapbookStyle.coverColor(style), in: UnevenRoundedRectangle(
            topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 12, topTrailingRadius: 12))
        .overlay(alignment: .leading) {
            Rectangle().fill(.black.opacity(0.12)).frame(width: 10)
                .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.28)).frame(width: 1) }
        }
        .overlay(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 2).fill(ScrapbookStyle.paper.opacity(0.6))
                .frame(width: 3).padding(.vertical, 10).padding(.trailing, 3)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.12), radius: 3, x: 2, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }
}

struct MemoryPaper<Content: View>: View {
    let color: Color
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(ScrapbookStyle.ink)
            .background(color, in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(ScrapbookStyle.ink.opacity(0.08)))
            .compositingGroup()
            .shadow(color: .black.opacity(0.09), radius: 3, x: 1, y: 4)
    }
}
