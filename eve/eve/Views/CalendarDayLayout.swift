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
    static func placements(for intervals: [CalendarDayInterval]) -> [CalendarDayPlacement] {
        let sorted = intervals.sorted {
            if $0.startMinute == $1.startMinute { return $0.endMinute < $1.endMinute }
            return $0.startMinute < $1.startMinute
        }

        var result: [CalendarDayPlacement] = []
        var cursor = 0

        while cursor < sorted.count {
            var cluster = [sorted[cursor]]
            var clusterEnd = sorted[cursor].endMinute
            cursor += 1

            // A cluster contains every interval connected by an overlap,
            // including transitive overlaps such as A-B and B-C.
            while cursor < sorted.count, sorted[cursor].startMinute < clusterEnd {
                cluster.append(sorted[cursor])
                clusterEnd = max(clusterEnd, sorted[cursor].endMinute)
                cursor += 1
            }

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
