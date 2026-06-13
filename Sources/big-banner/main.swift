import AppKit

var args = Array(CommandLine.arguments.dropFirst())

if args.contains("--help") || args.contains("-h") {
    print("""
    Usage: big-banner [options] <message>

    Displays a full-screen attention banner with flashing colors and an alarm sound.
    Dismiss by clicking anywhere or pressing Escape.

    Options:
      --no-sheet      Show a floating banner instead of a full-screen overlay
      --no-bell       Suppress the repeating Ping alarm sound
      --pause         Pause media playback while the banner is shown (resumes on dismiss)
      --monochrome    Show a static black/white banner instead of flashing red/yellow
      --verbose       Print debug log messages to stdout
      --help, -h      Show this help message
    """)
    exit(0)
}

let showSheet = !args.contains("--no-sheet")
args.removeAll { $0 == "--no-sheet" }
let playBell = !args.contains("--no-bell")
args.removeAll { $0 == "--no-bell" }
let pauseMedia = args.contains("--pause")
args.removeAll { $0 == "--pause" }
let verbose = args.contains("--verbose")
args.removeAll { $0 == "--verbose" }
let monochrome = args.contains("--monochrome")
args.removeAll { $0 == "--monochrome" }
let text = args.joined(separator: " ")

// Flash colors — deep warning red and amber gold
let flashRedBg   = NSColor(red: 0.68, green: 0.09, blue: 0.07, alpha: 0.92)
let flashYellowBg = NSColor(red: 0.90, green: 0.68, blue: 0.03, alpha: 0.92)
let flashRedFg   = NSColor.white
let flashYellowFg = NSColor(red: 0.10, green: 0.07, blue: 0.01, alpha: 1.0)

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
    var bannerLabel: NSTextField?

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

        let label = NSTextField(labelWithString: text)
        label.textColor = monochrome ? .white : flashRedFg
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.alignment = .center
        bannerLabel = label

        var bestFitSize: CGFloat = 12

        func sfProFont(size: CGFloat) -> NSFont {
            NSFont(name: "SFMono-Bold", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .bold)
        }

        for testSize in stride(from: 12, through: 200, by: 2) {
            let size = CGFloat(testSize)
            label.font = sfProFont(size: size)
            label.preferredMaxLayoutWidth = availableWidth
            label.sizeToFit()

            if label.frame.width <= availableWidth && label.frame.height <= availableHeight {
                bestFitSize = size
            } else {
                break
            }
        }

        label.font = sfProFont(size: bestFitSize)
        label.preferredMaxLayoutWidth = availableWidth
        label.sizeToFit()

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
        bg.layer?.backgroundColor = monochrome
            ? NSColor.black.withAlphaComponent(0.85).cgColor
            : flashRedBg.cgColor
        bg.layer?.cornerRadius = 12
        bgView = bg

        label.frame = NSRect(
            x: padding,
            y: (bannerHeight - label.frame.height) / 2,
            width: availableWidth,
            height: label.frame.height
        )
        bg.addSubview(label)
        contentView.addSubview(bg)

        window?.makeKeyAndOrderFront(nil)

        if !monochrome {
            let timer = Timer(timeInterval: 0.55, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.flashState.toggle()
                let nextBg = self.flashState ? flashYellowBg : flashRedBg
                let nextFg = self.flashState ? flashYellowFg : flashRedFg
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.12)
                self.bgView?.layer?.backgroundColor = nextBg.cgColor
                CATransaction.commit()
                self.bannerLabel?.textColor = nextFg
            }
            RunLoop.main.add(timer, forMode: .common)
            flashTimer = timer
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        bellTimer?.invalidate()
        flashTimer?.invalidate()
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

NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
    if e.keyCode == 53 {
        app.terminate(nil)
    }
    return e
}

app.activate(ignoringOtherApps: true)
app.run()
