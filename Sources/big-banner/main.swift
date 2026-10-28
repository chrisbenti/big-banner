import AppKit

var args = Array(CommandLine.arguments.dropFirst())
// Everything after a bare "--" is literal message text, never parsed as flags.
var literalText: [String] = []
if let i = args.firstIndex(of: "--") {
    literalText = Array(args[(i + 1)...])
    args = Array(args[..<i])
}

if args.contains("--help") || args.contains("-h") {
    print("""
    Usage: big-banner [options] [--] <message>

    Displays a full-screen attention banner with flashing colors and an alarm sound.
    Grabs and holds keyboard focus until dismissed.
    Dismiss by clicking anywhere or pressing any key.

    Options:
      --no-sheet      Show a floating banner instead of a full-screen overlay
      --no-bell       Suppress the repeating Ping alarm sound
      --pause         Pause media playback while the banner is shown (resumes on dismiss)
      --super <text>  Smaller line shown above the message
      --sub <text>    Smaller line shown below the message
      --verbose       Print debug log messages to stdout
      --help, -h      Show this help message
      --              Treat everything after it as message text, even if it looks like a flag

    Themes (pick one; if several are given, the last wins; default is --primary):
      --primary       Flashing blue/sky blue
      --secondary     Flashing purple/lavender
      --tertiary      Flashing green/lime
      --danger        Flashing red/yellow (use for urgent alerts)
      --monochrome    Static black/white, no flashing
    Colors are defined in Sources/big-banner/Themes.swift.

    Super and sub headers:
      Both are optional and independent: use either, both, or neither.
      A missing or empty/whitespace-only value hides that line.
      They render at a fixed size (shrinking only if a line is too wide for
      the banner), centered above/below the main message. The main message
      is sized independently to fill the remaining space, but never below
      24pt; longer text is truncated with an ellipsis instead.

    Examples:
      big-banner "STAND UP"
      big-banner --danger --super "BUILD FAILED" --sub "main @ c85d485" "DEPLOY BLOCKED"
      big-banner --tertiary --sub "all checks passed" "MERGED"
    """)
    exit(0)
}

// Take valued flags first so a value like "--danger" is never misread as a flag.
let superText = takeValue(for: "--super")
let subText = takeValue(for: "--sub")

let showSheet = !args.contains("--no-sheet")
args.removeAll { $0 == "--no-sheet" }
let playBell = !args.contains("--no-bell")
args.removeAll { $0 == "--no-bell" }
let pauseMedia = args.contains("--pause")
args.removeAll { $0 == "--pause" }
let verbose = args.contains("--verbose")
args.removeAll { $0 == "--verbose" }
// Last theme flag wins.
let theme = args.compactMap { arg in Themes.all.first { $0.flag == arg } }.last ?? Themes.default
args.removeAll { arg in Themes.all.contains { $0.flag == arg } }

func takeValue(for flag: String) -> String? {
    guard let i = args.firstIndex(of: flag) else { return nil }
    args.remove(at: i)
    guard i < args.count else { return nil }
    let value = args.remove(at: i).trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
}
let text = (args + literalText).joined(separator: " ")

func log(_ msg: String) {
    guard verbose else { return }
    print("[big-banner] \(msg)")
}
guard !text.isEmpty else {
    print("Usage: banner <text>")
    exit(1)
}

let bellInterval: TimeInterval = 0.0

// MARK: - Media Control

class MediaController {
    private typealias MRSendCommand  = @convention(c) (Int, CFDictionary?) -> Bool
    private typealias MRGetIsPlaying = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void

    private let sendCommand:  MRSendCommand?
    private let getIsPlaying: MRGetIsPlaying?
    private var didPause = false

    private let kMRPlay  = 0
    private let kMRPause = 1

