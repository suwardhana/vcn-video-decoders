import AppKit
import SwiftUI

// MARK: - Model

struct Check: Identifiable, Decodable {
  let id: String
  let label: String
  let status: String  // ok | warn | fail
  let detail: String
}

struct Preflight: Decodable {
  let canInstall: Bool
  let installed: String?  // none | current | outdated
  let overridable: Bool
  let repairable: Bool?
  let validated: Bool?
  let macos: String
  let checks: [Check]
}

enum Confirm: Identifiable {
  case install, installAnyway, uninstall, reboot, repair
  var id: Int { hashValue }
}

enum Phase: Equatable {
  case idle, checking, installing, repairing, uninstalling
  case done(String)
  case failed(String)
}

// MARK: - Engine bridge

final class Engine: ObservableObject {
  @Published var pre: Preflight? = nil
  @Published var phase: Phase = .idle
  @Published var needReboot = false

  private var resDir: String {
    Bundle.main.resourcePath ?? FileManager.default.currentDirectoryPath
  }
  private var enginePath: String { resDir + "/engine.sh" }

  func recheck() {
    phase = .checking
    DispatchQueue.global().async {
      let out = self.runUser(["check"])
      let pre = (out.data(using: .utf8)).flatMap {
        try? JSONDecoder().decode(Preflight.self, from: $0)
      }
      DispatchQueue.main.async {
        self.pre = pre
        self.phase =
          pre == nil ? .failed("Could not read preflight. Check the installer bundle.") : .idle
      }
    }
  }

  func install(force: Bool) {
    phase = .installing
    DispatchQueue.global().async {
      let forceArg = force ? " --force" : ""
      let inner =
        "/bin/zsh \(Self.shq(self.enginePath)) install\(forceArg) --res \(Self.shq(self.resDir))"
      let (ok, msg) = self.runPrivileged(inner)
      DispatchQueue.main.async {
        if ok {
          self.needReboot = true
          self.phase = .done("Installed. Reboot to load the hardware decoders.")
        } else {
          self.phase = .failed(msg)
        }
      }
    }
  }

  func repair(validated: Bool) {
    phase = .repairing
    DispatchQueue.global().async {
      let inner = "/bin/zsh \(Self.shq(self.enginePath)) repair --res \(Self.shq(self.resDir))"
      let (ok, msg) = self.runPrivileged(inner)
      DispatchQueue.main.async {
        if ok {
          self.needReboot = true
          self.phase = .done(
            validated
              ? "Repaired: Apple's video plug-ins are back and the decoders are installed. Reboot to finish."
              : "Repaired: Apple's video plug-ins are back. Reboot to finish."
          )
        } else {
          self.phase = .failed(msg)
        }
      }
    }
  }
  func uninstall() {
    phase = .uninstalling
    DispatchQueue.global().async {
      let inner = "/bin/zsh \(Self.shq(self.enginePath)) uninstall --res \(Self.shq(self.resDir))"
      let (ok, msg) = self.runPrivileged(inner)
      DispatchQueue.main.async {
        if ok {
          self.needReboot = true
          self.phase = .done("Removed. Reboot to apply.")
        } else {
          self.phase = .failed(msg)
        }
      }
    }
  }

  func reboot() {
    let s = NSAppleScript(source: "tell application \"System Events\" to restart")
    var e: NSDictionary?
    s?.executeAndReturnError(&e)
  }

  // run engine as the current user, capture stdout
  private func runUser(_ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/zsh")
    p.arguments = [enginePath] + args + ["--res", resDir]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    do { try p.run() } catch { return "" }
    let d = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: d, encoding: .utf8) ?? ""
  }

  /// Reject paths that can break out of a shell or AppleScript string.
  static func isUnsafePath(_ s: String) -> Bool {
    s.isEmpty || s.contains(where: { $0.isNewline || $0 == "\0" })
      || s.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7f }
  }

  // single-quote a path for the shell (the app can live in a folder with any name)
  static func shq(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  // escape a string for an AppleScript string literal (CWE-94)
  static func asq(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r")
  }

  // run a command as root via the native admin prompt
  private func runPrivileged(_ inner: String) -> (Bool, String) {
    if Self.isUnsafePath(enginePath) || Self.isUnsafePath(resDir) {
      return (false, "Installer path contains unsafe characters.")
    }
    let src = "do shell script \"\(Self.asq(inner))\" with administrator privileges"
    let s = NSAppleScript(source: src)
    var err: NSDictionary?
    let r = s?.executeAndReturnError(&err)
    if let err = err {
      let m =
        (err[NSAppleScript.errorMessage] as? String)
        ?? "Authorization failed or the install was cancelled."
      return (false, m)
    }
    return (true, r?.stringValue ?? "")
  }
}

// MARK: - UI

