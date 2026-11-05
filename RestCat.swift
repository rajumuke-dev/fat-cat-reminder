import Cocoa
import AVFoundation
import ServiceManagement

// MARK: - Config (override with env vars, in seconds, for testing)

func envSeconds(_ key: String, _ def: Int) -> Int {
    Int(ProcessInfo.processInfo.environment[key] ?? "") ?? def
}

let workLimit = envSeconds("REST_WORK", 25 * 60)     // Pomodoro: rest after 25 min of active work
let waterLimit = envSeconds("REST_WATER", 40 * 60)   // hydrate every 40 min of active work
let restBreak = envSeconds("REST_BREAK", 5 * 60)     // short break length
let waterBreak = envSeconds("REST_WATER_BREAK", 30)  // sip break length
let idleReset = envSeconds("REST_IDLE", 3 * 60)      // idle this long == you already rested
let snoozeSeconds = 5 * 60

enum Kind {
    case rest, water

    var titles: [String] {
        switch self {
        case .rest: return ["Take a rest, hooman!", "Step away from the screen!", "Stretch. Blink. Breathe."]
        case .water: return ["💧 Go drink some water!", "💧 Hydration time, hooman!", "💧 Time for a drink!"]
        }
    }
    var subtitles: [String] {
        switch self {
        case .rest: return ["Look at something 20 feet away and stand up for a bit. The cat insists.",
                            "You have been working hard. Walk around, stretch your neck and shoulders."]
        case .water: return ["Get up, grab a glass of water and drink. The cat is watching.",
                             "A few sips now keep the headache away. Go on, I'll wait."]
        }
    }
}

// MARK: - Overlay window (one per screen): transparent dim screen + real cat video with alpha

final class OverlayWindow: NSWindow {
    var onKey: ((NSEvent) -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func keyDown(with event: NSEvent) { onKey?(event) }
}

final class OverlayController {
    private var windows: [OverlayWindow] = []
    private var countdowns: [NSTextField] = []
    private var players: [AVQueuePlayer] = []
    private var loopers: [AVPlayerLooper] = []
    var onClose: ((Bool) -> Void)?   // true == snoozed

    init(kind: Kind, duration: Int) {
        let title = kind.titles.randomElement()!
        let sub = kind.subtitles.randomElement()!
        let sitURL = Bundle.main.url(forResource: "cat-sit", withExtension: "mov")
        let walkURL = Bundle.main.url(forResource: "cat-walk", withExtension: "mov")
        let settleURL = Bundle.main.url(forResource: "cat-settle", withExtension: "mov")
        for screen in NSScreen.screens {
            let w = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.isOpaque = false
            w.backgroundColor = NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.10, alpha: 0.6)
            w.hasShadow = false
            w.isReleasedWhenClosed = false
            w.onKey = { [weak self] e in if e.keyCode == 53 { self?.close(snoozed: false) } } // Esc

            let content = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            w.contentView = content

            content.wantsLayer = true
            if let sitURL, let root = content.layer {
                let sw = screen.frame.width * 0.7
                let (sit, sitSize) = videoLayer(sitURL)
                let sh = sw * sitSize.height / sitSize.width
                sit.bounds = CGRect(x: 0, y: 0, width: sw, height: sh)
                let rest = CGPoint(x: screen.frame.midX - screen.frame.minX, y: screen.frame.height * 0.04 + sh / 2)
                sit.position = rest
                root.addSublayer(sit)

                if let walkURL, let settleURL {
                    sit.opacity = 0
                    // all three clips share one framing, so they line up at the rest point
                    let (walk, _) = videoLayer(walkURL)
                    let (settle, _) = videoLayer(settleURL, loop: false, autoplay: false)
                    for l in [walk, settle] { l.bounds = sit.bounds; root.addSublayer(l) }
                    settle.position = rest
                    settle.opacity = 0
                    let ww = sw, wh = sh
                    let W = screen.frame.width
                    // the clip's cat faces left: walk in from the right edge, left across the screen, back right, then to the middle
                    let high = wh / 2 + screen.frame.height * 0.10
                    let pts = [CGPoint(x: W + ww / 2, y: rest.y), CGPoint(x: W * 0.28, y: high),
                               CGPoint(x: W * 0.72, y: rest.y), rest]
                    let dists = (1..<pts.count).map { hypot(pts[$0].x - pts[$0 - 1].x, pts[$0].y - pts[$0 - 1].y) }
                    let total = dists.reduce(0, +)
                    let duration = total / (W * 0.17)   // points per second of walking speed
                    var times: [NSNumber] = [0], acc: CGFloat = 0
                    for d in dists { acc += d; times.append(NSNumber(value: Double(acc / total))) }
                    let move = CAKeyframeAnimation(keyPath: "position")
                    move.values = pts.map { NSValue(point: $0) }
                    move.keyTimes = times
                    move.duration = duration
                    move.fillMode = .forwards
                    move.isRemovedOnCompletion = false
                    walk.add(move, forKey: "walk")
                    // face left on legs 1 and 3, right on leg 2
                    let flip = CAKeyframeAnimation(keyPath: "transform.scale.x")
                    flip.values = [1, -1, 1]
                    flip.keyTimes = [0, times[1], times[2]]
                    flip.calculationMode = .discrete
                    flip.duration = duration
                    flip.fillMode = .forwards
                    flip.isRemovedOnCompletion = false
                    walk.add(flip, forKey: "flip")
                    let settleLength = AVURLAsset(url: settleURL).duration.seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                        walk.opacity = 0
                        settle.opacity = 1
                        settle.player?.play()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration + settleLength - 0.05) {
                        settle.opacity = 0
                        sit.opacity = 1
                    }
                }
            }

