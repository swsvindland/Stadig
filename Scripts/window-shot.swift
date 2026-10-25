// Captures one app's frontmost window to a PNG, for checking the Mac app's layouts by eye without
// capturing anything else on the screen. Run: swift Scripts/window-shot.swift "Stadig Lift" out.png
// (the app's name as the menu bar shows it). Needs Screen Recording permission for the terminal.
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: swift Scripts/window-shot.swift <app name> <out.png>\n".utf8))
    exit(2)
}
let owner = arguments[1]
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let mine = windows.filter {
    ($0[kCGWindowOwnerName as String] as? String) == owner && ($0[kCGWindowLayer as String] as? Int) == 0
}
guard let window = mine.first, let id = window[kCGWindowNumber as String] as? Int else {
    FileHandle.standardError.write(Data("No on-screen window of \(owner)\n".utf8))
    exit(1)
}
let capture = Process()
capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
capture.arguments = ["-x", "-o", "-l\(id)", arguments[2]]
try capture.run()
capture.waitUntilExit()
exit(capture.terminationStatus)
