import CoreData
import Foundation
import SlateSchema
import Testing
@testable import Slate

@Suite
struct SlateAccessGateTests {
    @Test
    func readsRunConcurrently() async throws {
        let gate = SlateAccessGate()
        let counter = Counter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    try? await gate.read {
                        await counter.enter()
                        try? await Task.sleep(nanoseconds: 5_000_000)
                        await counter.exit()
                    }
                }
            }
        }

        let peak = await counter.peak
        #expect(peak >= 2)
    }

    @Test
    func writeIsExclusive() async throws {
        let gate = SlateAccessGate()
        let counter = Counter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    try? await gate.write {
                        await counter.enter()
                        try? await Task.sleep(nanoseconds: 2_000_000)
                        await counter.exit()
                    }
                }
            }
        }

        let peak = await counter.peak
        #expect(peak == 1)
    }

    @Test
    func writeWaitsForActiveReads() async throws {
        let gate = SlateAccessGate()
        let timeline = Timeline()

        async let firstRead: Void = gate.read {
            await timeline.append("read-start")
            try? await Task.sleep(nanoseconds: 20_000_000)
            await timeline.append("read-end")
        }

        try await Task.sleep(nanoseconds: 5_000_000)

        async let write: Void = gate.write {
            await timeline.append("write-start")
            await timeline.append("write-end")
        }

        _ = try await (firstRead, write)

        let events = await timeline.events
        let readEnd = events.firstIndex(of: "read-end")
        let writeStart = events.firstIndex(of: "write-start")
        #expect(readEnd != nil)
        #expect(writeStart != nil)
        #expect(readEnd! < writeStart!)
    }

    @Test
    func queuedWriteHasPriorityOverNewReads() async throws {
        let gate = SlateAccessGate()
        let timeline = Timeline()

        async let firstRead: Void = gate.read {
            await timeline.append("read1-start")
            try? await Task.sleep(nanoseconds: 30_000_000)
            await timeline.append("read1-end")
        }

        try await Task.sleep(nanoseconds: 5_000_000)

        async let write: Void = gate.write {
            await timeline.append("write-start")
            try? await Task.sleep(nanoseconds: 5_000_000)
            await timeline.append("write-end")
        }

        try await Task.sleep(nanoseconds: 5_000_000)

        async let secondRead: Void = gate.read {
            await timeline.append("read2-start")
            await timeline.append("read2-end")
        }

        _ = try await (firstRead, write, secondRead)

        let events = await timeline.events
        let writeEnd = events.firstIndex(of: "write-end")
        let read2Start = events.firstIndex(of: "read2-start")
        #expect(writeEnd != nil)
        #expect(read2Start != nil)
        #expect(writeEnd! < read2Start!)
    }

    @Test
    func cancellationRemovesQueuedWaiter() async throws {
        let gate = SlateAccessGate()
        let counter = Counter()

        let blockingTask = Task {
            try await gate.write {
                await counter.enter()
                try? await Task.sleep(nanoseconds: 50_000_000)
                await counter.exit()
            }
        }

        try await Task.sleep(nanoseconds: 5_000_000)

        let waitingTask = Task {
            try await gate.read {
                await counter.enter()
                await counter.exit()
            }
        }

        try await Task.sleep(nanoseconds: 5_000_000)
        waitingTask.cancel()

        await #expect(throws: CancellationError.self) {
            try await waitingTask.value
        }

        try await blockingTask.value
    }
}

private actor Counter {
    private(set) var current = 0
    private(set) var peak = 0

    func enter() {
        current += 1
        peak = max(peak, current)
    }

    func exit() {
        current -= 1
    }
}

private actor Timeline {
    private(set) var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }
}
