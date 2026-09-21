import Foundation

/// A framework-independent interval layout for the day canvas. The caller
/// converts minutes and columns into points, which keeps overlap behaviour
/// deterministic and straightforward to test without SwiftUI.
struct CalendarDayInterval: Identifiable {
    let id: String
    let startMinute: Int
    let endMinute: Int
}

struct CalendarDayPlacement: Identifiable {
    let interval: CalendarDayInterval
    let column: Int
    let columnCount: Int

    var id: String { interval.id }
}

enum CalendarDayLayout {
    /// Groups intervals into clusters of mutual — including transitive —
    /// time overlap: if A overlaps B and B overlaps C, all three land in
    /// one cluster even though A and C might not directly overlap. Each
    /// cluster is sorted by start time. Exposed separately from
    /// `placements` so callers that want to know *which* intervals collide,
    /// without needing a column assignment, can reuse the same grouping —
    /// e.g. collapsing every reminder due at once into a single stack.
    static func clusters(for intervals: [CalendarDayInterval]) -> [[CalendarDayInterval]] {
        let sorted = intervals.sorted {
            if $0.startMinute == $1.startMinute { return $0.endMinute < $1.endMinute }
            return $0.startMinute < $1.startMinute
        }

        var result: [[CalendarDayInterval]] = []
        var cursor = 0

        while cursor < sorted.count {
            var cluster = [sorted[cursor]]
            var clusterEnd = sorted[cursor].endMinute
            cursor += 1

            while cursor < sorted.count, sorted[cursor].startMinute < clusterEnd {
                cluster.append(sorted[cursor])
                clusterEnd = max(clusterEnd, sorted[cursor].endMinute)
                cursor += 1
            }

            result.append(cluster)
        }

        return result
    }

    static func placements(for intervals: [CalendarDayInterval]) -> [CalendarDayPlacement] {
        var result: [CalendarDayPlacement] = []

        for cluster in clusters(for: intervals) {
            var columnEnds: [Int] = []
            var columns: [(CalendarDayInterval, Int)] = []

            for interval in cluster {
                if let reusable = columnEnds.firstIndex(where: { $0 <= interval.startMinute }) {
                    columnEnds[reusable] = interval.endMinute
                    columns.append((interval, reusable))
                } else {
                    columnEnds.append(interval.endMinute)
                    columns.append((interval, columnEnds.count - 1))
                }
            }

            result.append(contentsOf: columns.map {
                CalendarDayPlacement(interval: $0.0, column: $0.1, columnCount: columnEnds.count)
            })
        }

        return result
    }
}
