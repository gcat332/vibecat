import Foundation

public enum SocketPath {
    public static let overrideKey = "VIBECAT_SOCKET"

    public static func resolve(env: [String: String], home: String) -> String {
        if let override = env[overrideKey], !override.isEmpty { return override }
        return "\(home)/Library/Application Support/VibeCat/vibecat.sock"
    }

    public static var `default`: String {
        resolve(env: ProcessInfo.processInfo.environment,
                home: NSHomeDirectory())
    }
}