            let t = label(title, size: 72, weight: .heavy)
            let s = label(sub, size: 24, weight: .medium, alpha: 0.9)
            let c = label(fmt(duration), size: 44, weight: .bold, alpha: 0.95)
            let skip = NSButton(title: "I'm done  (Esc)", target: self, action: #selector(skipTapped))
            let snooze = NSButton(title: "Snooze 5 min", target: self, action: #selector(snoozeTapped))
            [skip, snooze].forEach { $0.bezelStyle = .rounded; $0.controlSize = .large }
            let buttons = NSStackView(views: [snooze, skip]); buttons.spacing = 16
            let top = NSStackView(views: [t, s, c, buttons]); top.orientation = .vertical; top.spacing = 10
            top.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(top)
            top.centerXAnchor.constraint(equalTo: content.centerXAnchor).isActive = true
            top.topAnchor.constraint(equalTo: content.topAnchor, constant: screen.frame.height * 0.06).isActive = true
            s.preferredMaxLayoutWidth = screen.frame.width * 0.7
            windows.append(w); countdowns.append(c)
        }
    }

    private func videoLayer(_ url: URL, loop: Bool = true, autoplay: Bool = true) -> (AVPlayerLayer, CGSize) {
        let size = AVURLAsset(url: url).tracks(withMediaType: .video).first?.naturalSize ?? CGSize(width: 16, height: 9)
        let player = AVQueuePlayer()
        player.isMuted = true
        if loop {
            loopers.append(AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url)))
        } else {
            player.insert(AVPlayerItem(url: url), after: nil)
        }
        players.append(player)
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        if autoplay { player.play() }
        return (layer, size)
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat = 1) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = NSFont.systemFont(ofSize: size, weight: weight)
        l.textColor = NSColor.white.withAlphaComponent(alpha)
        l.alignment = .center
        l.isSelectable = false
        return l
    }

    private func fmt(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        windows.forEach { $0.alphaValue = 0; $0.orderFrontRegardless() }
        windows.first?.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.6
            windows.forEach { $0.animator().alphaValue = 1 }
        }
    }

    func update(remaining: Int) { countdowns.forEach { $0.stringValue = fmt(max(0, remaining)) } }

    @objc private func skipTapped() { close(snoozed: false) }
    @objc private func snoozeTapped() { close(snoozed: true) }

    func close(snoozed: Bool) {
        guard !windows.isEmpty else { return }
        let ws = windows
        windows = []
        players.forEach { $0.pause() }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            ws.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { ws.forEach { $0.orderOut(nil) } })
        onClose?(snoozed)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var activeSeconds = 0
    var waterSeconds = 0
    var paused = false
    var overlay: OverlayController?
    var overlayRemaining = 0
    var timer: Timer?
    let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let pauseItem = NSMenuItem(title: "Pause reminders", action: #selector(togglePause), keyEquivalent: "p")
    let loginItem = NSMenuItem(title: "Launch at login", action: #selector(toggleLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ n: Notification) {
        let quit = NSMenuItem(title: "Quit Fat Cat Reminder", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let credit = NSMenuItem(title: "Cat video: FASTILY, CC BY-SA 4.0 (Wikimedia Commons)", action: nil, keyEquivalent: "")
        let items = [statusLine, .separator(),
                     NSMenuItem(title: "Rest break now", action: #selector(restNow), keyEquivalent: "r"),
                     NSMenuItem(title: "Water reminder now", action: #selector(waterNow), keyEquivalent: "w"),
                     pauseItem, loginItem, .separator(), credit, quit]
        let menu = NSMenu()
        items.forEach { menu.addItem($0); $0.target = $0 === quit ? NSApp : self }
        item.menu = menu
        item.button?.title = "🐱"
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off

        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)

        let args = CommandLine.arguments
        if args.contains("--rest-now") { show(.rest) }
        if args.contains("--water-now") { show(.water) }
    }

    func idleSeconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    func tick() {
        if let o = overlay {
            overlayRemaining -= 1
            o.update(remaining: overlayRemaining)
            if overlayRemaining <= 0 { o.close(snoozed: false) }
            return
        }
        if !paused {
            if idleSeconds() >= Double(idleReset) {
                activeSeconds = 0   // you were away: that counts as a rest
                waterSeconds = 0
            } else {
                activeSeconds += 1
                waterSeconds += 1
            }
            if activeSeconds >= workLimit { show(.rest) } else if waterSeconds >= waterLimit { show(.water) }
        }
        let rest = max(0, workLimit - activeSeconds), water = max(0, waterLimit - waterSeconds)
        statusLine.title = paused ? "Paused" : "Rest in \(rest / 60)m \(rest % 60)s · Water in \(water / 60)m"
        item.button?.title = paused ? "🐱 ⏸" : "🐱 \(rest / 60)m"
    }

    func show(_ kind: Kind) {
        guard overlay == nil else { return }
        overlayRemaining = kind == .rest ? restBreak : waterBreak
        let o = OverlayController(kind: kind, duration: overlayRemaining)
        o.onClose = { [weak self] snoozed in
            guard let self else { return }
            self.overlay = nil
            if snoozed {
                self.activeSeconds = max(0, workLimit - snoozeSeconds)
                self.waterSeconds = max(0, waterLimit - snoozeSeconds)
            } else if kind == .rest {
                self.activeSeconds = 0
                self.waterSeconds = 0
            } else {
                self.waterSeconds = 0
            }
        }
        overlay = o
        o.show()
    }

    @objc func restNow() { show(.rest) }
    @objc func waterNow() { show(.water) }
    @objc func togglePause() { paused.toggle(); pauseItem.title = paused ? "Resume reminders" : "Pause reminders" }
    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch { NSLog("Login item change failed: \(error.localizedDescription)") }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
