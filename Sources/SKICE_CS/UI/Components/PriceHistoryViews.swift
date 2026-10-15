import SwiftUI

/// Compact signed-percentage trend badge with an arrow, colored by direction.
public struct PriceTrendBadge: View {
    public let trend: PriceTrend?

    public init(trend: PriceTrend?) {
        self.trend = trend
    }

    public var body: some View {
        Group {
            if let trend, let percent = trend.changePercent {
                let value = NSDecimalNumber(decimal: percent).doubleValue
                HStack(spacing: 2) {
                    Image(systemName: value > 0 ? "arrowtriangle.up.fill" : (value < 0 ? "arrowtriangle.down.fill" : "minus"))
                        .font(.system(size: 7, weight: .bold))
                    Text(Self.formatPercent(percent))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(
                    value > 0 ? AppTheme.Colors.statusSuccess
                        : (value < 0 ? AppTheme.Colors.statusDanger : AppTheme.Colors.textSecondary)
                )
            } else {
                EmptyView()
            }
        }
    }

    /// Signed percentage string: "+3.2%", "-1.1%", or "0.0%".
    public static func formatPercent(_ percent: Decimal) -> String {
        let value = NSDecimalNumber(decimal: percent).doubleValue
        if value > 0 { return String(format: "+%.1f%%", value) }
        if value < 0 { return String(format: "%.1f%%", value) }
        return "0.0%"
    }
}

/// Minimal line sparkline for a small sequence of values, with a faint area fill.
public struct PriceSparkline: View {
    public let values: [Double]
    public var color: Color = AppTheme.Colors.statusSuccess

    public init(values: [Double], color: Color = AppTheme.Colors.statusSuccess) {
        self.values = values
        self.color = color
    }

    public var body: some View {
        GeometryReader { geo in
            let size = geo.size
            if values.count >= 2 {
                let minV = values.min() ?? 0
                let maxV = values.max() ?? 1
                let span = max(maxV - minV, 0.0001)
                let points = Self.points(values: values, minV: minV, span: span, size: size)

                ZStack {
                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: first)
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                    Path { path in
                        guard let first = points.first, let last = points.last else { return }
                        path.move(to: CGPoint(x: first.x, y: size.height))
                        path.addLine(to: first)
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                        path.addLine(to: CGPoint(x: last.x, y: size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.28), color.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            } else if values.count == 1 {
                Circle()
                    .fill(color)
                    .frame(width: 3, height: 3)
                    .position(x: size.width / 2, y: size.height / 2)
            }
        }
    }

    private static func points(values: [Double], minV: Double, span: Double, size: CGSize) -> [CGPoint] {
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let x = CGFloat(index) * stepX
            let y = size.height * (1 - CGFloat((value - minV) / span))
            return CGPoint(x: x, y: y)
        }
    }
}

/// Detail-sheet panel: 7d / 30d deltas plus a small 30-day sparkline.
public struct PriceHistorySection: View {
    public let marketHashName: String
    public let historyStore: PriceHistoryStore

    @State private var trend7: PriceTrend?
    @State private var trend30: PriceTrend?

    public init(marketHashName: String, historyStore: PriceHistoryStore = .shared) {
        self.marketHashName = marketHashName
        self.historyStore = historyStore
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PRICE HISTORY")
                .font(AppTheme.Fonts.sectionTitle)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            HStack(spacing: 12) {
                deltaTile(label: "7D", trend: trend7)
                deltaTile(label: "30D", trend: trend30)
            }

            if let spark = trend30, spark.samples.count >= 2 {
                PriceSparkline(values: spark.sparklineValues, color: sparklineColor)
                    .frame(height: 44)
            } else {
                Text("Not enough history yet — the trend appears after a couple of refreshes.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.1))
        )
        .task(id: marketHashName) {
            trend7 = historyStore.trend(for: marketHashName, days: 7)
            trend30 = historyStore.trend(for: marketHashName, days: 30)
        }
    }

    private var sparklineColor: Color {
        guard let percent = trend30?.changePercent else { return AppTheme.Colors.textSecondary }
        if percent > 0 { return AppTheme.Colors.statusSuccess }
        if percent < 0 { return AppTheme.Colors.statusDanger }
        return AppTheme.Colors.textSecondary
    }

    private func deltaTile(label: String, trend: PriceTrend?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.Colors.textSecondary)

            if let trend, let percent = trend.changePercent {
                let value = NSDecimalNumber(decimal: percent).doubleValue
                Text(PriceTrendBadge.formatPercent(percent))
                    .font(.system(size: 16, weight: .heavy, design: .monospaced))
                    .foregroundStyle(
                        value > 0 ? AppTheme.Colors.statusSuccess
                            : (value < 0 ? AppTheme.Colors.statusDanger : .white)
                    )
                if let abs = trend.absoluteChange {
                    Text(signedEuro(abs))
                        .font(.caption2.weight(.semibold).monospaced())
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            } else {
                Text("—")
                    .font(.system(size: 16, weight: .heavy, design: .monospaced))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.07))
        )
    }

    private func signedEuro(_ value: Decimal) -> String {
        if value > 0 { return "+" + PriceFormatter.eur(value) }
        return PriceFormatter.eur(value)
    }
}
