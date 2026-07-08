import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.dismiss) var dismiss

    // The unified activity timeline, newest first.
    @Query(sort: \HistoryItem.timestamp, order: .reverse)
    private var items: [HistoryItem]

    // Which rows are expanded. Items with detail start expanded (see isExpanded).
    @State private var collapsedIDs: Set<PersistentIdentifier> = []

    var body: some View {
        ZStack {
            Color(hex: "#E0ECF7").ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Nav
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "chevron.backward.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(Color(hex: "#1D3557"))
                            .background(Circle().fill(Color.white))
                    }

                    Text("History")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.leading, 12)

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                // Character + Chat Bubble
                HStack(alignment: .center, spacing: 16) {
                    // Robot Face Group
                    ZStack {
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 79, height: 79)

                        Circle()
                            .fill(Color.white)
                            .frame(width: 70, height: 70)

                        // Screen
                        Ellipse()
                            .fill(Color(hex: "#1A1916"))
                            .frame(width: 54, height: 36)
                            .offset(y: -2)

                        // Face details
                        VStack(spacing: 4) {
                            HStack(spacing: 14) {
                                Ellipse().fill(Color(hex: "#E0ECF7")).frame(width: 5, height: 3)
                                Ellipse().fill(Color(hex: "#E0ECF7")).frame(width: 5, height: 3)
                            }
                            Rectangle().fill(Color(hex: "#E0ECF7")).frame(width: 13, height: 2)
                        }
                        .offset(y: -2)
                    }

                    // Chat Bubble
                    ZStack(alignment: .leading) {
                        // The triangle pointing left
                        Path { path in
                            path.move(to: CGPoint(x: 10, y: 15))
                            path.addLine(to: CGPoint(x: 0, y: 25))
                            path.addLine(to: CGPoint(x: 10, y: 35))
                        }
                        .fill(Color.white)
                        .offset(x: -8)

                        Text("I learn from your interactions and adaptively remind you.")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(hex: "#1D3557"))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.white)
                            .cornerRadius(12)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 32)

                // Timeline
                if items.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 40))
                            .foregroundColor(Color(hex: "#1E3659").opacity(0.4))
                        Text("Nothing yet")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(Color(hex: "#1E3659"))
                        Text("Every sync, question, visit and insight will appear here as a timeline.")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "#1E3659").opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 48)
                    }
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.persistentModelID) { index, item in
                                HistoryTimelineRow(
                                    dateLabel: dateLabel(at: index),
                                    timeLabel: timeLabel(for: item),
                                    isExpanded: isExpanded(item),
                                    title: item.title,
                                    bodyText: bodyText(for: item),
                                    insightTitle: insightTitle(for: item),
                                    insightBody: insightBody(for: item),
                                    onToggle: { toggle(item) }
                                )
                            }
                        }
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Mapping HistoryItem → designed row

    /// Shows a day header only on the first item of each calendar day.
    private func dateLabel(at index: Int) -> String? {
        let item = items[index]
        let day = Calendar.current.startOfDay(for: item.timestamp)

        if index > 0 {
            let previousDay = Calendar.current.startOfDay(for: items[index - 1].timestamp)
            if day == previousDay { return nil }
        }

        if Calendar.current.isDateInToday(item.timestamp) { return "Today" }
        if Calendar.current.isDateInYesterday(item.timestamp) { return "Yesterday" }
        return item.timestamp.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "8:00 AM" rendered as two lines, matching the design.
    private func timeLabel(for item: HistoryItem) -> String {
        item.timestamp
            .formatted(date: .omitted, time: .shortened)
            .replacingOccurrences(of: " ", with: "\n")
    }

    private func isInsightType(_ item: HistoryItem) -> Bool {
        switch item.type {
        case .insightCreated, .insightUpdated, .insightEdited: true
        default: false
        }
    }

    private func bodyText(for item: HistoryItem) -> String? {
        // Insight events render their detail as a highlighted insight card instead.
        guard !isInsightType(item), !item.detail.isEmpty else { return nil }
        return item.detail
    }

    private func insightTitle(for item: HistoryItem) -> String? {
        isInsightType(item) ? "Learning Insight:" : nil
    }

    private func insightBody(for item: HistoryItem) -> String? {
        guard isInsightType(item), !item.detail.isEmpty else { return nil }
        return item.detail
    }

    // MARK: - Expansion state

    private func hasDetail(_ item: HistoryItem) -> Bool {
        !item.detail.isEmpty
    }

    /// Items with detail start expanded; the user can collapse them.
    private func isExpanded(_ item: HistoryItem) -> Bool {
        hasDetail(item) && !collapsedIDs.contains(item.persistentModelID)
    }

    private func toggle(_ item: HistoryItem) {
        guard hasDetail(item) else { return }
        if collapsedIDs.contains(item.persistentModelID) {
            collapsedIDs.remove(item.persistentModelID)
        } else {
            collapsedIDs.insert(item.persistentModelID)
        }
    }
}

struct HistoryTimelineRow: View {
    var dateLabel: String?
    var timeLabel: String?
    var isExpanded: Bool
    var title: String
    var bodyText: String?
    var insightTitle: String?
    var insightBody: String?
    var onToggle: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left Time Column
            VStack(spacing: 8) {
                if let dateLabel = dateLabel {
                    Text(dateLabel)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(hex: "#1E3659"))
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                }
                if let timeLabel = timeLabel {
                    Text(timeLabel)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(hex: "#1E3659"))
                        .multilineTextAlignment(.center)
                        .padding(.top, dateLabel == nil ? 12 : 0)
                }
            }
            .frame(width: 65, alignment: .top)

            // Timeline Line
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Color(hex: "#7AA0C3"))
                    .frame(width: 4)

                Circle()
                    .fill(Color(hex: "#3FA9F5"))
                    .frame(width: 10, height: 10)
                    .offset(y: dateLabel != nil ? 54 : 14)
            }
            .frame(width: 24)
            .padding(.horizontal, 8)

            // Card Content
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(hex: "#1E3659"))
                    Spacer()
                    if hasBody {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(Color(hex: "#ADC0D3"))
                            .font(.system(size: 12, weight: .bold))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, isExpanded ? 16 : 12)
                .contentShape(Rectangle())
                .onTapGesture { onToggle?() }

                if isExpanded {
                    if let bodyText = bodyText {
                        Text(bodyText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "#1E3659"))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                    }

                    if let insightBody = insightBody {
                        VStack(alignment: .leading, spacing: 4) {
                            if let insightTitle = insightTitle {
                                Text(insightTitle)
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundColor(Color(hex: "#1E3659"))
                            }
                            Text(insightBody)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color(hex: "#1E3659"))
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: "#C4D7EA"))
                    }
                }
            }
            .background(Color(hex: "#E8F3FF"))
            .cornerRadius(12)
            .padding(.top, dateLabel != nil ? 40 : 0)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
    }

    private var hasBody: Bool {
        bodyText != nil || insightBody != nil
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
}
