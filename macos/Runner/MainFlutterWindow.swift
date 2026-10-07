import Cocoa
import FlutterMacOS
import ServiceManagement
import UserNotifications
import UniformTypeIdentifiers

class MainFlutterWindow: NSWindow {
  private var channel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let bridge = FlutterMethodChannel(name: "impression_day/native",
                                      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel = bridge
    bridge.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(becameActive),
      name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(becameActive),
      name: NSWorkspace.didWakeNotification, object: nil)

    super.awakeFromNib()
  }

  deinit { NSWorkspace.shared.notificationCenter.removeObserver(self) }

  @objc private func becameActive() {
    channel?.invokeMethod("becameActive", arguments: nil)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "dataDirectory":
      guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first else {
        result(FlutterError(code: "directory", message: "앱 데이터 폴더를 찾지 못했습니다.", details: nil))
        return
      }
      let folder = base.appendingPathComponent("ImpressionDay", isDirectory: true)
      do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        result(folder.path)
      } catch {
        result(FlutterError(code: "directory", message: error.localizedDescription, details: nil))
      }
    case "showWindow":
      NSApp.activate(ignoringOtherApps: true)
      makeKeyAndOrderFront(nil)
      result(nil)
    case "getLaunchAtLogin":
      result(SMAppService.mainApp.status == .enabled)
    case "setLaunchAtLogin":
      let enabled = call.arguments as? Bool ?? false
      do {
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
        result(SMAppService.mainApp.status == .enabled)
      } catch {
        result(FlutterError(code: "login", message: error.localizedDescription, details: nil))
      }
    case "notificationAllowed":
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        DispatchQueue.main.async {
          let allowed = settings.authorizationStatus == .authorized
          if allowed { self.scheduleMorningNotification() }
          result(allowed)
        }
      }
    case "requestNotifications":
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { allowed, error in
        DispatchQueue.main.async {
          if allowed { self.scheduleMorningNotification() }
          if let error = error {
            result(FlutterError(code: "notification", message: error.localizedDescription, details: nil))
          } else { result(allowed) }
        }
      }
    case "saveImage":
      guard let arguments = call.arguments as? [String: Any],
            let bytes = arguments["bytes"] as? FlutterStandardTypedData,
            let name = arguments["name"] as? String else {
        result(FlutterError(code: "save", message: "그림 데이터가 없습니다.", details: nil))
        return
      }
      let panel = NSSavePanel()
      panel.allowedContentTypes = [.jpeg]
      panel.nameFieldStringValue = name.replacingOccurrences(of: "/", with: "-")
      panel.begin { response in
        guard response == .OK, let url = panel.url else { result(false); return }
        do {
          try bytes.data.write(to: url, options: .atomic)
          result(true)
        } catch {
          result(FlutterError(code: "save", message: error.localizedDescription, details: nil))
        }
      }
    case "openUrl":
      guard let value = call.arguments as? String, let url = URL(string: value) else {
        result(false)
        return
      }
      result(NSWorkspace.shared.open(url))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func scheduleMorningNotification() {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: ["impressionDayMorning"])
    let content = UNMutableNotificationContent()
    content.title = "오늘의 일정과 그림"
    content.body = "오늘의 D-day와 인상주의 그림을 확인해 보세요."
    content.sound = .default
    let trigger = UNCalendarNotificationTrigger(
      dateMatching: DateComponents(hour: 8, minute: 0), repeats: true)
    center.add(UNNotificationRequest(identifier: "impressionDayMorning",
                                     content: content, trigger: trigger))
  }
}
