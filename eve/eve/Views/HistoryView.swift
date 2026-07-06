//
//  HistoryView.swift
//  Eve
//
//  Created by cabsss on 06/07/26.
//

import SwiftUI
import SwiftData

/// The full activity timeline: everything Eve has observed or learned.
struct HistoryView: View {

    @Query(sort: \HistoryItem.timestamp, order: .reverse)
    private var items: [HistoryItem]

    var body: some View {
        NavigationStack {
            Group {

                if items.isEmpty {

                    ContentUnavailableView(
                        "Nothing yet",
                        systemImage: "clock",
                        description: Text(
                            "Every observation, sync, question and insight will appear here as a timeline."
                        )
                    )

                } else {

                    List(items) { item in

                        HStack(alignment: .top, spacing: 12) {

                            Image(systemName: icon(for: item.type))
                                .foregroundStyle(.tint)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {

                                Text(item.title)

                                if !item.detail.isEmpty {
                                    Text(item.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Text(
                                    item.timestamp.formatted(
                                        date: .abbreviated,
                                        time: .shortened
                                    )
                                )
                                .font(.caption2)
                                .foregroundStyle(.tertiary)

                            }

                        }

                    }

                }

            }
            .navigationTitle("History")
        }
    }

    private func icon(for type: HistoryItemType) -> String {
        switch type {
        case .calendarImported: "calendar"
        case .reminderCompleted: "checkmark.circle"
        case .reminderIgnored: "bell.slash"
        case .reminderSnoozed: "zzz"
        case .questionAnswered: "questionmark.bubble"
        case .insightCreated: "sparkles"
        case .insightUpdated: "arrow.triangle.2.circlepath"
        case .insightEdited: "pencil"
        case .locationVisited: "mappin.and.ellipse"
        }
    }

}
