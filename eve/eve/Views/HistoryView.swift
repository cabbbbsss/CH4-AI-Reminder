import SwiftUI
import SwiftData

struct HistoryView: View {
    // The unified activity timeline, newest first.
    @Query(sort: \HistoryItem.timestamp, order: .reverse)
    private var items: [HistoryItem]

    // Which rows are expanded. Items with detail start expanded (see isExpanded).
    @State private var collapsedIDs: Set<PersistentIdentifier> = []

    @State private var isSearching = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    /// The timeline as it's actually drawn.
    ///
    /// Every index-based helper below reads from this rather than `items` —
    /// day headers and repeated-time suppression are computed by comparing a
    /// row with the one above it, so filtering the source without filtering
    /// what they look at would put headers on the wrong rows.
    private var visibleItems: [HistoryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.detail.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.gradientPrimaryStart), Color(.bgPrimary)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Character + Chat Bubble
                HStack(alignment: .center, spacing: 16) {
                    Image("Avatar")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 75, height: 75)

                    Text("I learn from your **interactions** and **adaptively** remind you.")
                        .font(.system(size: 13))
                        .foregroundColor(Color(.textPrimary))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(.bgTertiary))
                        .cornerRadius(10, corners: [.topRight, .bottomLeft, .bottomRight])
                        .cornerRadius(4, corners: [.topLeft])
//                        .background(alignment: .leading) {
//                            BubbleTail()
//                                .fill(Color(.bgSecondary))
//                                .frame(width: 12, height: 18)
//                                .offset(x: -9)
//                        }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 48)

                if isSearching {
                    searchField
                }

                // Timeline
                if visibleItems.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: items.isEmpty ? "clock" : "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(Color(.textPrimary).opacity(0.4))
                        Text(items.isEmpty ? "Nothing yet" : "No matches")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(Color(.textPrimary))
                        Text(items.isEmpty
                             ? "Every sync, question, visit and insight will appear here as a timeline."
                             : "Nothing in your history mentions “\(searchText)”.")
                            .font(.system(size: 13))
                            .foregroundColor(Color(.textPrimary).opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 48)
                    }
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            ForEach(Array(visibleItems.enumerated()), id: \.element.persistentModelID) { index, item in
                                HistoryTimelineRow(
                                    dateLabel: dateLabel(at: index),
                                    timeLabel: timeLabel(at: index),
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
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSearching.toggle()
                    }
                    // Closing also clears, so a hidden filter can never leave
                    // the timeline looking mysteriously short.
                    if isSearching {
                        searchFocused = true
                    } else {
                        searchText = ""
                    }
                } label: {
                    Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                }
                .accessibilityLabel(isSearching ? "Close search" : "Search history")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Color(.textPrimary).opacity(0.5))

            TextField("Search history", text: $searchText)
                .font(.system(size: 15))
                .foregroundColor(Color(.textPrimary))
                .focused($searchFocused)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color(.textPrimary).opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Color(.bgTertiary))
        .cornerRadius(12)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Mapping HistoryItem → designed row

    /// Shows a day header only on the first item of each calendar day.
    private func dateLabel(at index: Int) -> String? {
        let item = visibleItems[index]
        let day = Calendar.current.startOfDay(for: item.timestamp)

        if index > 0 {
            let previousDay = Calendar.current.startOfDay(for: visibleItems[index - 1].timestamp)
            if day == previousDay { return nil }
        }

        if Calendar.current.isDateInToday(item.timestamp) { return "Today" }
        if Calendar.current.isDateInYesterday(item.timestamp) { return "Yesterday" }
        return item.timestamp.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "8:00 AM" rendered as two lines, matching the design. Hidden when it
    /// would repeat the previous row's label (same day, same minute).
    private func timeLabel(at index: Int) -> String? {
        let item = visibleItems[index]
        let label = formattedTime(item.timestamp)

        if index > 0 {
            let previous = visibleItems[index - 1]
            if Calendar.current.isDate(previous.timestamp, inSameDayAs: item.timestamp),
               formattedTime(previous.timestamp) == label {
                return nil
            }
        }

        return label
    }

    private func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
            .replacingOccurrences(of: "\u{202F}", with: "\n")
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

/// Rounded tail on the speech bubble, pointing left at the avatar.
struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.midY),
            control: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.height * 0.2)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.height * 0.8)
        )
        path.closeSubpath()
        return path
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
                        .foregroundColor(Color(.textPrimary))
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                }
                if let timeLabel = timeLabel {
                    Text(timeLabel)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(.textPrimary))
                        .multilineTextAlignment(.center)
                        .padding(.top, dateLabel == nil ? 12 : 0)
                }
            }
            .frame(width: 65, alignment: .top)

            // Timeline Line
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Color(.textQuarternary))
                    .frame(width: 4)

                Circle()
                    .fill(Color.accentColor)
                    .frame(width: dotSize, height: dotSize)
                    .offset(y: dotOffset)
            }
            .frame(width: 24)
            .padding(.horizontal, 8)

            // Card Content
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(.textPrimary))
                        // Without this a Text in a constrained container
                        // truncates to one line rather than growing taller.
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 8)
                    if hasBody {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .foregroundColor(Color(.textTertiary))
                            .font(.system(size: 12, weight: .bold))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, isExpanded ? 16 : 12)
                .contentShape(Rectangle())
                .onTapGesture { onToggle?() }

                if isExpanded {
                    if let bodyText = bodyText {
                        Text(markdown(bodyText))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(.textPrimary))
                            .lineSpacing(3)
                            // An explanation is the whole point of expanding a
                            // row, so it must never be cut off.
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                    }

                    if let insightBody = insightBody {
                        VStack(alignment: .leading, spacing: 4) {
                            if let insightTitle = insightTitle {
                                Text(insightTitle)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(Color(.textPrimary))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(markdown(insightBody))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(.textPrimary))
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.bgTertiary))
                        .cornerRadius(10)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 14)
                    }
                }
            }
            .background(Color(.bgSecondary))
            .cornerRadius(16)
            .shadow(color: Color(.textPrimary).opacity(0.08), radius: 10, y: 4)
            .padding(.top, dateLabel != nil ? 40 : 0)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
    }

    private var hasBody: Bool {
        bodyText != nil || insightBody != nil
    }

    /// Rows without a time label get the design's smaller dot.
    private var dotSize: CGFloat {
        timeLabel != nil ? 12 : 8
    }

    /// Keeps the dot's center where the 12pt dot would sit.
    private var dotOffset: CGFloat {
        let base: CGFloat = dateLabel != nil ? 54 : 14
        return base + (12 - dotSize) / 2
    }

    /// Renders bold spans in the stored detail text, like the design's
    /// emphasized quotes; falls back to plain text if parsing fails.
    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
}
