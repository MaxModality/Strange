import Foundation
import StrangeCore

public enum PlacementQueueError: Error, Equatable, Sendable {
    case queueFull
}

/// Serializes shortcuts without losing rapid, distinct placements. Process IDs
/// remain transient and let the operation reject requests after focus changes.
@MainActor public final class PlacementQueue {
    public typealias Operation = @MainActor (WindowZone, pid_t) async throws -> Void
    public typealias CommandOperation = @MainActor (WindowCommand, pid_t) async throws -> Void
    private struct Request: Equatable {
        let command: WindowCommand
        let processID: pid_t
    }

    private let operation: CommandOperation
    private let onSuccess: (@MainActor (WindowCommand) -> Void)?
    private let onFailure: (@MainActor (any Error) -> Void)?
    private let onIdle: (@MainActor () -> Void)?
    private var pending: [Request] = []
    private var inFlight: Request?
    private var worker: Task<Void, Never>?
    private var generation: UInt64 = 0

    public var isRunning: Bool { worker != nil }

    public convenience init(operation: @escaping Operation,
                onSuccess: (@MainActor (WindowZone) -> Void)? = nil,
                onFailure: (@MainActor (any Error) -> Void)? = nil,
                onIdle: (@MainActor () -> Void)? = nil) {
        self.init(commandOperation: { command, processID in
            guard case .zone(let zone) = command else { throw PlacementError.unsupportedWindow }
            try await operation(zone, processID)
        }, onCommandSuccess: { command in
            if case .zone(let zone) = command { onSuccess?(zone) }
        }, onFailure: onFailure, onIdle: onIdle)
    }

    public init(commandOperation: @escaping CommandOperation,
                onCommandSuccess: (@MainActor (WindowCommand) -> Void)? = nil,
                onFailure: (@MainActor (any Error) -> Void)? = nil,
                onIdle: (@MainActor () -> Void)? = nil) {
        self.operation = commandOperation
        self.onSuccess = onCommandSuccess
        self.onFailure = onFailure
        self.onIdle = onIdle
    }

    isolated deinit { worker?.cancel() }

    public func enqueue(zone: WindowZone, processID: pid_t) {
        enqueue(command: .zone(zone), processID: processID)
    }

    public func enqueue(command: WindowCommand, processID: pid_t) {
        let request = Request(command: command, processID: processID)
        // Zone repeats have one destination. Display moves and resizes are
        // relative, so every press must execute, including consecutive repeats.
        if case .zone = command, request == (pending.last ?? inFlight) { return }
        guard pending.count < 32 else {
            onFailure?(PlacementQueueError.queueFull)
            return
        }
        pending.append(request)
        guard worker == nil else { return }
        let token = generation
        let operation = operation
        // Do not retain the queue across an operation suspension. Deallocation
        // cancels the worker instead of forming queue -> task -> queue cycles.
        worker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let request = self?.nextRequest(generation: token) else { return }
                do {
                    try await operation(request.command, request.processID)
                    guard !Task.isCancelled, self?.generation == token else { return }
                    self?.inFlight = nil
                    self?.onSuccess?(request.command)
                } catch {
                    guard !Task.isCancelled, self?.generation == token else { return }
                    self?.inFlight = nil
                    if error is CancellationError {
                        self?.cancel()
                        return
                    }
                    if let placementError = error as? PlacementError,
                       placementError == .focusChanged || placementError == .accessibilityPermissionRequired {
                        self?.cancel()
                        self?.onFailure?(error)
                        return
                    }
                    self?.onFailure?(error)
                }
            }
        }
    }

    public func cancel() {
        generation &+= 1
        pending.removeAll(keepingCapacity: false)
        inFlight = nil
        worker?.cancel()
        worker = nil
        onIdle?()
    }

    private func nextRequest(generation token: UInt64) -> Request? {
        guard generation == token else { return nil }
        guard !pending.isEmpty else {
            worker = nil
            onIdle?()
            return nil
        }
        let request = pending.removeFirst()
        inFlight = request
        return request
    }
}
