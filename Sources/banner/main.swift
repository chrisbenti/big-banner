import AppKit

let text = CommandLine.arguments.dropFirst().joined(separator: " ")
guard !text.isEmpty else {
    print("Usage: banner <text>")
    exit(1)
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screen = NSScreen.main!
        let screenWidth = screen.frame.width
        let screenHeight = screen.frame.height

        let windowWidth = screenWidth * 0.66
        let windowHeight = screenHeight * 0.33
        let padding: CGFloat = 32
        let availableWidth = windowWidth - padding * 2
        let availableHeight = windowHeight - padding * 2

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
            x: (screenWidth - windowWidth) / 2,
            y: (screenHeight - windowHeight) / 2
        )

        window = NSWindow(
            contentRect: NSRect(origin: origin, size: contentSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window?.level = .floating
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.ignoresMouseEvents = false
        window?.hasShadow = false
        window?.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let bg = NSView(frame: NSRect(origin: .zero, size: contentSize))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        bg.layer?.cornerRadius = 12

        label.frame = NSRect(
            x: padding,
            y: (windowHeight - label.frame.height) / 2,
            width: availableWidth,
            height: label.frame.height
        )
        bg.addSubview(label)
        window?.contentView = bg

        window?.makeKeyAndOrderFront(nil)
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
