// Loads webtest/index.html in a WKWebView (same WebKit as Safari),
// prints what the page reports, then quits.
//   webtest [clip.mp4]
import AppKit
import WebKit

/// Hosts the local AV1 capability page inside WebKit.
final class App: NSObject, NSApplicationDelegate, WKScriptMessageHandler {
  private var window: NSWindow?
  private var web: WKWebView?

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard let launched = "launched\n".data(using: .utf8) else { return }
    FileHandle.standardError.write(launched)
    let configuration = WKWebViewConfiguration()
    configuration.mediaTypesRequiringUserActionForPlayback = []
    configuration.userContentController.add(self, name: "done")
    let window = NSWindow(
      contentRect: NSRect(x: 40, y: 40, width: 480, height: 270),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    window.title = "AV1 WebKit test"
    guard let contentView = window.contentView else { return }
    let webView = WKWebView(frame: contentView.bounds, configuration: configuration)
    webView.autoresizingMask = [.width, .height]
    contentView.addSubview(webView)
    window.orderFrontRegardless()
    NSApp.activate(ignoringOtherApps: true)
    self.window = window
    self.web = webView
    let directory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    guard
      var page = URLComponents(
        url: directory.appendingPathComponent("index.html"),
        resolvingAgainstBaseURL: false
      )
    else { return }
    if CommandLine.arguments.count > 1 {
      page.queryItems = [URLQueryItem(name: "clip", value: CommandLine.arguments[1])]
    }
    guard let pageURL = page.url else { return }
    webView.loadFileURL(pageURL, allowingReadAccessTo: directory)
    DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
      print("timeout")
      exit(3)
    }
  }

  func userContentController(
    _ controller: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    print(message.body)
    fflush(stdout)
    exit(0)
  }
}

guard let started = "start\n".data(using: .utf8) else {
  fatalError("UTF-8 encoding of a literal failed")
}
FileHandle.standardError.write(started)
let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
let activity = ProcessInfo.processInfo.beginActivity(
  options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled],
  reason: "AV1 WebKit test"
)
app.run()
_ = activity
