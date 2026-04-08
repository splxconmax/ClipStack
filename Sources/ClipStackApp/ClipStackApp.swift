import AppKit
import ClipStackCore

let application = NSApplication.shared
let delegate = ClipStackApplicationDelegate()

application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
