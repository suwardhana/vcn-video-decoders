// Load webtest/index.html in a WKWebView (same WebKit as Safari), print what the page reports, quit.
//   webtest [clip.mp4]
import AppKit
import WebKit

final class App: NSObject, NSApplicationDelegate, WKScriptMessageHandler {
  var window: NSWindow!
  var web: WKWebView!

  func applicationDidFinishLaunching(_ n: Notification) {
    FileHandle.standardError.write("launched\n".data(using: .utf8)!)
    let cfg = WKWebViewConfiguration()
    cfg.mediaTypesRequiringUserActionForPlayback = []
    cfg.userContentController.add(self, name: "done")
    window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 480, height: 270), styleMask: [.titled], backing: .buffered, defer: false)
    window.title = "AV1 WebKit test"
    web = WKWebView(frame: window.contentView!.bounds, configuration: cfg)
    web.autoresizingMask = [.width, .height]
    window.contentView!.addSubview(web)
    window.orderFrontRegardless()
    NSApp.activate(ignoringOtherApps: true)
    let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    var page = URLComponents(url: dir.appendingPathComponent("index.html"), resolvingAgainstBaseURL: false)!
    if CommandLine.arguments.count > 1 { page.queryItems = [URLQueryItem(name: "clip", value: CommandLine.arguments[1])] }
    web.loadFileURL(page.url!, allowingReadAccessTo: dir)
    DispatchQueue.main.asyncAfter(deadline: .now() + 30) { print("timeout"); exit(3) }
  }

  func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
    print(m.body)
    fflush(stdout)
    exit(0)
  }
}

FileHandle.standardError.write("start\n".data(using: .utf8)!)
let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled], reason: "AV1 WebKit test")
app.run()
_ = activity
