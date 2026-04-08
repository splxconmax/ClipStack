import Foundation

public enum ClipSearch {
    public static func matches(_ clip: ClipRecord, query: String, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return true
        }

        let haystack = [clip.searchText, clip.sourceAppName, dateSearchText(for: clip.createdAt, now: now, calendar: calendar)]
            .joined(separator: " ")
            .lowercased()

        return trimmed
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .allSatisfy { haystack.contains($0) }
    }

    static func dateSearchText(for date: Date, now: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = calendar
        formatter.dateFormat = "EEEE EEE MMMM MMM d yyyy"

        var tokens = formatter.string(from: date).lowercased()
        if calendar.isDate(date, inSameDayAs: now) {
            tokens += " today just now"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            tokens += " yesterday"
        }
        return tokens
    }
}

public enum ClipGrouping {
    public static func listItems(from clips: [ClipRecord], expandedGroupIDs: Set<String>) -> [ClipListItem] {
        var items: [ClipListItem] = []
        var index = 0

        while index < clips.count {
            let current = clips[index]
            var groupClips = [current]
            var nextIndex = index + 1

            while nextIndex < clips.count {
                let nextClip = clips[nextIndex]
                guard isCompatible(lhs: current, rhs: nextClip) else {
                    break
                }

                let newest = groupClips.first?.createdAt ?? current.createdAt
                guard newest.timeIntervalSince(nextClip.createdAt) <= 300 else {
                    break
                }

                groupClips.append(nextClip)
                nextIndex += 1
            }

            if groupClips.count >= 3 {
                let groupID = makeGroupID(from: groupClips)
                if expandedGroupIDs.contains(groupID) {
                    items.append(contentsOf: groupClips.map { .clip($0) })
                } else {
                    items.append(.group(ClipGroup(
                        id: groupID,
                        sourceAppName: current.sourceAppName,
                        sourceBundleID: current.sourceBundleID,
                        sourceIconKey: current.sourceIconKey,
                        clips: groupClips
                    )))
                }
                index = nextIndex
            } else {
                items.append(.clip(current))
                index += 1
            }
        }

        return items
    }

    private static func isCompatible(lhs: ClipRecord, rhs: ClipRecord) -> Bool {
        let lhsKey = lhs.sourceBundleID ?? lhs.sourceAppName
        let rhsKey = rhs.sourceBundleID ?? rhs.sourceAppName
        return lhsKey == rhsKey
    }

    private static func makeGroupID(from clips: [ClipRecord]) -> String {
        let ids = clips.map(\.id.uuidString).joined(separator: "-")
        return "group-\(ids)"
    }
}