struct StatusDot: View {
  let status: String
  var body: some View {
    let (name, color): (String, Color) = {
      switch status {
      case "ok": return ("checkmark.circle.fill", .green)
      case "warn": return ("exclamationmark.triangle.fill", .orange)
      default: return ("xmark.octagon.fill", .red)
      }
    }()
    Image(systemName: name).foregroundStyle(color).font(.system(size: 18, weight: .semibold))
  }
}

struct CheckRow: View {
  let c: Check
  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      StatusDot(status: c.status).frame(width: 22)
      VStack(alignment: .leading, spacing: 2) {
        Text(c.label).font(.system(size: 13, weight: .semibold))
        Text(c.detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(
          horizontal: false,
          vertical: true
        )
      }
      Spacer(minLength: 0)
    }.padding(.vertical, 6)
  }
}

struct ContentView: View {
  @StateObject var engine = Engine()
  @State private var confirm: Confirm? = nil

  var installed: String { engine.pre?.installed ?? "none" }
  var canInstall: Bool { engine.pre?.canInstall ?? false }
  var overridable: Bool { engine.pre?.overridable ?? false }
  var repairable: Bool { engine.pre?.repairable ?? false }
  var validated: Bool { engine.pre?.validated ?? false }
  var busy: Bool {
    switch engine.phase {
    case .checking, .installing, .repairing, .uninstalling: return true
    default: return false
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if engine.pre != nil && !engine.needReboot { stateBanner.padding(.horizontal, 20) }
          Text("PREFLIGHT").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
            .padding(.top, 16).padding(.horizontal, 20)
          if let pre = engine.pre {
            VStack(spacing: 0) {
              ForEach(pre.checks) { c in
                CheckRow(c: c)
                if c.id != pre.checks.last?.id { Divider().padding(.leading, 54) }
              }
            }.padding(.horizontal, 20).padding(.vertical, 6)
          } else {
            HStack {
              ProgressView().controlSize(.small)
              Text("Checking…").foregroundStyle(.secondary)
            }.padding(20)
          }
          resultBanner.padding(.horizontal, 20)
        }
      }
      Divider()
      footer
      credit
    }.frame(width: 560, height: 700).onAppear { engine.recheck() }.alert(item: $confirm) { c in
      alert(for: c)
    }
  }

  @ViewBuilder var stateBanner: some View {
    if repairable {
      banner(
        icon: "wrench.and.screwdriver.fill",
        color: .orange,
        text:
          "Some of Apple's own video plug-ins are missing on this Mac. Click Repair: it puts them back from Apple's original system copy\(validated ? " and installs the decoders" : "") — nothing else is changed. Then reboot."
      )
    } else {
      switch installed {
      case "current":
        banner(
          icon: "checkmark.seal.fill",
          color: .green,
          text: "Already installed and up to date. Nothing to do — you can close this window."
        )
      case "outdated":
        banner(
          icon: "arrow.triangle.2.circlepath",
          color: .orange,
          text: "An older or different version is installed. Click Update to replace it."
        )
      default:
        if canInstall {
          banner(
            icon: "info.circle.fill",
            color: .blue,
            text: "Ready. Click Install, type your password, then reboot. That's it."
          )
        } else if overridable {
          banner(
            icon: "exclamationmark.triangle.fill",
            color: .orange,
            text:
              "This macOS version hasn't been validated yet. The safe choice is to wait for an updated installer."
          )
        } else {
          banner(
            icon: "xmark.octagon.fill",
            color: .red,
            text: "Can't install on this Mac yet. Fix the items marked in red, then click Re-check."
          )
        }
      }
    }
  }

  func alert(for c: Confirm) -> Alert {
    switch c {
    case .install:
      return Alert(
        title: Text("Install the hardware decoders?"),
        message: Text(
          "This copies the AV1 and VP9 decoders into the system volume and creates a new boot snapshot. macOS will ask for your password. You must reboot afterwards."
        ),
        primaryButton: .default(Text("Install")) { engine.install(force: false) },
        secondaryButton: .cancel()
      )
    case .installAnyway:
      return Alert(
        title: Text("This macOS build is NOT validated"),
        message: Text(
          "The GPU driver of this macOS version has not been checked. Installing can FREEZE the screen or hang the GPU while playing video. Only continue if you know how to boot without the decoders and remove them."
        ),
        primaryButton: .destructive(Text("I understand, install")) { engine.install(force: true) },
        secondaryButton: .cancel(Text("Cancel"))
      )
    case .uninstall:
      return Alert(
        title: Text("Remove the hardware decoders?"),
        message: Text(
          "Safari and Chrome go back to software decoding after a reboot. macOS will ask for your password."
        ),
        primaryButton: .destructive(Text("Remove")) { engine.uninstall() },
        secondaryButton: .cancel()
      )
    case .repair:
      return Alert(
        title: Text("Repair the system video plug-ins?"),
        message: Text(
          "Missing Apple plug-ins are copied back from Apple's original, untouched system snapshot\(validated ? ", and the AV1 and VP9 decoders are installed" : ""). Nothing that is already there is changed. macOS will ask for your password. You must reboot afterwards."
        ),
        primaryButton: .default(Text("Repair")) { engine.repair(validated: validated) },
        secondaryButton: .cancel()
      )
    case .reboot:
      return Alert(
        title: Text("Reboot now?"),
        message: Text("Save your work first. Other apps will be asked to quit."),
        primaryButton: .default(Text("Reboot")) { engine.reboot() },
        secondaryButton: .cancel(Text("Later"))
      )
    }
  }

  var header: some View {
    HStack(spacing: 14) {
      ZStack {
        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(
          LinearGradient(
            colors: [.pink, .purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        ).frame(width: 60, height: 60)
        Image(systemName: "bolt.fill").font(.system(size: 28, weight: .bold)).foregroundStyle(
          .white
        )
      }
      VStack(alignment: .leading, spacing: 3) {
        Text("AMD VCN Video Decoders").font(.system(size: 19, weight: .bold))
        Text("Hardware AV1 + VP9 for Safari & Chrome").font(.system(size: 12)).foregroundStyle(
          .secondary
        )
        Text(engine.pre?.macos ?? "detecting macOS…").font(.system(size: 11)).foregroundStyle(
          .tertiary
        )
      }
      Spacer()
    }.padding(20)
  }

  @ViewBuilder var resultBanner: some View {
    switch engine.phase {
    case .done(let m): banner(icon: "checkmark.seal.fill", color: .green, text: m)
    case .failed(let m): banner(icon: "exclamationmark.triangle.fill", color: .red, text: m)
    case .installing:
      banner(
        icon: "gearshape.fill",
        color: .blue,
        text: "Installing into the sealed system volume… enter your password when asked."
      )
    case .repairing:
      banner(
        icon: "wrench.and.screwdriver.fill",
        color: .blue,
        text: "Repairing the system volume… enter your password when asked."
      )
    case .uninstalling: banner(icon: "trash.fill", color: .blue, text: "Removing…")
    default: EmptyView()
    }
  }

  func banner(icon: String, color: Color, text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: icon).foregroundStyle(color)
      Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }.padding(12).background(
      color.opacity(0.12),
      in: RoundedRectangle(cornerRadius: 10, style: .continuous)
    ).padding(.top, 10)
  }

  var footer: some View {
    HStack(spacing: 12) {
      Button {
        engine.recheck()
      } label: {
        Label("Re-check", systemImage: "arrow.clockwise")
      }.disabled(busy)
      Spacer()
      Button(role: .destructive) {
        confirm = .uninstall
      } label: {
        Text("Uninstall")
      }.disabled(busy || installed == "none")
      if engine.needReboot {
        Button {
          confirm = .reboot
        } label: {
          Text("Reboot now").bold()
        }.buttonStyle(.borderedProminent).tint(.green)
      } else if repairable {
        Button {
          confirm = .repair
        } label: {
          Text(busy ? "Working…" : "Repair").bold().frame(minWidth: 90)
        }.buttonStyle(.borderedProminent).tint(.orange).disabled(busy)
      } else {
        Button {
          confirm = (overridable && !canInstall) ? .installAnyway : .install
        } label: {
          Text(installLabel).bold().frame(minWidth: 90)
        }.buttonStyle(.borderedProminent).tint(overridable && !canInstall ? .orange : .accentColor)
          .disabled(busy || installed == "current" || (!canInstall && !overridable))
      }
    }.padding(16)
  }

  var credit: some View {
    HStack(spacing: 4) {
      Text("Made by").foregroundStyle(.secondary)
      if let drogaBoxURL = URL(string: "https://github.com/DrogaBox") {
        Link("DrogaBox", destination: drogaBoxURL)
      }
      Text("&").foregroundStyle(.secondary)
      if let izzyURL = URL(string: "https://github.com/wh0ami7") {
        Link("Izzy", destination: izzyURL)
      }
    }.font(.system(size: 11)).padding(.bottom, 12)
  }

  var installLabel: String {
    if busy && !engine.needReboot { return "Working…" }
    if overridable && !canInstall { return "Install anyway" }
    switch installed {
    case "current": return "Installed"
    case "outdated": return "Update"
    default: return "Install"
    }
  }
}

// MARK: - App

@main struct VCNInstallerApp: App {
  init() { NSApplication.shared.setActivationPolicy(.regular) }
  var body: some Scene {
    Window("AMD VCN Video Decoders", id: "main") { ContentView() }.windowResizability(.contentSize)
  }
}
