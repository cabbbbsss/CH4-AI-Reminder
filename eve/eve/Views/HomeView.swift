import SwiftUI
import SwiftData

// Custom corner radius modifier
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape( RoundedCorner(radius: radius, corners: corners) )
    }
}

struct HomeView: View {

    @Environment(\.modelContext) private var modelContext

    // The composition root ported from TodayView: owns the sync,
    // location and assistant managers and starts them in order.
    @State private var viewModel: TodayViewModel?

    // Calendar mirror kept fresh by EventKitSyncManager. @Query
    // re-renders the routine automatically when a sync writes.
    @Query(sort: \CalendarEvent.startDate)
    private var events: [CalendarEvent]

    // The user's profile (for the personalised greeting). @Query keeps the
    // greeting in sync when the name is changed in Settings.
    @Query private var profiles: [UserProfile]

    // Which Today's Routine row is expanded, and its AI-generated prep
    // checklist once fetched. Keyed by occurrenceID so each event caches
    // independently and re-expanding doesn't re-ask the model.
    @State private var expandedEventID: String?
    @State private var preparationByEvent: [String: [String]] = [:]
    @State private var loadingPreparationEventID: String?

    /// Only today's events, in time order — this is "Today's Routine".
    private var todaysEvents: [CalendarEvent] {
        let calendar = Calendar.current
        return events.filter { calendar.isDateInToday($0.startDate) }
    }

    private var greeting: String {
        let timeOfDay: String
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<12: timeOfDay = "Good morning"
        case 12..<17: timeOfDay = "Good afternoon"
        default: timeOfDay = "Good evening"
        }

        // Personalise with the name from Settings once it's set.
        if let name = profiles.first?.name, !name.isEmpty {
            return "\(timeOfDay), \(name)!"
        }
        return "\(timeOfDay)!"
    }

    /// The AI suggestion bubble text: Eve's latest decision if it has
    /// one, otherwise a friendly prompt to tap and ask.
    ///
    /// Distinguishes "haven't asked yet" from "asked, nothing needed" and
    /// "asked, it failed" — otherwise a successful-but-quiet decision and a
    /// silent failure both look identical to the untapped state, making it
    /// impossible to tell whether tapping did anything at all.
    private var suggestionText: String {
        if viewModel?.assistant.isThinking == true {
            return "Thinking about your day…"
        }
        if let error = viewModel?.assistant.errorMessage {
            return "Something went wrong: \(error)"
        }
        if let decision = viewModel?.assistant.lastDecision {
            return decision.shouldNotify
                ? decision.body
                : "Nothing urgent right now — I'll let you know if something comes up."
        }
        return "Tap me anytime and I'll look at your day and suggest what matters."
    }

    var body: some View {
        TabView {
            NavigationStack {
                homeTab
                    .navigationBarHidden(true)
            }
            .tabItem {
                Label("Dashboard", systemImage: "house.fill")
            }

            NavigationStack {
                LocationView()
            }
            .tabItem {
                Label("Location", systemImage: "location.fill")
            }

            NavigationStack {
                CalendarView()
            }
            .tabItem {
                Label("Calendar", systemImage: "calendar")
            }

            NavigationStack {
                InsightView()
            }
            .tabItem {
                Label("Insight", systemImage: "sparkles")
            }
        }
        .tint(Color.accentColor)
        .task {
            // Create the managers once, then start syncing + monitoring.
            guard viewModel == nil else { return }
            let vm = TodayViewModel(context: modelContext)
            viewModel = vm
            await vm.start()

            // Populate the suggestion bubble with a real reminder on first
            // appear — silently, so opening Home doesn't fire a notification.
            await vm.assistant.generateInitialInsights(currentPlace: vm.location.currentPlace)
        }
    }

    private var homeTab: some View {
        ZStack {
            LinearGradient(
              stops: [
                .init(color: Color(.bgPrimary), location: 0.75),
                .init(color: Color(.bgSecondary), location: 1.0)
              ],
              startPoint: .top,
              endPoint: .bottom
            )
            .ignoresSafeArea()

            Rectangle()
                .fill(Color(.bgSecondary))
                .cornerRadius(20)
                .frame(width: 390, height: 490)
                .ignoresSafeArea(edges: .top)
                .frame(maxHeight: .infinity, alignment: .top)

            Rectangle()
                .fill(Color(.bgPrimary))
                .cornerRadius(20)
                .blur(radius: 100)
                .frame(width: 400, height: 300)
                .ignoresSafeArea(edges: .top)
                .ignoresSafeArea(edges: .horizontal)
                .frame(maxHeight: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text(greeting)
                        .font(.system(size: 26, weight: .medium, design: .default))
                        .foregroundColor(Color(.textPrimary))
                        .padding(.leading, 30)

                    Spacer()

                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            // White, not accent: .glassProminent tints the button's
                            // background with the accent color, so an accent-colored
                            // gear was invisible against it. White reads in both modes.
                            .foregroundColor(Color(.textPrimary))
                            .foregroundStyle(.white)
                            .padding(5)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .background(Color(.bgTertiary))
                    .clipShape(Circle())
                    .frame(maxHeight: .infinity, alignment: .topTrailing)
                    .padding(20)
                }
                .padding(.top, 20)

                // AI Suggestion Bubble — tap to refresh Eve's read on your day (dashboard only, no notification).
                Button {
                    Task { await viewModel?.askEve() }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            Image("Avatar")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 70, height: 70)

                            if viewModel?.assistant.isThinking == true {
                                ProgressView()
                                    .tint(.white)
                            }
                        }

                        VStack(alignment: .leading) {
                            // Capped so an over-long model response can't
                            // push Today's Routine off the screen. The
                            // prompt asks for one sentence under 18 words,
                            // which fits in three lines here — this is the
                            // guarantee for when it doesn't comply, since
                            // nothing about a generated string is certain.
                            Text(suggestionText)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(Color(.textPrimary))
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .background(Color(.bgSecondary))
                        .cornerRadius(20, corners: [.topRight, .bottomLeft, .bottomRight])
                        .cornerRadius(4, corners: [.topLeft])
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel == nil || viewModel?.assistant.isThinking == true)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .animation(.easeInOut, value: suggestionText)

                // Today's Routine
                VStack(alignment: .leading, spacing: 16) {
                    Text("Today's Routine")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Color(.textPrimary))
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    ScrollView(.vertical, showsIndicators: true) {
                        if todaysEvents.isEmpty {
                            Text("No calendar events today.")
                                .font(.system(size: 14))
                                .foregroundColor(Color(.textPrimary).opacity(0.6))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 24)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(todaysEvents.enumerated()), id: \.element.occurrenceID) { index, event in
                                    TimelineItem(
                                        time: event.startDate.formatted(date: .omitted, time: .shortened),
                                        title: event.title,
                                        location: event.notes ?? "",
                                        isCurrent: isNow(event),
                                        dotColor: dotColor(for: index),
                                        isLast: index == todaysEvents.count - 1,
                                        isExpanded: expandedEventID == event.occurrenceID,
                                        isLoadingPreparation: loadingPreparationEventID == event.occurrenceID,
                                        preparationItems: preparationByEvent[event.occurrenceID],
                                        onToggle: { toggleExpand(event) }
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                    }
                }
                // Fixed light color, not the adaptive system background —
                // the text inside is hardcoded dark, so an adaptive
                // background would turn near-black in Dark Mode and make
                // the text unreadable. Matches every other card on this screen.
                .background(Color(.bgSecondary))
                .opacity(0.9)
                .frame(maxHeight: .infinity)
                .cornerRadius(10)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 8)
            }
        }
    }

    /// True if the given event is happening right now.
    private func isNow(_ event: CalendarEvent) -> Bool {
        let now = Date()
        return event.startDate <= now && now <= event.endDate
    }

    /// Expands/collapses a Today's Routine row. On first expand, kicks off
    /// an AI call for that event's prep checklist and caches the result so
    /// collapsing and re-expanding doesn't ask the model again.
    private func toggleExpand(_ event: CalendarEvent) {

        if expandedEventID == event.occurrenceID {
            expandedEventID = nil
            return
        }

        expandedEventID = event.occurrenceID

        guard preparationByEvent[event.occurrenceID] == nil,
              let assistant = viewModel?.assistant
        else { return }

        loadingPreparationEventID = event.occurrenceID

        Task {
            let items = await assistant.suggestPreparation(
                forEventTitled: event.title,
                at: event.startDate,
                notes: event.notes,
                location: event.location
            )
            preparationByEvent[event.occurrenceID] = items
            if loadingPreparationEventID == event.occurrenceID {
                loadingPreparationEventID = nil
            }
        }

    }

    /// Cycles through the three design accent colors for timeline dots.
    private func dotColor(for index: Int) -> Color {
        let palette = [
            Color.accentColor,
            Color(.textPrimary),
            Color(.bgTertiary)
        ]
        return palette[index % palette.count]
    }
}

