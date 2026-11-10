import SwiftUI
import AppKit

/// Everything a widget needs to draw itself inside a dock.
struct WidgetContext {
    var item: DockItem
    var profileID: UUID
    var height: CGFloat
    var accent: Color

    var instance: WidgetInstance { item.widget ?? WidgetInstance(kind: .clock) }
    var kind: WidgetKind { instance.kind }
    var id: UUID { item.id }

    /// Widgets scale with the dock's icon size so a small dock stays readable.
    var scale: CGFloat { max(0.72, min(1.35, height / 48)) }
    func pt(_ base: CGFloat) -> CGFloat { (base * scale).rounded() }
}

/// The rounded plate every widget sits on.
struct WidgetPlate<Content: View>: View {
    var context: WidgetContext
    var tint: Color?
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, context.pt(9))
            .padding(.vertical, context.pt(5))
            .frame(height: context.height, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: context.pt(13), style: .continuous)
                    .fill(Color.black.opacity(0.28))
                    .overlay(
                        RoundedRectangle(cornerRadius: context.pt(13), style: .continuous)
                            .fill((tint ?? .clear).opacity(0.16))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: context.pt(13), style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: context.pt(13), style: .continuous))
    }
}

struct WidgetCaption: View {
    var text: String
    var context: WidgetContext
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: context.pt(8), weight: .semibold, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.5))
            .lineLimit(1)
    }
}

struct WidgetValue: View {
    var text: String
    var context: WidgetContext
    var size: CGFloat = 17
    var weight: Font.Weight = .semibold
    var body: some View {
        Text(text)
            .font(.system(size: context.pt(size), weight: weight, design: .rounded))
            .foregroundStyle(.white)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// A tiny sparkline used by the activity, network and revenue widgets.
struct Sparkline: View {
    var values: [Double]
    var color: Color
    var filled: Bool = true

    var body: some View {
        GeometryReader { geo in
            let pts = normalized(in: geo.size)
            ZStack {
                if filled, pts.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        for pt in pts { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.45), color.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
                }
                if pts.count > 1 {
                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func normalized(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let maxV = max(values.max() ?? 1, 0.0001)
        let minV = min(values.min() ?? 0, maxV - 0.0001)
        let span = max(maxV - minV, 0.0001)
        return values.enumerated().map { i, v in
            let x = size.width * CGFloat(i) / CGFloat(values.count - 1)
            let y = size.height * (1 - CGFloat((v - minV) / span))
            return CGPoint(x: x, y: y)
        }
    }
}

/// A ring gauge — focus timer, battery, hydration and activity all use it.
struct RingGauge: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 3.5
    var track: Double = 0.16

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(track), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: progress)
        }
    }
}

/// Small pill button used inside widgets.
struct WidgetButton: View {
    var symbol: String
    var context: WidgetContext
    var prominent: Bool = false
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: context.pt(prominent ? 11 : 9), weight: .bold))
                .foregroundStyle(.white.opacity(prominent ? 1 : 0.75))
                .frame(width: context.pt(prominent ? 22 : 18),
                       height: context.pt(prominent ? 22 : 18))
                .background(
                    Circle().fill(Color.white.opacity(hovering ? 0.22 : (prominent ? 0.14 : 0.08)))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Router

struct DockWidgetView: View {
    var context: WidgetContext

    var body: some View {
        switch context.kind {
        case .clock:           ClockWidget(context: context)
        case .worldClock:      WorldClockWidget(context: context)
        case .stopwatch:       StopwatchWidget(context: context)
        case .focusTimer:      FocusTimerWidget(context: context)
        case .countdown:       CountdownWidget(context: context)
        case .alarm:           AlarmWidget(context: context)
        case .timeProgress:    TimeProgressWidget(context: context)
        case .calendar:        CalendarWidget(context: context)
        case .reminders:       RemindersWidget(context: context)
        case .nowPlaying:      NowPlayingWidget(context: context)
        case .stickyNote:      StickyNoteWidget(context: context)
        case .hydration:       HydrationWidget(context: context)
        case .weather:         WeatherWidget(context: context)
        case .battery:         BatteryWidget(context: context)
        case .systemActivity:  SystemActivityWidget(context: context)
        case .networkActivity: NetworkActivityWidget(context: context)
        case .airDrop:         AirDropWidget(context: context)
        case .shortcut:        ShortcutWidget(context: context)
        case .recentApps:      RecentAppsWidget(context: context)
        case .volume:          VolumeWidget(context: context)
        case .keepAwake:       KeepAwakeWidget(context: context)
        case .diskSpace:       DiskSpaceWidget(context: context)
        case .bluetoothBattery: BluetoothBatteryWidget(context: context)
        case .screenshot:      ScreenshotWidget(context: context)
        case .clipboard:       ClipboardWidget(context: context)
        case .stripe, .paddle: RevenueWidget(context: context)
        }
    }
}
