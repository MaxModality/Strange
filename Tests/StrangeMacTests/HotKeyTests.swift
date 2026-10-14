import Carbon
import XCTest
import StrangeCore
@testable import StrangeMac

final class HotKeyTests: XCTestCase {
    func testBaselineShortcutsMatchRequestedZones() {
        assertMappings([
            (kVK_Return, .whole),
            (kVK_LeftArrow, .leftHalf),
            (kVK_RightArrow, .rightHalf),
            (kVK_UpArrow, .topHalf),
            (kVK_DownArrow, .bottomHalf),
            (kVK_ANSI_J, .leftThird),
            (kVK_ANSI_K, .centerThird),
            (kVK_ANSI_L, .rightThird),
            (kVK_ANSI_U, .topLeftQuadrant),
            (kVK_ANSI_O, .topRightQuadrant),
            (kVK_ANSI_M, .bottomLeftQuadrant),
            (kVK_ANSI_Period, .bottomRightQuadrant)
        ], modifiers: UInt32(controlKey | optionKey))
    }

    func testCommandShortcutsMatchRequestedSixths() {
        assertMappings([
            (kVK_ANSI_U, .topLeftSixth),
            (kVK_ANSI_I, .topCenterSixth),
            (kVK_ANSI_O, .topRightSixth),
            (kVK_ANSI_M, .bottomLeftSixth),
            (kVK_ANSI_Comma, .bottomCenterSixth),
            (kVK_ANSI_Period, .bottomRightSixth)
        ], modifiers: UInt32(controlKey | optionKey | cmdKey))
    }

    func testEveryZoneHasOneUniqueUnshiftedShortcut() {
        let bindings = HotKeyBinding.defaults
        XCTAssertEqual(bindings.count, 20)
        XCTAssertEqual(bindings.compactMap(\.zone).count, 18)
        XCTAssertEqual(Set(bindings.compactMap(\.zone)), Set(WindowZone.allCases))
        XCTAssertEqual(Set(bindings.map { "\($0.keyCode):\($0.modifiers)" }).count, bindings.count)
        for binding in bindings {
            XCTAssertEqual(binding.modifiers & UInt32(shiftKey), 0, binding.label)
            XCTAssertFalse(binding.label.isEmpty)
        }
    }

    private func assertMappings(
        _ expected: [(Int, WindowZone)],
        modifiers: UInt32,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let bindings = HotKeyBinding.defaults.filter { $0.modifiers == modifiers && $0.zone != nil }
        XCTAssertEqual(bindings.count, expected.count, file: file, line: line)
        for (keyCode, zone) in expected {
            let matches = bindings.filter { $0.keyCode == UInt32(keyCode) }
            XCTAssertEqual(matches.count, 1, "Shortcut for \(zone)", file: file, line: line)
            XCTAssertEqual(matches.first?.zone, zone, file: file, line: line)
        }
    }

    func testCommandArrowsMoveDisplaysWithoutChangingBaselineHalves() {
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        let displayBindings = HotKeyBinding.defaults.filter { $0.zone == nil }
        XCTAssertEqual(displayBindings.count, 2)
        XCTAssertEqual(displayBindings.first { $0.keyCode == UInt32(kVK_LeftArrow) }?.command, .moveDisplay(.left))
        XCTAssertEqual(displayBindings.first { $0.keyCode == UInt32(kVK_RightArrow) }?.command, .moveDisplay(.right))
        XCTAssertTrue(displayBindings.allSatisfy { $0.modifiers == modifiers })
    }
}
