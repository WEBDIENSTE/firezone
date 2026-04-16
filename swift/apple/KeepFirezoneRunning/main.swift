import AppKit
import Foundation

private enum Constants {
  static let mainAppBundleIdentifierInfoKey = "FirezoneMainAppBundleIdentifier"
  static let mainAppPathEnvironmentVariable = "KEEP_FIREZONE_RUNNING_MAIN_APP_PATH"
  static let relaunchInterval: TimeInterval = 5
}

private struct MainApp {
  let url: URL
  let bundleIdentifier: String
}

final class KeepFirezoneRunningAppDelegate: NSObject, NSApplicationDelegate {
  private var timer: Timer?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSLog(
      "[KeepFirezoneRunning] launched helper bundle=%@",
      Bundle.main.bundleURL.path
    )
    launchMainAppIfNeeded(trigger: "launch")

    timer = Timer.scheduledTimer(
      timeInterval: Constants.relaunchInterval,
      target: self,
      selector: #selector(handleTimer),
      userInfo: nil,
      repeats: true
    )
  }

  func applicationWillTerminate(_ notification: Notification) {
    timer?.invalidate()
  }

  @objc private func handleTimer() {
    launchMainAppIfNeeded(trigger: "timer")
  }

  private func launchMainAppIfNeeded(trigger: String) {
    guard let mainApp = resolveMainApp(trigger: trigger) else {
      return
    }

    let runningApplications = NSRunningApplication.runningApplications(
      withBundleIdentifier: mainApp.bundleIdentifier
    )

    guard runningApplications.isEmpty else {
      return
    }

    launch(mainApp, trigger: trigger)
  }

  private func resolveMainApp(trigger: String) -> MainApp? {
    guard let mainAppURL = mainAppURL else {
      NSLog(
        "[KeepFirezoneRunning] %@: failed to resolve main app URL from helper bundle=%@",
        trigger,
        Bundle.main.bundleURL.path
      )
      return nil
    }

    guard let bundleIdentifier = mainAppBundleIdentifier else {
      NSLog(
        "[KeepFirezoneRunning] %@: failed to resolve main app bundle identifier for %@",
        trigger,
        mainAppURL.path
      )
      return nil
    }

    return MainApp(url: mainAppURL, bundleIdentifier: bundleIdentifier)
  }

  private func launch(_ mainApp: MainApp, trigger: String) {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false

    NSWorkspace.shared.openApplication(at: mainApp.url, configuration: configuration) {
      runningApplication,
      error in
      if let error {
        NSLog(
          "[KeepFirezoneRunning] %@: failed to launch %@: %@",
          trigger,
          mainApp.url.path,
          error.localizedDescription
        )
        return
      }

      if let runningApplication {
        NSLog(
          "[KeepFirezoneRunning] %@: launched %@ pid=%d",
          trigger,
          mainApp.url.path,
          runningApplication.processIdentifier
        )
      } else {
        NSLog(
          "[KeepFirezoneRunning] %@: launch completed without app instance for %@",
          trigger,
          mainApp.url.path
        )
      }
    }
  }

  private var mainAppURL: URL? {
    if let mainAppPath = ProcessInfo.processInfo.environment[
      Constants.mainAppPathEnvironmentVariable],
      !mainAppPath.isEmpty
    {
      return URL(fileURLWithPath: mainAppPath)
    }

    let helperBundleURL = Bundle.main.bundleURL
    guard helperBundleURL.lastPathComponent == "KeepFirezoneRunning.app" else {
      return nil
    }

    return
      helperBundleURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private var mainAppBundleIdentifier: String? {
    if let injectedBundleIdentifier = Bundle.main.object(
      forInfoDictionaryKey: Constants.mainAppBundleIdentifierInfoKey
    ) as? String,
      !injectedBundleIdentifier.isEmpty
    {
      return injectedBundleIdentifier
    }

    guard let mainAppURL else {
      return nil
    }

    return Bundle(url: mainAppURL)?.bundleIdentifier
  }
}

let application = NSApplication.shared
let delegate = KeepFirezoneRunningAppDelegate()
application.setActivationPolicy(.prohibited)
application.delegate = delegate
application.run()
