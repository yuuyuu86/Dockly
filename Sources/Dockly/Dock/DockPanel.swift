import AppKit
import SwiftUI
import Combine

/// A borderless, non-activating panel. Clicking a dock tile must never steal
/// focus from whatever the user is working in.
final class DockPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
        worksWhenModal = true
    }
}

/// Root view that forwards two-finger swipes and tracks the pointer for
/// auto-hide, then hands everything else to SwiftUI.
final class DockRootView: NSView {
    var onSwipe: ((Int) -> Void)?
    var onMouseInside: ((Bool) -> Void)?

    private var scrollAccumulator: CGFloat = 0
    private var lastSwipe = Date.distantPast
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    override func mouseEntered(with event: NSEvent) { onMouseInside?(true) }
    override func mouseExited(with event: NSEvent) { onMouseInside?(false) }

    override func scrollWheel(with event: NSEvent) {
        // Only trackpad gestures switch setups; a mouse wheel scrolls normally.
        guard event.hasPreciseScrollingDeltas else { super.scrollWheel(with: event); return }
        if event.phase == .began { scrollAccumulator = 0 }
        scrollAccumulator += event.scrollingDeltaY

        if abs(scrollAccumulator) > 26, Date().timeIntervalSince(lastSwipe) > 0.45 {
            lastSwipe = Date()
            onSwipe?(scrollAccumulator > 0 ? -1 : 1)
            scrollAccumulator = 0
        }
        if event.phase == .ended || event.momentumPhase == .ended { scrollAccumulator = 0 }
    }
}

// MARK: - One dock window

/// A single dock on a single display. Everything about placement, auto-hide
/// and measurement is per-window, because two displays can want different
/// answers at the same moment.
@MainActor
final class DockWindow {
    /// nil means "whichever display the pointer is on".
    let screenID: String?

    let panel: DockPanel
    private let hosting: NSHostingView<AnyView>
    private let root: DockRootView
    private let store = DocklyStore.shared

    private var contentSize = CGSize(width: 200, height: 68)
    private(set) var isHidden = false
    private var pointerInside = false
    private var hideWork: DispatchWorkItem?

