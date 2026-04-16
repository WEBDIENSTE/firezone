//
//  Configuration.swift
//  (c) 2024 Firezone, Inc.
//  LICENSE: Apache-2.0
//
//  A thin wrapper around UserDefaults for user and admin managed app configuration.

import Combine
import Foundation
import Sentry

#if os(macOS)
  import ServiceManagement

  extension SMAppService.Status {
    var isRegistered: Bool {
      switch self {
      case .enabled, .requiresApproval:
        return true
      case .notRegistered, .notFound:
        return false
      @unknown default:
        return false
      }
    }
  }
#endif

@MainActor
public class Configuration: ObservableObject {
  static let shared = Configuration()
  private var cancellables = Set<AnyCancellable>()

  @Published private(set) var publishedInternetResourceEnabled = false
  @Published private(set) var publishedHideAdminPortalMenuItem = false
  @Published private(set) var publishedHideResourceList = false

  #if os(macOS)
    private struct LaunchServicesConfiguration: Equatable {
      let startOnLogin: Bool
      let keepAppRunning: Bool
    }

    private var launchServicesConfiguration: LaunchServicesConfiguration {
      LaunchServicesConfiguration(
        startOnLogin: startOnLogin,
        keepAppRunning: keepAppRunning
      )
    }

    private var suppressAutomaticLaunchServicesUpdates = 0
    private var lastSeenLaunchServicesConfiguration: LaunchServicesConfiguration
  #endif

  var isAuthURLForced: Bool { defaults.objectIsForced(forKey: Keys.authURL) }
  var isApiURLForced: Bool { defaults.objectIsForced(forKey: Keys.apiURL) }
  var isLogFilterForced: Bool { defaults.objectIsForced(forKey: Keys.logFilter) }
  var isAccountSlugForced: Bool { defaults.objectIsForced(forKey: Keys.accountSlug) }
  var isConnectOnStartForced: Bool { defaults.objectIsForced(forKey: Keys.connectOnStart) }
  var isStartOnLoginForced: Bool { defaults.objectIsForced(forKey: Keys.startOnLogin) }
  var isKeepAppRunningForced: Bool {
    defaults.objectIsForced(forKey: Keys.keepAppRunning)
  }

  var authURL: String {
    get { defaults.string(forKey: Keys.authURL) ?? Self.defaultAuthURL }
    set { defaults.set(newValue, forKey: Keys.authURL) }
  }

  var apiURL: String {
    get { defaults.string(forKey: Keys.apiURL) ?? Self.defaultApiURL }
    set { defaults.set(newValue, forKey: Keys.apiURL) }
  }

  var logFilter: String {
    get { defaults.string(forKey: Keys.logFilter) ?? Self.defaultLogFilter }
    set { defaults.set(newValue, forKey: Keys.logFilter) }
  }

  var accountSlug: String {
    get { defaults.string(forKey: Keys.accountSlug) ?? Self.defaultAccountSlug }
    set { defaults.set(newValue, forKey: Keys.accountSlug) }
  }

  var hideAdminPortalMenuItem: Bool {
    get { defaults.bool(forKey: Keys.hideAdminPortalMenuItem) }
    set { defaults.set(newValue, forKey: Keys.hideAdminPortalMenuItem) }
  }

  var hideResourceList: Bool {
    get { defaults.bool(forKey: Keys.hideResourceList) }
    set { defaults.set(newValue, forKey: Keys.hideResourceList) }
  }

  var connectOnStart: Bool {
    get { defaults.bool(forKey: Keys.connectOnStart) }
    set { defaults.set(newValue, forKey: Keys.connectOnStart) }
  }

  var startOnLogin: Bool {
    get { defaults.bool(forKey: Keys.startOnLogin) }
    set { defaults.set(newValue, forKey: Keys.startOnLogin) }
  }

  var keepAppRunning: Bool {
    get { defaults.bool(forKey: Keys.keepAppRunning) }
    set { defaults.set(newValue, forKey: Keys.keepAppRunning) }
  }

  var shouldStartOnLogin: Bool {
    startOnLogin || keepAppRunning
  }

  var disableUpdateCheck: Bool {
    get { defaults.bool(forKey: Keys.disableUpdateCheck) }
    set { defaults.set(newValue, forKey: Keys.disableUpdateCheck) }
  }

  var supportURL: String {
    get { defaults.string(forKey: Keys.supportURL) ?? Self.defaultSupportURL }
    set { defaults.set(newValue, forKey: Keys.supportURL) }
  }

  // User-configurable only
  var internetResourceEnabled: Bool {
    get { defaults.bool(forKey: Keys.internetResourceEnabled) }
    set { defaults.set(newValue, forKey: Keys.internetResourceEnabled) }
  }

  #if DEBUG
    static let defaultAuthURL = "https://app.firez.one"
    static let defaultApiURL = "wss://api.firez.one"
    static let defaultLogFilter = "debug"
  #else
    static let defaultAuthURL = "https://app.firezone.dev"
    static let defaultApiURL = "wss://api.firezone.dev"
    static let defaultLogFilter = "info"
  #endif

  static let defaultAccountSlug = ""
  static let defaultSupportURL = "https://firezone.dev/support"

  // Bools are always default false
  static let defaultConnectOnStart = false
  static let defaultStartOnLogin = false
  static let defaultKeepAppRunning = false
  static let defaultDisableUpdateCheck = false

