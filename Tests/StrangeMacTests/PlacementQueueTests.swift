import XCTest
import StrangeCore
@testable import StrangeMac

@MainActor private final class PlacementGate {
    var requests: [(WindowZone, pid_t)] = []
    var successes: [WindowZone] = []
    var failures: [any Error] = []
    private var operations: [CheckedContinuation<Void, any Error>] = []
    private var startWaiter: (Int, CheckedContinuation<Void, Never>)?
    private var successWaiter: (Int, CheckedContinuation<Void, Never>)?
    private var failureWaiter: (Int, CheckedContinuation<Void, Never>)?

    func operate(_ zone: WindowZone, _ processID: pid_t) async throws {
        try await withCheckedThrowingContinuation { continuation in
            requests.append((zone, processID))
            operations.append(continuation)
            if let (count, waiter) = startWaiter, requests.count >= count {
                startWaiter = nil
                waiter.resume()
            }
        }
    }

    func waitForStarts(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { startWaiter = (count, $0) }
    }

    func waitForSuccesses(_ count: Int) async {
        if successes.count >= count { return }
        await withCheckedContinuation { successWaiter = (count, $0) }
    }

    func waitForFailures(_ count: Int) async {
        if failures.count >= count { return }
        await withCheckedContinuation { failureWaiter = (count, $0) }
    }

    func succeed(_ zone: WindowZone) {
        successes.append(zone)
        if let (count, waiter) = successWaiter, successes.count >= count {
            successWaiter = nil
            waiter.resume()
        }
    }

    func fail(_ error: any Error) {
        failures.append(error)
        if let (count, waiter) = failureWaiter, failures.count >= count {
            failureWaiter = nil
            waiter.resume()
        }
    }

    func finish(_ error: (any Error)? = nil) {
        let continuation = operations.removeFirst()
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
    }

    func makeQueue() -> PlacementQueue {
        PlacementQueue(operation: { [self] in try await operate($0, $1) },
                       onSuccess: { [self] in succeed($0) },
                       onFailure: { [self] in fail($0) })
    }
}

final class PlacementQueueTests: XCTestCase {
    @MainActor func testMixedZoneAndDisplayCommandsPreserveOrderIncludingRepeatedMoves() async {
        let gate = PlacementGate()
        var commands: [WindowCommand] = []
        var completed: [WindowCommand] = []
        let queue = PlacementQueue(commandOperation: { command, processID in
            commands.append(command)
            try await gate.operate(.whole, processID)
        }, onCommandSuccess: { command in
            completed.append(command)
            gate.succeed(.whole)
        }, onFailure: { gate.fail($0) })
        let expected: [WindowCommand] = [
            .zone(.leftThird), .moveDisplay(.right), .moveDisplay(.right), .zone(.centerThird)
        ]
        for command in expected { queue.enqueue(command: command, processID: 1) }
        for count in 1...expected.count {
            await gate.waitForStarts(count)
            gate.finish()
        }
        await gate.waitForSuccesses(expected.count)
        XCTAssertEqual(commands, expected)
        XCTAssertEqual(completed, expected)
        XCTAssertTrue(gate.failures.isEmpty)
    }

    @MainActor func testRepeatedDisplayMoveDuringOperationAdvancesAgain() async {
        let gate = PlacementGate()
        var commands: [WindowCommand] = []
        let queue = PlacementQueue(commandOperation: { command, processID in
            commands.append(command)
            try await gate.operate(.whole, processID)
        }, onCommandSuccess: { _ in gate.succeed(.whole) })
        queue.enqueue(command: .moveDisplay(.right), processID: 1)
        await gate.waitForStarts(1)
        queue.enqueue(command: .moveDisplay(.right), processID: 1)
        gate.finish()
        await gate.waitForStarts(2)
        gate.finish()
        await gate.waitForSuccesses(2)
        XCTAssertEqual(commands, [.moveDisplay(.right), .moveDisplay(.right)])
    }

    @MainActor func testLegacyOperationRejectsDisplayCommandAndContinues() async {
        let gate = PlacementGate()
        let queue = gate.makeQueue()
        queue.enqueue(command: .moveDisplay(.left), processID: 1)
        queue.enqueue(zone: .rightThird, processID: 1)
        await gate.waitForFailures(1)
        await gate.waitForStarts(1)
        gate.finish()
        await gate.waitForSuccesses(1)
        XCTAssertEqual(gate.failures.first as? PlacementError, .unsupportedWindow)
        XCTAssertEqual(gate.requests.map(\.0), [.rightThird])
    }

    @MainActor func testRapidThirdsPreserveOrderAndInputDuringOperation() async {
        let gate = PlacementGate()
        let queue = gate.makeQueue()
        queue.enqueue(zone: .leftThird, processID: 1)
        queue.enqueue(zone: .centerThird, processID: 1)
        await gate.waitForStarts(1)
        queue.enqueue(zone: .rightThird, processID: 1)
        for count in 1...3 {
            await gate.waitForStarts(count)
            gate.finish()
        }
        await gate.waitForSuccesses(3)
        XCTAssertEqual(gate.requests.map(\.0), [.leftThird, .centerThird, .rightThird])
        XCTAssertEqual(gate.successes, [.leftThird, .centerThird, .rightThird])
        XCTAssertTrue(gate.failures.isEmpty)
    }