    /// Just above the system Dock. Sitting any higher would put Dockly over
    /// other apps' menus, popovers and alerts, which a dock has no business
    /// covering.
    static let dockLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)

    init(screenID: String?) {
        self.screenID = screenID

        root = DockRootView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        hosting = NSHostingView(rootView: AnyView(EmptyView()))
        if #available(macOS 13.0, *) { hosting.sizingOptions = [.intrinsicContentSize] }
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = root.bounds
        root.addSubview(hosting)

        panel = DockPanel(contentRect: root.frame)
        panel.contentView = root
        panel.level = Self.dockLevel
        panel.orderFrontRegardless()

        root.onSwipe = { [weak self] delta in
            guard let self, self.store.activeProfile.appearance.swipeToSwitch else { return }
            self.store.cycle(by: delta)
        }
        root.onMouseInside = { [weak self] inside in
            guard let self, inside != self.pointerInside else { return }
            self.pointerInside = inside
            self.evaluateAutoHide()
        }
    }

    func close() {
        hideWork?.cancel()
        panel.orderOut(nil)
    }

    // MARK: Content

    func update(profile: DockProfile, banner: String?) {
        if !panel.isVisible { panel.orderFrontRegardless() }
        hosting.rootView = AnyView(
            DockContainerView(profile: profile, banner: banner)
                .environmentObject(store))
        panel.level = Self.dockLevel
        evaluateAutoHide()
        DispatchQueue.main.async { [weak self] in self?.measureNow() }
    }

    // MARK: Measurement

    func measureNow() {
        hosting.layoutSubtreeIfNeeded()
        // `fittingSize` is the *minimum* that satisfies the constraints, which
        // squeezes any widget that declares a minWidth. The intrinsic size is
        // what SwiftUI actually wants, so prefer it and keep fittingSize only
        // as a fallback.
        let intrinsic = hosting.intrinsicContentSize
        let fitting = hosting.fittingSize
        let size = CGSize(width: max(intrinsic.width, fitting.width),
                          height: max(intrinsic.height, fitting.height))
        guard size.width > 1, size.height > 1 else { return }

        let rounded = CGSize(width: ceil(size.width), height: ceil(size.height))
        guard abs(rounded.width - contentSize.width) > 0.5
                || abs(rounded.height - contentSize.height) > 0.5 else { return }
        contentSize = rounded
        reposition()
    }

    // MARK: Placement

    func targetScreen() -> NSScreen {
        if let screenID,
           let match = NSScreen.screens.first(where: { $0.docklyID == screenID }) {
            return match
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    func reposition(animated: Bool = false) {
        let a = store.activeProfile.appearance
        let screen = targetScreen()
        let visible = screen.visibleFrame
        let size = contentSize
        let margin = CGFloat(a.screenMargin)

        var origin = CGPoint.zero
        switch a.edge {
        case .bottom, .top:
            switch a.alignment {
            case .start:  origin.x = visible.minX + margin
            case .center: origin.x = visible.midX - size.width / 2
            case .end:    origin.x = visible.maxX - size.width - margin
            }
            origin.y = a.edge == .bottom ? visible.minY + margin
                                         : visible.maxY - size.height - margin
        case .left, .right:
            switch a.alignment {
            case .start:  origin.y = visible.maxY - size.height - margin
            case .center: origin.y = visible.midY - size.height / 2
            case .end:    origin.y = visible.minY + margin
            }
            origin.x = a.edge == .left ? visible.minX + margin
                                       : visible.maxX - size.width - margin
        }

        if isHidden {
            origin = hiddenOrigin(base: origin, size: size, edge: a.edge, screen: screen)
        }

        let frame = NSRect(origin: origin, size: size)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func hiddenOrigin(base: CGPoint, size: CGSize,
                              edge: DockEdge, screen: NSScreen) -> CGPoint {
        let peek: CGFloat = 3
        var p = base
        let f = screen.frame
        switch edge {
        case .bottom: p.y = f.minY - size.height + peek
        case .top:    p.y = f.maxY - peek
        case .left:   p.x = f.minX - size.width + peek
        case .right:  p.x = f.maxX - peek
        }
        return p
    }

    // MARK: Pointer and auto-hide

    /// Tracking areas miss the case where the dock slides out from under a
    /// pointer that never entered it, so the position is checked directly.
    func trackPointer() {
        let p = NSEvent.mouseLocation

        if isHidden {
            guard pointerIsAtRevealEdge(p) else { return }
            // Treat the reveal as "the pointer is on the dock", so moving away
            // is a real transition and the dock tucks itself back in.
            pointerInside = true
            setHidden(false)
            return
        }
        // A little slack keeps the dock from flickering at its own edge.
        let inside = NSPointInRect(p, panel.frame.insetBy(dx: -4, dy: -4))
        guard inside != pointerInside else { return }
        pointerInside = inside
        evaluateAutoHide()
    }

    /// True when the pointer has reached the screen edge this dock hides
    /// against, across the stretch the dock occupies.
    func pointerIsAtRevealEdge(_ p: CGPoint) -> Bool {
        let a = store.activeProfile.appearance
        let screen = targetScreen()
        guard NSPointInRect(p, screen.frame) else { return false }

        let f = screen.frame
        let hot: CGFloat = 4
        let slack: CGFloat = 24
        let frame = panel.frame
        switch a.edge {
        case .bottom:
            return p.y <= f.minY + hot
                && p.x >= frame.minX - slack && p.x <= frame.maxX + slack
        case .top:
            return p.y >= f.maxY - hot
                && p.x >= frame.minX - slack && p.x <= frame.maxX + slack
        case .left:
            return p.x <= f.minX + hot
                && p.y >= frame.minY - slack && p.y <= frame.maxY + slack
        case .right:
            return p.x >= f.maxX - hot
                && p.y >= frame.minY - slack && p.y <= frame.maxY + slack
        }
    }

    func evaluateAutoHide() {
        let mode = store.activeProfile.appearance.hideMode
        hideWork?.cancel()

        switch mode {
        case .never:
            setHidden(false)
        case .auto:
            if pointerInside { setHidden(false) }
            else {
                let work = DispatchWorkItem { [weak self] in
                    guard let self, !self.pointerInside else { return }
                    self.setHidden(true)
                }
                hideWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
            }
        case .whenFullScreen:
            setHidden(!pointerInside && isFrontAppFullScreen())
        }
    }

    private func isFrontAppFullScreen() -> Bool {
        let screen = targetScreen()
        // A full-screen app leaves no menu bar gap in its visible frame.
        return abs(screen.frame.height - screen.visibleFrame.height) < 1
    }

    func setHidden(_ hidden: Bool) {
        guard hidden != isHidden else { return }
        isHidden = hidden
        reposition(animated: true)
    }

    func revealForAMoment() {
        panel.orderFrontRegardless()
        setHidden(false)
        pointerInside = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self else { return }
            self.pointerInside = false
            self.evaluateAutoHide()
        }
    }
}

// MARK: - Controller

@MainActor
final class DockPanelController {
    static let shared = DockPanelController()

    private var windows: [DockWindow] = []
    private let store = DocklyStore.shared
    private var cancellables = Set<AnyCancellable>()
    private var revealMonitor: Any?
    private var measureTimer: Timer?

    private init() {}

    // MARK: Lifecycle

    func start() {
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                // A display coming or going changes how many docks there are.
                self?.refresh()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                for w in self.windows {
                    w.panel.orderFrontRegardless()
                    w.reposition()
                }
            }
            .store(in: &cancellables)

        installRevealMonitor()
        refresh()
        startMeasuringLoop()
    }

    // MARK: Which docks should exist

    /// One entry per dock window: a screen id, or nil for "follow the pointer".
    private func desiredScreens() -> [String?] {
        let profile = store.activeProfile
        guard store.library.settings.mode.showsCustomDock, profile.customDockEnabled else {
            return []
        }
        guard let id = profile.appearance.screenID else { return [nil] }
        if id == DockAppearance.everyScreen {
            return NSScreen.screens.map { $0.docklyID }
        }
        // A display that is no longer attached falls back to following the
        // pointer rather than leaving the user with no dock at all.
        guard NSScreen.screens.contains(where: { $0.docklyID == id }) else { return [nil] }
        return [id]
    }

    func refresh() {
        let wanted = desiredScreens()

        // Close docks that are no longer wanted.
        for window in windows where !wanted.contains(where: { $0 == window.screenID }) {
            window.close()
        }
        windows.removeAll { window in !wanted.contains(where: { $0 == window.screenID }) }

        // Open the ones that are missing.
        for id in wanted where !windows.contains(where: { $0.screenID == id }) {
            windows.append(DockWindow(screenID: id))
        }

        let profile = store.activeProfile
        for window in windows {
            window.update(profile: profile, banner: store.switchBanner)
        }
    }

    private func startMeasuringLoop() {
        measureTimer = everySecond(0.35) { [weak self] in
            guard let self else { return }
            for window in self.windows {
                window.measureNow()
                window.trackPointer()
            }
        }
    }

    /// A fast path for the same check the timer makes — when the app is
    /// allowed to observe global mouse events, the dock slides back the
    /// instant the pointer touches the edge rather than on the next tick.
    private func installRevealMonitor() {
        revealMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            guard let self else { return }
            let point = NSEvent.mouseLocation
            for window in self.windows where window.isHidden {
                if window.pointerIsAtRevealEdge(point) { window.trackPointer() }
            }
        }
    }

    // MARK: External control

    func reposition(animated: Bool = false) {
        for window in windows { window.reposition(animated: animated) }
    }

    func toggleVisibility() {
        for window in windows {
            if window.panel.isVisible { window.panel.orderOut(nil) }
            else { window.panel.orderFrontRegardless() }
        }
    }

    func bringToFront() {
        for window in windows {
            window.panel.orderFrontRegardless()
            window.setHidden(false)
        }
    }

    /// Reveals every dock and keeps them up for a moment, so a keyboard or
    /// menu bar command is not undone by the auto-hide timer a beat later.
    func reveal() {
        if windows.isEmpty { refresh() }
        for window in windows { window.revealForAMoment() }
    }

    /// Where the dock on a given screen currently sits, for anchoring stacks.
    func frame(onScreenContaining point: CGPoint) -> CGRect? {
        windows.first { NSPointInRect(point, $0.panel.frame.insetBy(dx: -200, dy: -200)) }?
            .panel.frame
    }
}

extension NSScreen {
    /// A stable-enough identifier to remember which display a setup lives on.
    var docklyID: String {
        if let n = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "screen-\(n.intValue)"
        }
        return "screen-\(Int(frame.origin.x))x\(Int(frame.origin.y))"
    }

    var docklyName: String {
        if #available(macOS 14.0, *) { return localizedName }
        return "Display \(docklyID)"
    }
}


