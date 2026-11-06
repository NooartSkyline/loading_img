import Flutter
import Security

enum LoginVault {
  private static let service = "com.loading.app.loading.login"

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "loading/login", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any]
      let site = args?["site"] as? String ?? ""
      guard site == "instagram" || site == "facebook" else {
        result(FlutterError(code: "login", message: "ไม่รู้จักไซต์", details: nil))
        return
      }
      switch call.method {
      case "read":
        result(read(site: site))
      case "write":
        let user = (args?["user"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let password = args?["password"] as? String ?? ""
        if !user.isEmpty && !password.isEmpty {
          write(site: site, user: user, password: password)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func query(site: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: site,
    ]
  }

  private static func read(site: String) -> [String: String]? {
    var lookup = query(site: site)
    lookup[kSecReturnData as String] = true
    lookup[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(lookup as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    guard
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
      let user = json["user"]?.trimmingCharacters(in: .whitespacesAndNewlines),
      let password = json["password"],
      !user.isEmpty,
      !password.isEmpty
    else { return nil }
    return ["user": user, "password": password]
  }

  private static func write(site: String, user: String, password: String) {
    guard
      let data = try? JSONSerialization.data(withJSONObject: [
        "user": user,
        "password": password,
      ])
    else { return }
    SecItemDelete(query(site: site) as CFDictionary)
    let record: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: site,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    SecItemAdd(record as CFDictionary, nil)
  }
}
