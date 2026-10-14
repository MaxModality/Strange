import Foundation
import StrangeCore
import StrangeMac

@main struct StrangeCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--version"] {
            print("0.4.3")
        } else if arguments == ["--request-permission"] {
            let trusted = WindowManager.requestAccessibilityPermission()
            print(trusted ? "Accessibility access is enabled." : "Enable Accessibility access in System Settings, then run again.")
        } else if arguments.count == 2, arguments[0] == "move", let zone = WindowZone(rawValue: arguments[1]) {
            do {
                _ = try await WindowManager().moveActiveWindow(to: zone)
                print("Window placement verified.")
            } catch {
                // Never print application names, window titles, or document content.
                print("Placement failed: \(error)")
                Foundation.exit(1)
            }
        } else {
            print("Strange 0.4.3\nUsage: strange move <zone> | --request-permission | --version\nZones:")
            for zone in WindowZone.allCases { print("  \(zone.rawValue)") }
        }
    }
}
