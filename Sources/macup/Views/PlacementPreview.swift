import SwiftUI

/// Tiny visual icon showing where a single WindowPlacement sits on a screen.
public struct PlacementMiniIcon: View {
    public let placement: WindowPlacement
    public var width: CGFloat = 24
    public var height: CGFloat = 16

    public init(placement: WindowPlacement, width: CGFloat = 24, height: CGFloat = 16) {
        self.placement = placement
        self.width = width
        self.height = height
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.secondary.opacity(0.6), lineWidth: 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.08)))

            if let norm = placement.normalizedRect {
                let inset: CGFloat = 2
                let innerW = max(0, width - inset * 2)
                let innerH = max(0, height - inset * 2)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: max(2, innerW * norm.width), height: max(2, innerH * norm.height))
                    .offset(x: inset + innerW * norm.origin.x, y: inset + innerH * norm.origin.y)
            }
        }
        .frame(width: width, height: height)
    }
}

/// Visual miniature monitor preview showing all enabled apps arranged on a DesktopLayout.
public struct DesktopLayoutPreview: View {
    public let apps: [AppLaunchItem]

    private let palette: [Color] = [
        .blue, .purple, .teal, .orange, .pink, .green, .indigo
    ]

    public init(apps: [AppLaunchItem]) {
        self.apps = apps
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let padding: CGFloat = 6
            let innerW = max(1, w - padding * 2)
            let innerH = max(1, h - padding * 2)

            ZStack(alignment: .topLeading) {
                // Monitor background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    )

                // Subtle 2x2 guide lines
                Path { path in
                    path.move(to: CGPoint(x: w / 2, y: padding))
                    path.addLine(to: CGPoint(x: w / 2, y: h - padding))
                    path.move(to: CGPoint(x: padding, y: h / 2))
                    path.addLine(to: CGPoint(x: w - padding, y: h / 2))
                }
                .stroke(style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                .foregroundStyle(Color.secondary.opacity(0.25))

                let activeApps = apps.filter { $0.isEnabled }
                if activeApps.isEmpty {
                    Text("No apps placed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: w, height: h)
                } else {
                    ForEach(Array(activeApps.enumerated()), id: \.element.id) { idx, app in
                        let norm = app.placement.normalizedRect ?? CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
                        let color = palette[idx % palette.count]
                        let rectW = max(18, innerW * norm.width - 3)
                        let rectH = max(16, innerH * norm.height - 3)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.opacity(0.22))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(color.opacity(0.85), lineWidth: 1.2)
                            )
                            .overlay(
                                Text(app.appName)
                                    .font(.system(size: 9, weight: .semibold))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .padding(.horizontal, 3)
                                    .foregroundStyle(.primary)
                            )
                            .frame(width: rectW, height: rectH)
                            .offset(
                                x: padding + innerW * norm.origin.x + 1.5,
                                y: padding + innerH * norm.origin.y + 1.5
                            )
                    }
                }
            }
        }
        .frame(height: 112)
    }
}
