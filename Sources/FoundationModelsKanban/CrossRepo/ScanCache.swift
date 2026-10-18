import Foundation

/// The scan indexes of a ``KanbanHost``, with the state that tells when an index can serve a call with no new scan
/// (plan.md §6.6, index life; divergence.md §16, Gap 1).
///
/// The cache keeps one index for each list of scan places, by the canonical path of each place in scan order. An
/// index is current after a scan whose places each have a running file watcher, until a ``ScanChange`` of one of its
/// places expires it. A current index serves each call: a board ref that names no copy of it is not found, with no
/// new scan and no `git`. An index that is not current serves the board refs that it has, and the next call that
/// needs more scans again, reusing the keys that no change made unknown.
///
/// A change that comes while a scan of its places runs is kept until the scan ends. The scan can have read the old
/// state, so its index is not current, and it forgets the keys that the change made unknown.
///
/// When the scan ends, the cache compares the files of each kept change with the marks of the scan. A change whose
/// files are the same as the scan saw them occurred before the reads of the scan, so it does not make the index stale.
///
/// A change of a place itself, or a batch of lost events of a place, applies as the change of each repo of the place
/// whose files are not the same as the scan saw them (``BoardIndex/resolving(_:)``). Thus a compare after lost events
/// forgets only the keys that the events of the files would forget.
struct ScanCache {
    /// The index and the state of each list of scan places, by the canonical path of each place in scan order.
    private var records: [[String]: ScanRecord] = [:]

    /// Gives the index of the last scan of a list of places, current or not.
    ///
    /// - Parameter places: The canonical path of each place, in scan order.
    /// - Returns: The index, or `nil` before the first scan of the places ends.
    func index(ofPlaces places: [String]) -> BoardIndex? {
        records[places]?.index
    }

    /// Gives the index of a list of places when no change expired it after its scan.
    ///
    /// - Parameter places: The canonical path of each place, in scan order.
    /// - Returns: The index, or `nil` when the places need a new scan.
    func currentIndex(ofPlaces places: [String]) -> BoardIndex? {
        guard let record = records[places], record.isCurrent else {
            return nil
        }
        return record.index
    }

    /// Records the start of a scan of a list of places.
    ///
    /// - Parameter places: The canonical path of each place, in scan order.
    /// - Returns: The index of the earlier scan, for the keys that the new scan reuses, or `nil` for the first scan.
    mutating func beginScan(ofPlaces places: [String]) -> BoardIndex? {
        records[places, default: ScanRecord()].runningScans += 1
        return records[places]?.index
    }

    /// Records the index of a scan that ended.
    ///
    /// - Parameters:
    ///   - scanned: The index that the scan gave.
    ///   - places: The canonical path of each place, in scan order.
    ///   - isWatched: `true` when each place has a running file watcher, so that a later change reaches the cache.
    /// - Returns: The stored index: the scanned index without the keys that a change during the scan made unknown.
    mutating func finishScan(_ scanned: BoardIndex, ofPlaces places: [String], isWatched: Bool) -> BoardIndex {
        records[places, default: ScanRecord()].finishScan(scanned, isWatched: isWatched)
    }

    /// Records the end of a scan that gave no index, for example a cancelled scan. The earlier index stays.
    ///
    /// A scan of places that the cache does not know did not begin. That is a defect of the caller: a debug build
    /// stops, and a release build logs it and changes nothing.
    ///
    /// - Parameter places: The canonical path of each place, in scan order.
    mutating func abandonScan(ofPlaces places: [String]) {
        guard records[places] != nil else {
            assertionFailure("A scan of \(places) stopped, and no scan of the places began")
            Log.kanban.error(
                "A scan stopped for places with no scan that began; the cache stays the same",
                metadata: ["places": "\(places)"]
            )
            return
        }
        records[places]?.endScan()
    }

    /// Applies a change of one scan place to each index of a list of places that holds the place.
    ///
    /// - Parameters:
    ///   - change: The change.
    ///   - place: The canonical path of the place.
    mutating func apply(_ change: ScanChange, inPlace place: String) {
        for places in records.keys where places.contains(place) {
            records[places]?.apply(change)
        }
    }
}

// MARK: - Record

/// The index and the state of one list of scan places in a ``ScanCache``.
private struct ScanRecord {
    /// The index of the last scan that ended, or `nil` before the first scan ends.
    var index: BoardIndex?

    /// `true` when the index can serve a call with no new scan.
    var isCurrent = false

    /// The number of scans of the places that run now.
    var runningScans = 0

    /// The changes that came while a scan ran, in order. The list is empty when no scan runs.
    var changesDuringScans: [ScanChange] = []

    /// Applies a change to the index, and keeps it for each scan that runs now. A change of a place applies as the
    /// change of each repo of the place whose files changed (``BoardIndex/resolving(_:)``).
    ///
    /// - Parameter change: The change.
    mutating func apply(_ change: ScanChange) {
        if runningScans > 0 {
            changesDuringScans.append(change)
        }
        guard let index else {
            return
        }
        let expiring = index.resolving(change).filter(index.isExpired(by:))
        guard !expiring.isEmpty else {
            return
        }
        self.index = expiring.reduce(index) { index, change in index.forgetting(change) }
        isCurrent = false
    }

    /// Stores the index of a scan that ended.
    ///
    /// - Parameters:
    ///   - scanned: The index that the scan gave.
    ///   - isWatched: `true` when each place has a running file watcher.
    /// - Returns: The stored index.
    mutating func finishScan(_ scanned: BoardIndex, isWatched: Bool) -> BoardIndex {
        let expiring = changesDuringScans.flatMap(scanned.resolving).filter(scanned.isExpired(by:))
        let stored = expiring.reduce(scanned) { index, change in index.forgetting(change) }
        index = stored
        isCurrent = isWatched && expiring.isEmpty
        endScan()
        return stored
    }

    /// Records that one running scan ended. The kept changes go when no scan runs.
    ///
    /// A scan end with no running scan is a defect of the caller: a ``ScanCache/beginScan(ofPlaces:)`` does not match
    /// each ``ScanCache/finishScan(_:ofPlaces:isWatched:)`` or ``ScanCache/abandonScan(ofPlaces:)``. A debug build
    /// stops, and a release build logs it and keeps the count of running scans at zero.
    mutating func endScan() {
        if runningScans == 0 {
            assertionFailure("A scan ended with no running scan")
            Log.kanban.error(
                "A scan of the scan places ended with no running scan; the count of running scans stays at zero"
            )
        }
        runningScans = max(runningScans - 1, 0)
        if runningScans == 0 {
            changesDuringScans = []
        }
    }
}
