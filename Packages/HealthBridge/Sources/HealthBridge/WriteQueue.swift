import Foundation
import Synchronization

/// Runs async work one job at a time per id, in the order it was asked for. A delete of a food that
/// is still being saved waits for the save, rather than finishing first and leaving the save to land
/// after it, in Health for good. Jobs for other ids run alongside.
final class WriteQueue: Sendable {
    private let tails = Mutex<[UUID: Task<Void, Never>]>([:])

    /// Waits for the earlier jobs of any of `ids`, then runs `work`.
    func run(_ ids: [UUID], _ work: @escaping @Sendable () async -> Void) async {
        let job = tails.withLock { tails in
            let earlier = Set(ids.compactMap { tails[$0] })
            let job = Task {
                for task in earlier { await task.value }
                await work()
            }
            for id in ids { tails[id] = job }
            return job
        }
        await job.value
        tails.withLock { tails in
            for id in ids where tails[id] == job { tails[id] = nil }
        }
    }

    /// Nothing queued or running.
    var isIdle: Bool { tails.withLock { $0.isEmpty } }
}