struct TimelineItem: View {
    var time: String
    var title: String
    var location: String
    var isCurrent: Bool
    var dotColor: Color
    var isLast: Bool

    /// Expand state + AI prep checklist, owned by the parent HomeView so
    /// the fetch-once-cache lives above this stateless row.
    var isExpanded: Bool = false
    var isLoadingPreparation: Bool = false
    var preparationItems: [String]? = nil
    var onToggle: (() -> Void)? = nil

    private var textColor: Color {
        isCurrent ? Color(.textSecondary) : Color(.textPrimary)
    }

    private var secondaryTextColor: Color {
        isCurrent ? Color(.textSecondary).opacity(0.8) : Color(.textPrimary).opacity(0.6)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Timeline line & dot
            VStack(spacing: 0) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 12, height: 12)
                    .padding(.top, 16)

                if !isLast {
                    Rectangle()
                        .fill(Color(.bgSecondary))
                        .frame(width: 2)
                        .padding(.top, 8)
                }
            }
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Button {
                        onToggle?()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(time)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(secondaryTextColor)

                            Text(title)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(textColor)

                            if !location.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "location.fill")
                                        .font(.system(size: 10))
                                    Text(location)
                                        .font(.system(size: 13))
                                }
                                .foregroundColor(secondaryTextColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(onToggle == nil)

                    Spacer(minLength: 8)

                    if let onToggle {
                        Button(action: onToggle) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(secondaryTextColor)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                .padding(6)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if isExpanded {
                    preparationSection
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isCurrent ? Color(.textPrimary) : Color.clear)
            .cornerRadius(12)
            .padding(.bottom, 8)
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    /// AI-generated "things you might forget" for this specific event.
    @ViewBuilder
    private var preparationSection: some View {
        VStack(alignment: .leading, spacing: 6) {

            if isLoadingPreparation {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(secondaryTextColor)
                    Text("Thinking about what you might need…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                }
            } else if let items = preparationItems {
                if items.isEmpty {
                    Text("Nothing specific to prepare — you're all set.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                } else {
                    ForEach(items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                                .foregroundColor(secondaryTextColor)
                                .padding(.top, 2)
                            Text(item)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(textColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

        }
        .padding(.top, 8)
        .padding(.leading, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

#Preview {
    HomeView()
}

