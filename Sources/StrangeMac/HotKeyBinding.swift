import Carbon
import StrangeCore

/// Physical ANSI key positions. Punctuation uses comma/period without Shift.
public struct HotKeyBinding: Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32
    public let command: WindowCommand
    public var zone: WindowZone? {
        if case .zone(let zone) = command { return zone }
        return nil
    }
    public let label: String

    private init(keyCode: UInt32, modifiers: UInt32, zone: WindowZone, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.command = .zone(zone)
        self.label = label
    }

    private init(keyCode: UInt32, modifiers: UInt32, command: WindowCommand, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.command = command
        self.label = label
    }

    public static let defaults: [HotKeyBinding] = {
        let baseline = UInt32(controlKey | optionKey)
        let sixths = baseline | UInt32(cmdKey)
        return [
            Self(keyCode: UInt32(kVK_Return), modifiers: baseline, zone: .whole, label: "⌃⌥ Return"),
            Self(keyCode: UInt32(kVK_LeftArrow), modifiers: baseline, zone: .leftHalf, label: "⌃⌥ ←"),
            Self(keyCode: UInt32(kVK_RightArrow), modifiers: baseline, zone: .rightHalf, label: "⌃⌥ →"),
            Self(keyCode: UInt32(kVK_UpArrow), modifiers: baseline, zone: .topHalf, label: "⌃⌥ ↑"),
            Self(keyCode: UInt32(kVK_DownArrow), modifiers: baseline, zone: .bottomHalf, label: "⌃⌥ ↓"),
            Self(keyCode: UInt32(kVK_ANSI_J), modifiers: baseline, zone: .leftThird, label: "⌃⌥ J"),
            Self(keyCode: UInt32(kVK_ANSI_K), modifiers: baseline, zone: .centerThird, label: "⌃⌥ K"),
            Self(keyCode: UInt32(kVK_ANSI_L), modifiers: baseline, zone: .rightThird, label: "⌃⌥ L"),
            Self(keyCode: UInt32(kVK_ANSI_U), modifiers: baseline, zone: .topLeftQuadrant, label: "⌃⌥ U"),
            Self(keyCode: UInt32(kVK_ANSI_O), modifiers: baseline, zone: .topRightQuadrant, label: "⌃⌥ O"),
            Self(keyCode: UInt32(kVK_ANSI_M), modifiers: baseline, zone: .bottomLeftQuadrant, label: "⌃⌥ M"),
            Self(keyCode: UInt32(kVK_ANSI_Period), modifiers: baseline, zone: .bottomRightQuadrant, label: "⌃⌥ ."),
            Self(keyCode: UInt32(kVK_ANSI_U), modifiers: sixths, zone: .topLeftSixth, label: "⌃⌥⌘ U"),
            Self(keyCode: UInt32(kVK_ANSI_I), modifiers: sixths, zone: .topCenterSixth, label: "⌃⌥⌘ I"),
            Self(keyCode: UInt32(kVK_ANSI_O), modifiers: sixths, zone: .topRightSixth, label: "⌃⌥⌘ O"),
            Self(keyCode: UInt32(kVK_ANSI_M), modifiers: sixths, zone: .bottomLeftSixth, label: "⌃⌥⌘ M"),
            Self(keyCode: UInt32(kVK_ANSI_Comma), modifiers: sixths, zone: .bottomCenterSixth, label: "⌃⌥⌘ ,"),
            Self(keyCode: UInt32(kVK_ANSI_Period), modifiers: sixths, zone: .bottomRightSixth, label: "⌃⌥⌘ ."),
            Self(keyCode: UInt32(kVK_LeftArrow), modifiers: sixths, command: .moveDisplay(.left), label: "⌃⌥⌘ ←"),
            Self(keyCode: UInt32(kVK_RightArrow), modifiers: sixths, command: .moveDisplay(.right), label: "⌃⌥⌘ →")
        ]
    }()
}
