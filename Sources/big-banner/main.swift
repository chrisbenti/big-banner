import AppKit
import CoreAudio

var args = Array(CommandLine.arguments.dropFirst())
let showSheet = !args.contains("--no-sheet")
args.removeAll { $0 == "--no-sheet" }
let playBell = !args.contains("--no-bell")
args.removeAll { $0 == "--no-bell" }
let pauseMedia = !args.contains("--no-pause")
args.removeAll { $0 == "--no-pause" }
let text = args.joined(separator: " ")
guard !text.isEmpty else {
    print("Usage: banner <text>")
    exit(1)
}

if playBell {
    if let sound = NSSound(contentsOfFile: "/System/Library/Sounds/Glass.aiff", byReference: false) {
        sound.play()
    }
}

// MARK: - Media Control

class MediaController {
    private typealias MRSendCommand = @convention(c) (Int, CFDictionary?) -> Bool
    private let sendCommand: MRSendCommand?
    private var didPause = false

    private let kMRPlay  = 0
    private let kMRPause = 1

    init() {
        let handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_LAZY
        )
        if let sym = dlsym(handle, "MRMediaRemoteSendCommand") {
            sendCommand = unsafeBitCast(sym, to: MRSendCommand.self)
        } else {
            sendCommand = nil
        }
    }

    // Returns true if any process is actively outputting audio.
    private func isAudioPlaying() -> Bool {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID
        ) == noErr, deviceID != kAudioDeviceUnknown else { return false }

        var isRunning = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            deviceID, &addr, 0, nil, &size, &isRunning
        ) == noErr else { return false }

        return isRunning != 0
    }

    func pauseIfPlaying() {
        guard isAudioPlaying(), let send = sendCommand else { return }
        if send(kMRPause, nil) {
            didPause = true
        }
    }

    func resumeIfPaused() {
        guard didPause, let send = sendCommand else { return }
        _ = send(kMRPlay, nil)
        didPause = false
    }
}

let mediaController: MediaController? = pauseMedia ? MediaController() : nil
mediaController?.pauseIfPlaying()

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        label.textColor = .white
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.alignment = .center

        var bestFitSize: CGFloat = 12

        for testSize in stride(from: 12, through: 200, by: 2) {
            let size = CGFloat(testSize)
            label.font = .systemFont(ofSize: size, weight: .bold)
            label.preferredMaxLayoutWidth = availableWidth
            label.sizeToFit()

            if label.frame.width <= availableWidth && label.frame.height <= availableHeight {
                bestFitSize = size
            } else {
                break
            }
        }

        label.font = .systemFont(ofSize: bestFitSize, weight: .bold)
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
        bg.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        bg.layer?.cornerRadius = 12

        label.frame = NSRect(
            x: padding,
            y: (bannerHeight - label.frame.height) / 2,
            width: availableWidth,
            height: label.frame.height
        )
        bg.addSubview(label)
        contentView.addSubview(bg)

        window?.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
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
