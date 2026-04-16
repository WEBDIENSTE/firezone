#if os(macOS)
  import Foundation
  import ServiceManagement

  enum KeepAppRunningService {
    static var plistName: String {
      let bundleIdentifier = Bundle.main.bundleIdentifier ?? "dev.firezone.firezone"
      return "\(bundleIdentifier).keep-app-running.plist"
    }

    static var appService: SMAppService {
      SMAppService.agent(plistName: plistName)
    }
  }
#endif