    init() {
        let handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_LAZY
        )
        sendCommand = dlsym(handle, "MRMediaRemoteSendCommand")
            .map { unsafeBitCast($0, to: MRSendCommand.self) }
        getIsPlaying = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying")
            .map { unsafeBitCast($0, to: MRGetIsPlaying.self) }
    }

    func pauseIfPlaying() {
        guard let send = sendCommand, let getIsPlaying = getIsPlaying else {
            log("MediaController: missing symbols, skipping pause")
            return
        }
        let semaphore = DispatchSemaphore(value: 0)
        var isPlaying = false
        getIsPlaying(DispatchQueue.global()) { playing in
            isPlaying = playing
            semaphore.signal()
        }
        semaphore.wait()
        log("MediaController: isPlaying=\(isPlaying)")
        guard isPlaying else { return }
        let result = send(kMRPause, nil)
        log("MediaController: pause returned \(result)")
        if result { didPause = true }
    }

    func resumeIfPaused() {
        log("MediaController: resumeIfPaused called, didPause=\(didPause)")
        guard didPause, let send = sendCommand else { return }
        log("MediaController: sending play command")
        let result = send(kMRPlay, nil)
        log("MediaController: play returned \(result)")
        didPause = false
    }
}

let mediaController: MediaController? = pauseMedia ? MediaController() : nil
log("pauseMedia=\(pauseMedia)")
mediaController?.pauseIfPlaying()

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var bellSound: NSSound?
    var bellTimer: Timer?
    var flashTimer: Timer?
    var flashState = false
    var bgView: NSView?
    var bannerLabels: [NSTextField] = []
    var focusTimer: Timer?
    var observers: [NSObjectProtocol] = []

    func seizeFocus() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if playBell {
            bellSound = NSSound(contentsOfFile: "/System/Library/Sounds/Ping.aiff", byReference: false)
            log("Bell: playing (initial)")
            bellSound?.play()
            let timer = Timer(timeInterval: bellInterval, repeats: true) { [weak self] _ in
                guard let sound = self?.bellSound else { return }
                log("Bell: timer fired, isPlaying=\(sound.isPlaying)")
                guard !sound.isPlaying else { return }
                log("Bell: playing (repeat)")
                sound.play()
            }
            RunLoop.main.add(timer, forMode: .common)
            bellTimer = timer
        }
        let screen = NSScreen.main!
        let screenWidth = screen.frame.width
        let screenHeight = screen.frame.height

        let bannerWidth = screenWidth * 0.66
        let bannerHeight = screenHeight * 0.33
        let menuBarHeight: CGFloat = 25
        let windowWidth = showSheet ? screenWidth : bannerWidth
        let windowHeight = showSheet ? screenHeight + menuBarHeight : bannerHeight
        let padding: CGFloat = 32
        let availableWidth = bannerWidth - padding * 2
        let availableHeight = bannerHeight - padding * 2

        func makeLabel(_ string: String) -> NSTextField {
            let label = NSTextField(labelWithString: string)
            label.textColor = theme.fgA
            label.isEditable = false
            label.isBordered = false
            label.drawsBackground = false
            label.alignment = .center
            label.preferredMaxLayoutWidth = availableWidth
            return label
        }

        let label = makeLabel(text)
        let superLabel = superText.map(makeLabel)
        let subLabel = subText.map(makeLabel)
        bannerLabels = [superLabel, label, subLabel].compactMap { $0 }

        func sfProFont(size: CGFloat) -> NSFont {
            NSFont(name: "SFMono-Bold", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .bold)
        }

        // Super/sub lines size independently of the main text: each uses the
        // largest size up to secondaryMaxSize that fits on one line.
        let secondaryMaxSize: CGFloat = 16
        let lineGap: CGFloat = 8

        func fitSecondary(_ l: NSTextField) {
            l.maximumNumberOfLines = 1
            l.lineBreakMode = .byClipping
            var size = secondaryMaxSize
            while size > 10 {
                l.font = sfProFont(size: size)
                l.sizeToFit()
                if l.frame.width <= availableWidth { return }
                size -= 2
            }
            l.font = sfProFont(size: size)
            l.sizeToFit()
        }

        for l in bannerLabels where l !== label { fitSecondary(l) }
        let secondaryHeight = bannerLabels
            .filter { $0 !== label }
            .reduce(CGFloat(0)) { $0 + $1.frame.height + lineGap }

        // Main text takes whatever space the secondary lines leave.
        let mainAvailableHeight = availableHeight - secondaryHeight
        func layoutMain(size: CGFloat) -> (width: CGFloat, height: CGFloat) {
            label.font = sfProFont(size: size)
            label.preferredMaxLayoutWidth = availableWidth
            label.sizeToFit()
            return (label.frame.width, label.frame.height)
        }

        // The main text never shrinks below minMainSize; past that it is truncated.
        let minMainSize: CGFloat = 24
        var bestFitSize: CGFloat = minMainSize
        for testSize in stride(from: Int(minMainSize), through: 200, by: 2) {
            let size = CGFloat(testSize)
            let fit = layoutMain(size: size)
            if fit.width <= availableWidth && fit.height <= mainAvailableHeight {
                bestFitSize = size
            } else {
                break
            }
        }
        let finalFit = layoutMain(size: bestFitSize)
        if finalFit.height > mainAvailableHeight {
            // Even the minimum size overflows: keep only the lines that fit, ending in an ellipsis.
            let lineHeight = ceil(label.font!.ascender - label.font!.descender + label.font!.leading)
            label.maximumNumberOfLines = max(1, Int(mainAvailableHeight / lineHeight))
            label.lineBreakMode = .byTruncatingTail
            label.sizeToFit()
        }
        let stackHeight = bannerLabels.enumerated().reduce(CGFloat(0)) {
            $0 + $1.element.frame.height + ($1.offset > 0 ? lineGap : 0)
        }

        let contentSize = NSSize(width: windowWidth, height: windowHeight)

        let origin = NSPoint(
            x: showSheet ? 0 : (screenWidth - bannerWidth) / 2,
            y: showSheet ? -menuBarHeight : (screenHeight - bannerHeight) / 2
        )

        window = NSWindow(
            contentRect: NSRect(origin: origin, size: contentSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window?.level = showSheet ? .screenSaver : .floating
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.ignoresMouseEvents = false
        window?.hasShadow = false
        window?.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let contentView = NSView(frame: NSRect(origin: .zero, size: contentSize))
        window?.contentView = contentView

        if showSheet {
            let sheet = NSView(frame: NSRect(origin: .zero, size: contentSize))
            sheet.wantsLayer = true
            sheet.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.40).cgColor
            contentView.addSubview(sheet)
        }

        let bg = NSView(frame: NSRect(
            x: showSheet ? (windowWidth - bannerWidth) / 2 : 0,
            y: showSheet ? (windowHeight - bannerHeight) / 2 : 0,
            width: bannerWidth,
            height: bannerHeight
        ))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = theme.bgA.cgColor
        bg.layer?.cornerRadius = 12
        bgView = bg

        var cursorY = (bannerHeight + stackHeight) / 2
        for (i, l) in bannerLabels.enumerated() {
            cursorY -= l.frame.height + (i > 0 ? lineGap : 0)
            l.frame = NSRect(x: padding, y: cursorY, width: availableWidth, height: l.frame.height)
            bg.addSubview(l)
        }
        contentView.addSubview(bg)

        window?.makeKeyAndOrderFront(nil)

        let resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            log("Window resigned key, reseizing focus")
            self?.seizeFocus()
        }
        let activateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            log("Another application activated, reseizing focus")
            self?.seizeFocus()
        }
        observers = [resignObserver, activateObserver]

        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if !NSApp.isActive || self.window?.isKeyWindow != true {
                self.seizeFocus()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        focusTimer = timer

        if theme.flashes {
            let timer = Timer(timeInterval: 0.55, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.flashState.toggle()
                let nextBg = self.flashState ? theme.bgB : theme.bgA
                let nextFg = self.flashState ? theme.fgB : theme.fgA
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.12)
                self.bgView?.layer?.backgroundColor = nextBg.cgColor
                CATransaction.commit()
                self.bannerLabels.forEach { $0.textColor = nextFg }
            }
            RunLoop.main.add(timer, forMode: .common)
            flashTimer = timer
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        bellTimer?.invalidate()
        flashTimer?.invalidate()
        focusTimer?.invalidate()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        bellSound?.stop()
        mediaController?.resumeIfPaused()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)

NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { _ in
    app.terminate(nil)
    return nil
}

NSEvent.addLocalMonitorForEvents(matching: .keyDown) { _ in
    app.terminate(nil)
    return nil
}

app.activate(ignoringOtherApps: true)
app.run()
