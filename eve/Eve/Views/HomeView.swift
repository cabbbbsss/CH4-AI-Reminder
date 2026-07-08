import SwiftUI
import SwiftData

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // RRGGBBAA (32-bit)
            (r, g, b, a) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

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

    /// Only today's events, in time order — this is "Today's Routine".
    private var todaysEvents: [CalendarEvent] {
        let calendar = Calendar.current
        return events.filter { calendar.isDateInToday($0.startDate) }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<12: "Good morning!"
        case 12..<17: "Good afternoon!"
        default: "Good evening!"
        }
    }

    /// The AI suggestion bubble text: Eve's latest decision if it has
    /// one, otherwise a friendly prompt to tap and ask.
    private var suggestionText: String {
        if viewModel?.assistant.isThinking == true {
            return "Thinking about your day…"
        }
        if let decision = viewModel?.assistant.lastDecision, decision.shouldNotify {
            return decision.body
        }
        return "Tap me anytime and I'll look at your day and suggest what matters."
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                  stops: [
                    .init(color: Color(hex: "#AACBEB"), location: 0.75),
                    .init(color: Color(hex: "#E8F3FF"), location: 1.0)
                  ],
                  startPoint: .top,
                  endPoint: .bottom
                )
                .ignoresSafeArea()

                Rectangle()
                    .fill(Color.init(hex: "#3E6590"))
                    .cornerRadius(20)
                    .frame(width: 390, height: 490)
                    .ignoresSafeArea(edges: .top)
                    .frame(maxHeight: .infinity, alignment: .top)

                Rectangle()
                    .fill(Color.init(hex: "#1D3557"))
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
                                .font(.system(size: 30, weight: .medium, design: .default))
                                .foregroundColor(Color(hex: "#BCCFE3"))
                                .padding(.leading, 30)

                            Spacer()

                            NavigationLink(destination: SettingsView()) {
                                Image(systemName: "gearshape.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color.primaryEve)
                                    .padding(5)
                            }
                            .buttonStyle(.glassProminent)
                            .clipShape(Circle())
                            .frame(maxHeight: .infinity, alignment: .topTrailing)
                            .padding(20)
                        }
                        .padding(.top, 20)

                        // AI Suggestion Bubble — tap Eve to run one assistant cycle.
                        HStack(alignment: .top, spacing: 10) {
                            Button {
                                Task { await viewModel?.askEve() }
                            } label: {
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
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel == nil || viewModel?.assistant.isThinking == true)

                            VStack(alignment: .leading) {
                                Text(suggestionText)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.black)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(16)
                            .background(Color(hex: "#C4D7EA"))
                            .cornerRadius(20, corners: [.topRight, .bottomLeft, .bottomRight])
                            .cornerRadius(4, corners: [.topLeft])
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .animation(.easeInOut, value: suggestionText)

                        // Today's Routine
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Today's Routine")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(Color(hex: "#1D3557"))
                                .padding(.horizontal, 20)
                                .padding(.top, 20)

                            ScrollView(.vertical, showsIndicators: true) {
                                if todaysEvents.isEmpty {
                                    Text("No calendar events today.")
                                        .font(.system(size: 14))
                                        .foregroundColor(Color(hex: "#1D3557").opacity(0.6))
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
                                                isLast: index == todaysEvents.count - 1
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 20)
                                }
                            }
                        }
                        .background()
                        .opacity(0.9)
                        .frame(height: 200)
                        .cornerRadius(10)
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                        // Synced Reminders
                        Text("Synced Reminders")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Color(hex: "#1D3557"))
                            .padding(.horizontal, 30)
                            .padding(.top, 40)

                        HStack(spacing: 20) {
                            // Location Card
                            NavigationLink(destination: LocationView()) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Image(systemName: "location.fill")
                                        .font(.system(size: 30))
                                        .foregroundColor(Color(hex: "#1D3557"))
                                        .frame(maxWidth: .infinity, alignment: .center)

                                    Text("Location")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(Color(hex: "#1D3557"))
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                                .padding(20)
                                .background(Color(hex: "#E8F3FF"))
                                .cornerRadius(20)
                            }

                            // Calendar Card
                            NavigationLink(destination: CalendarView()) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 30))
                                        .foregroundColor(Color(hex: "#1D3557"))
                                        .frame(maxWidth: .infinity, alignment: .center)

                                    Text("Calendar")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(Color(hex: "#1D3557"))
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                                .padding(20)
                                .background(Color(hex: "#E8F3FF"))
                                .cornerRadius(20)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 10)

                        // Bottom Area
                        VStack(spacing: 10) {
                            // Robot floating icon
                            Image("Avatar")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 130, height: 130)

                            NavigationLink(destination: InsightView()) {
                                Text("View Insights")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(Color(hex: "#E0ECF7"))
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 20)
                                    .background(Color(hex: "#368BC8"))
                                    .cornerRadius(20)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
            }
            .navigationBarHidden(true)
        }
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

    /// True if the given event is happening right now.
    private func isNow(_ event: CalendarEvent) -> Bool {
        let now = Date()
        return event.startDate <= now && now <= event.endDate
    }

    /// Cycles through the three design accent colors for timeline dots.
    private func dotColor(for index: Int) -> Color {
        let palette = [
            Color(hex: "#3FA9F5"),
            Color(hex: "#4A60B2"),
            Color(hex: "#E0ECF7")
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
                        .fill(Color(hex: "#E0ECF7"))
                        .frame(width: 2)
                        .padding(.top, 8)
                }
            }
            .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(time)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(isCurrent ? Color(hex: "#FFFFFF").opacity(0.8) : Color.black.opacity(0.6))
                
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(isCurrent ? .white : .black)
                
                if !location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10))
                        Text(location)
                            .font(.system(size: 13))
                    }
                    .foregroundColor(isCurrent ? Color(hex: "#FFFFFF").opacity(0.8) : Color.black.opacity(0.6))
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isCurrent ? Color(hex: "#1D3557") : Color.clear)
            .cornerRadius(12)
            .padding(.bottom, 8)
        }
    }
}

#Preview {
    HomeView()
}