  private struct Keys {
    static let authURL = "authURL"
    static let apiURL = "apiURL"
    static let logFilter = "logFilter"
    static let accountSlug = "accountSlug"
    static let internetResourceEnabled = "internetResourceEnabled"
    static let hideAdminPortalMenuItem = "hideAdminPortalMenuItem"
    static let hideResourceList = "hideResourceList"
    static let connectOnStart = "connectOnStart"
    static let startOnLogin = "startOnLogin"
    static let keepAppRunning = "keepAppRunning"
    static let disableUpdateCheck = "disableUpdateCheck"
    static let supportURL = "supportURL"
  }

  private var defaults: UserDefaults

  // swiftlint:disable:next no_userdefaults_standard - DI entry point
  init(userDefaults: UserDefaults = UserDefaults.standard) {
    defaults = userDefaults

    #if os(macOS)
      self.lastSeenLaunchServicesConfiguration = LaunchServicesConfiguration(
        startOnLogin: defaults.bool(forKey: Keys.startOnLogin),
        keepAppRunning: defaults.bool(forKey: Keys.keepAppRunning)
      )
    #endif

    self.publishedInternetResourceEnabled = internetResourceEnabled
    self.publishedHideAdminPortalMenuItem = hideAdminPortalMenuItem
    self.publishedHideResourceList = hideResourceList

    NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: defaults)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.handleUserDefaultsChanged()
      }
      .store(in: &cancellables)
  }

  func toTunnelConfiguration() -> TunnelConfiguration {
    return TunnelConfiguration(
      apiURL: apiURL,
      accountSlug: accountSlug,
      logFilter: logFilter,
      internetResourceEnabled: internetResourceEnabled
    )
  }

  #if os(macOS)
    func beginSuppressingAutomaticLaunchServicesUpdates() {
      suppressAutomaticLaunchServicesUpdates += 1
    }

    func endSuppressingAutomaticLaunchServicesUpdates() {
      suppressAutomaticLaunchServicesUpdates = max(suppressAutomaticLaunchServicesUpdates - 1, 0)
    }

    // Register / unregister our login item and launch agent based on configuration.
    func updateLaunchServices(forceAgentReregistration: Bool = false) async throws {
      // Getting these statuses appears to be blocking sometimes.
      SentrySDK.pauseAppHangTracking()
      defer { SentrySDK.resumeAppHangTracking() }
      try await updateMainAppService(status: SMAppService.mainApp.status)
      try await updateKeepAppRunningService(
        status: KeepAppRunningService.appService.status,
        forceReregistration: forceAgentReregistration
      )
    }

    private func updateMainAppService(status: SMAppService.Status) async throws {
      guard shouldStartOnLogin != status.isRegistered else {
        return
      }

      if shouldStartOnLogin {
        try SMAppService.mainApp.register()
        return
      }

      try await SMAppService.mainApp.unregister()
    }

    private func updateKeepAppRunningService(
      status: SMAppService.Status,
      forceReregistration: Bool
    ) async throws {
      guard keepAppRunning else {
        guard status.isRegistered else {
          return
        }

        try await KeepAppRunningService.appService.unregister()
        return
      }

      guard !forceReregistration || status != .enabled else {
        try await KeepAppRunningService.appService.unregister()
        try KeepAppRunningService.appService.register()
        return
      }

      guard !status.isRegistered else {
        return
      }

      try KeepAppRunningService.appService.register()
    }

    private func updateLaunchServicesIfNeeded() {
      let currentLaunchServicesConfiguration = launchServicesConfiguration
      defer {
        lastSeenLaunchServicesConfiguration = currentLaunchServicesConfiguration
      }

      guard suppressAutomaticLaunchServicesUpdates == 0 else {
        return
      }

      guard currentLaunchServicesConfiguration != lastSeenLaunchServicesConfiguration else {
        return
      }

      Task {
        do {
          try await updateLaunchServices()
        } catch {
          Log.error(error)
        }
      }
    }
  #endif

  private func handleUserDefaultsChanged() {
    #if os(macOS)
      updateLaunchServicesIfNeeded()
    #endif

    // Update published properties
    self.publishedInternetResourceEnabled = internetResourceEnabled
    self.publishedHideAdminPortalMenuItem = hideAdminPortalMenuItem
    self.publishedHideResourceList = hideResourceList

    // Announce we changed
    objectWillChange.send()
  }
}

// Configuration does not conform to Decodable, so introduce a simpler type here to encode for IPC
public struct TunnelConfiguration: Codable, Sendable {
  public let apiURL: String
  public let accountSlug: String
  public let logFilter: String
  public let internetResourceEnabled: Bool

  public init(apiURL: String, accountSlug: String, logFilter: String, internetResourceEnabled: Bool)
  {
    self.apiURL = apiURL
    self.accountSlug = accountSlug
    self.logFilter = logFilter
    self.internetResourceEnabled = internetResourceEnabled
  }
}

extension TunnelConfiguration: Equatable {
  public static func == (lhs: TunnelConfiguration, rhs: TunnelConfiguration) -> Bool {
    return lhs.apiURL == rhs.apiURL && lhs.accountSlug == rhs.accountSlug
      && lhs.logFilter == rhs.logFilter
      && lhs.internetResourceEnabled == rhs.internetResourceEnabled
  }
}