    @MainActor func testOnlyConsecutiveDuplicatesWithSameProcessAreCoalesced() async {
        let gate = PlacementGate()
        let queue = gate.makeQueue()
        queue.enqueue(zone: .leftThird, processID: 1)
        await gate.waitForStarts(1)
        queue.enqueue(zone: .leftThird, processID: 1)
        queue.enqueue(zone: .centerThird, processID: 1)
        queue.enqueue(zone: .centerThird, processID: 1)
        queue.enqueue(zone: .leftThird, processID: 1)
        queue.enqueue(zone: .leftThird, processID: 2)
        for count in 1...4 {
            await gate.waitForStarts(count)
            gate.finish()
        }
        await gate.waitForSuccesses(4)
        XCTAssertEqual(gate.requests.map(\.0), [.leftThird, .centerThird, .leftThird, .leftThird])
        XCTAssertEqual(gate.requests.map(\.1), [1, 1, 1, 2])
    }

    @MainActor func testBoundedPendingQueueReportsOverflowAndKeepsAcceptedOrder() async {
        let gate = PlacementGate()
        let queue = gate.makeQueue()
        queue.enqueue(zone: .whole, processID: 1)
        await gate.waitForStarts(1)
        let zones: [WindowZone] = (0..<32).map { $0.isMultiple(of: 2) ? .leftThird : .rightThird }
        for zone in zones { queue.enqueue(zone: zone, processID: 1) }
        queue.enqueue(zone: .centerThird, processID: 1)
        XCTAssertEqual(gate.failures.count, 1)
        XCTAssertEqual(gate.failures.first as? PlacementQueueError, .queueFull)
        for count in 1...33 {
            await gate.waitForStarts(count)
            gate.finish()
        }
        await gate.waitForSuccesses(33)
        XCTAssertEqual(gate.requests.map(\.0), [.whole] + zones)
    }

    @MainActor func testCancellationDiscardsStaleRequestsAndDoesNotOverwriteNewWorker() async {
        let gate = PlacementGate()
        let queue = gate.makeQueue()
        queue.enqueue(zone: .leftThird, processID: 1)
        await gate.waitForStarts(1)
        queue.enqueue(zone: .centerThird, processID: 1)
        queue.cancel()
        queue.enqueue(zone: .rightThird, processID: 2)
        await gate.waitForStarts(2)
        gate.finish(CancellationError())
        gate.finish()
        await gate.waitForSuccesses(1)
        XCTAssertEqual(gate.requests.map(\.0), [.leftThird, .rightThird])
        XCTAssertEqual(gate.successes, [.rightThird])
        XCTAssertTrue(gate.failures.isEmpty)
    }

    @MainActor func testFocusAndPermissionFailuresClearStaleRequests() async {
        for error in [PlacementError.focusChanged, .accessibilityPermissionRequired] {
            let gate = PlacementGate()
            let queue = gate.makeQueue()
            queue.enqueue(zone: .leftThird, processID: 1)
            await gate.waitForStarts(1)
            queue.enqueue(zone: .centerThird, processID: 1)
            gate.finish(error)
            await gate.waitForFailures(1)
            queue.enqueue(zone: .rightThird, processID: 2)
            await gate.waitForStarts(2)
            gate.finish()
            await gate.waitForSuccesses(1)
            XCTAssertEqual(gate.requests.map(\.0), [.leftThird, .rightThird])
            XCTAssertEqual(gate.failures.first as? PlacementError, error)
        }
    }

    @MainActor func testNonterminalFailureContinuesToNextPlacement() async {
        let gate = PlacementGate()
        let queue = gate.makeQueue()
        queue.enqueue(zone: .leftThird, processID: 1)
        queue.enqueue(zone: .rightThird, processID: 1)
        await gate.waitForStarts(1)
        gate.finish(PlacementError.frameNotAccepted)
        await gate.waitForStarts(2)
        gate.finish()
        await gate.waitForSuccesses(1)
        XCTAssertEqual(gate.requests.map(\.0), [.leftThird, .rightThird])
        XCTAssertEqual(gate.failures.first as? PlacementError, .frameNotAccepted)
    }

    @MainActor func testDrainNotifiesIdleAndCanStartAnotherBurst() async {
        let gate = PlacementGate()
        var idleCount = 0
        let queue = PlacementQueue(
            operation: { try await gate.operate($0, $1) },
            onSuccess: { gate.succeed($0) },
            onIdle: { idleCount += 1 }
        )
        XCTAssertFalse(queue.isRunning)
        queue.enqueue(zone: .leftThird, processID: 1)
        XCTAssertTrue(queue.isRunning)
        await gate.waitForStarts(1)
        gate.finish()
        await gate.waitForSuccesses(1)
        XCTAssertFalse(queue.isRunning)
        XCTAssertEqual(idleCount, 1)
        queue.enqueue(zone: .leftThird, processID: 1)
        await gate.waitForStarts(2)
        gate.finish()
        await gate.waitForSuccesses(2)
        XCTAssertFalse(queue.isRunning)
        XCTAssertEqual(idleCount, 2)
        XCTAssertEqual(gate.successes, [.leftThird, .leftThird])
    }

    @MainActor func testQueueCanDeallocateWhileOperationIsSuspended() async {
        let gate = PlacementGate()
        var queue: PlacementQueue? = gate.makeQueue()
        weak var weakQueue = queue
        queue?.enqueue(zone: .leftThird, processID: 1)
        await gate.waitForStarts(1)
        queue = nil
        XCTAssertNil(weakQueue)
        // Release the deliberately non-cooperative test operation as well.
        gate.finish(CancellationError())
    }
}
