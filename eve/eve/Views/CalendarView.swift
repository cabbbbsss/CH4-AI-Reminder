import SwiftUI
import SwiftData

/// A single row on the timeline: either an on-the-hour tick mark
/// or a real event, merged and sorted by their actual time.
private enum CalendarTimelineEntry: Identifiable {
    case hour(Date)
    case event(CalendarEvent)

    var id: String {
        switch self {
        case .hour(let date): return "hour-\(date.timeIntervalSince1970)"
        case .event(let event): return "event-\(event.occurrenceID)"
        }
    }

    var sortDate: Date {
        switch self {
        case .hour(let date): return date
        case .event(let event): return event.startDate
        }
    }
}

struct CalendarView: View {
    @Environment(\.dismiss) var dismiss
    @Query(sort: \CalendarEvent.startDate) private var events: [CalendarEvent]

    private var selectedDate: Date { .now }

    private var todaysEvents: [CalendarEvent] {
        events.filter { Calendar.current.isDate($0.startDate, inSameDayAs: selectedDate) }
    }

    private var dateHeaderText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM yyyy"
        let formatted = formatter.string(from: selectedDate)
        return Calendar.current.isDateInToday(selectedDate) ? "Today\n\(formatted)" : formatted
    }

    private var timelineEntries: [CalendarTimelineEntry] {

        guard let first = todaysEvents.first, let last = todaysEvents.last else { return [] }

        let calendar = Calendar.current

        let startHour = calendar.date(
            bySettingHour: calendar.component(.hour, from: first.startDate),
            minute: 0, second: 0, of: first.startDate
        ) ?? first.startDate

        let endHour = calendar.date(
            bySettingHour: calendar.component(.hour, from: last.startDate),
            minute: 0, second: 0, of: last.startDate
        ) ?? last.startDate

        var entries: [CalendarTimelineEntry] = []
        var cursor = startHour

        while cursor <= endHour {
            entries.append(.hour(cursor))
            cursor = calendar.date(byAdding: .hour, value: 1, to: cursor) ?? endHour.addingTimeInterval(3600)
        }

        entries.append(contentsOf: todaysEvents.map { .event($0) })

        return entries.sorted { $0.sortDate < $1.sortDate }

    }

    var body: some View {
        ZStack {
            Color(hex: "#4F83AB").ignoresSafeArea()
            
            GeometryReader { proxy in
                Ellipse()
                    .fill(Color(hex: "#E0ECF7"))
                    .frame(width: proxy.size.width * 2.5, height: proxy.size.height * 1.2)
                    .position(x: proxy.size.width / 2, y: -proxy.size.height * 0.1)
            }
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top Bar
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 32) {
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "chevron.backward.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(Color(hex: "#1D3557"))
                                .background(Circle().fill(Color.white))
                        }
                        
                        Text("Calendar")
                            .font(.system(size: 34, weight: .black, design: .default))
                            .foregroundColor(Color(hex: "#1D3557"))
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 32) {
                        Button(action: {}) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(Color(hex: "#1D3557"))
                                .background(Circle().fill(Color.white))
                        }
                        
                        Image(systemName: "calendar.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(Color(hex: "#1D3557"))
                            .background(Circle().fill(Color.white))
                            .offset(y: 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                // Calendar section title
                HStack {
                    Spacer()
                    Text(dateHeaderText)
                        .font(.system(size: 32, weight: .black, design: .default))
                        .foregroundColor(Color(hex: "#90B9DCCC"))
                        .multilineTextAlignment(.center)
                        .padding(.top, -10)
                    Spacer()
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 32)

                // Timeline Container
                ZStack(alignment: .top) {
                    Color(hex: "#1D3557")
                        .cornerRadius(32, corners: [.topLeft, .topRight])
                        .ignoresSafeArea(edges: .bottom)

                    if todaysEvents.isEmpty {
                        Text("No events synced for today.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: "#7AA0C3"))
                            .padding(.top, 40)
                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 0) {
                                Spacer().frame(height: 30)
                                ForEach(timelineEntries) { entry in
                                    switch entry {
                                    case .hour(let date):
                                        CalendarTimelineRow(
                                            time: date.formatted(date: .omitted, time: .shortened),
                                            isMainTime: true
                                        )
                                    case .event(let event):
                                        CalendarTimelineRow(
                                            time: event.startDate.formatted(date: .omitted, time: .shortened),
                                            title: event.title,
                                            subtitle: event.location ?? event.notes,
                                            isMainTime: false
                                        )
                                    }
                                }
                                Spacer().frame(height: 40)
                            }
                        }
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }
}

struct CalendarTimelineRow: View {
    var time: String
    var title: String?
    var subtitle: String?
    var isMainTime: Bool
    var isImportant: Bool = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Left Column: Time
            Text(time)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(isMainTime ? Color(hex: "#E8F3FF") : Color(hex: "#E8F3FF").opacity(0.5))
                .frame(width: 80, alignment: .trailing)
            
            // Timeline Center
            ZStack {
                Rectangle()
                    .fill(Color(hex: "#7AA0C3"))
                    .frame(width: 4)
                
                if title != nil {
                    Circle()
                        .fill(Color(hex: "#3FA9F5"))
                        .frame(width: 10, height: 10)
                }
            }
            .frame(width: 20)
            .padding(.horizontal, 8)
            
            // Right Column: Event Box
            if let title = title {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color(hex: "#3FA9F5"))
                        .frame(width: 12, height: 1) // Connecting line
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 13, weight: isImportant ? .black : .bold))
                            .foregroundColor(Color(hex: "#E8F3FF"))
                        if let subtitle = subtitle {
                            Text(subtitle)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(hex: "#7AA0C3"))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: "#1D3557"))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(hex: "#3FA9F5"), lineWidth: 1)
                    )
                }
                .padding(.trailing, 24)
                .padding(.vertical, 8)
            } else {
                Spacer()
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(minHeight: 60)
    }
}

#Preview {
    NavigationStack {
        CalendarView()
    }
    .modelContainer(for: CalendarEvent.self, inMemory: true)
}
