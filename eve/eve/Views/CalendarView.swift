import SwiftData
import SwiftUI

/// A single row on the timeline: either an on-the-hour tick mark
/// or an AI reminder, merged and sorted by their actual (shown) time.
private enum CalendarTimelineEntry: Identifiable {
  case hour(Date)
  case reminder(CalendarReminder)

  var id: String {
    switch self {
    case .hour(let date): return "hour-\(date.timeIntervalSince1970)"
    case .reminder(let reminder): return "reminder-\(reminder.id)"
    }
  }

  var sortDate: Date {
    switch self {
    case .hour(let date): return date
    case .reminder(let reminder): return reminder.reminderDate
    }
  }
}

struct CalendarView: View {
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \CalendarEvent.startDate) private var events: [CalendarEvent]
  @Query(sort: \CalendarReminder.eventDate) private var reminders: [CalendarReminder]

  @State private var selectedDate: Date = .now
  @State private var displayedWeekStart: Date = Calendar.weekStart(containing: .now)
  @State private var isShowingCalendar = false
  @State private var isReloading = false
  @State private var isGenerating = false
  @State private var editingReminder: CalendarReminder?

  @State private var reminderManager: CalendarReminderManager?
  @State private var syncManager: EventKitSyncManager?

  private var todaysEvents: [CalendarEvent] {
    events.filter { Calendar.current.isDate($0.startDate, inSameDayAs: selectedDate) }
  }

  private var todaysReminders: [CalendarReminder] {
    reminders
      .filter { Calendar.current.isDate($0.eventDate, inSameDayAs: selectedDate) }
      .sorted { $0.reminderDate < $1.reminderDate }
  }

  private var isToday: Bool {
    Calendar.current.isDateInToday(selectedDate)
  }

  private var dateHeaderMainText: String {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE, d MMMM yyyy"
    return formatter.string(from: selectedDate)
  }

  private var timelineEntries: [CalendarTimelineEntry] {
    guard let first = todaysReminders.first, let last = todaysReminders.last else { return [] }

    let calendar = Calendar.current

    let startHour = calendar.date(
      bySettingHour: calendar.component(.hour, from: first.reminderDate),
      minute: 0, second: 0, of: first.reminderDate
    ) ?? first.reminderDate

    let endHour = calendar.date(
      bySettingHour: calendar.component(.hour, from: last.reminderDate),
      minute: 0, second: 0, of: last.reminderDate
    ) ?? last.reminderDate

    var entries: [CalendarTimelineEntry] = []
    var cursor = startHour

    while cursor <= endHour {
      entries.append(.hour(cursor))
      cursor = calendar.date(byAdding: .hour, value: 1, to: cursor) ?? endHour.addingTimeInterval(3600)
    }

    entries.append(contentsOf: todaysReminders.map { .reminder($0) })

    return entries.sorted { $0.sortDate < $1.sortDate }
   }

  var body: some View {
    ZStack {
      Color(.bgPrimary).ignoresSafeArea()

      GeometryReader { proxy in
        Ellipse()
          .fill(Color(.bgSecondary))
          .frame(width: proxy.size.width * 2.5, height: proxy.size.height * 1.2)
          .position(x: proxy.size.width / 2, y: -proxy.size.height * 0.1)
      }
      .ignoresSafeArea()

      VStack(spacing: 0) {
        // Timeline Container
        ZStack(alignment: .top) {
          Color(.textPrimary)
            .cornerRadius(32, corners: [.topLeft, .topRight])
            .ignoresSafeArea(edges: .bottom)

          VStack(spacing: 0) {
            weekStrip
              .padding(.top, 20)
              .padding(.bottom, 12)

            dateHeader
              .padding(.bottom, 20)

            if todaysEvents.isEmpty {
              Text("No events synced for this day.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(.textQuarternary))
                .padding(.top, 20)
              Spacer()
            } else if todaysReminders.isEmpty && isGenerating {
              HStack(spacing: 12) {
                Image(systemName: "sparkles")
                  .foregroundColor(Color(.textQuarternary))
                Text("Eve is preparing your reminders…")
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundColor(Color(.textQuarternary))
              }
              .padding(.top, 20)
              Spacer()
            } else if todaysReminders.isEmpty {
              Text("Nothing to prepare for this day.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(.textQuarternary))
                .padding(.top, 20)
              Spacer()
            } else {
              timelineList
            }
          }
        }
      }
      .navigationTitle("Calendar")
      .navigationBarTitleDisplayMode(.large)
      .toolbarBackground(.hidden, for: .navigationBar)
      .tint(Color(.textPrimary))
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            isShowingCalendar = true
          } label: {
            Image(systemName: "calendar")
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Task { await reload() }
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .disabled(isReloading)
        }
      }
      .sheet(isPresented: $isShowingCalendar) {
        NavigationStack {
          DatePicker("Select Date", selection: $selectedDate, displayedComponents: [.date])
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle("Select Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
              ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                  isShowingCalendar = false
                }
              }
            }
        }
        .presentationDetents([.medium, .large])
      }
      .sheet(item: $editingReminder) { reminder in
        CalendarReminderEditSheet(reminder: reminder, manager: reminderManager)
      }
      .onChange(of: selectedDate) { _, newDate in
        displayedWeekStart = Calendar.weekStart(containing: newDate)
      }
      .task {
        if reminderManager == nil {
          reminderManager = CalendarReminderManager(context: modelContext)
        }
        if syncManager == nil {
          syncManager = EventKitSyncManager(context: modelContext)
          await syncManager?.start()
        }
      }
      .task(id: selectedDate) {
        if reminderManager == nil {
          reminderManager = CalendarReminderManager(context: modelContext)
        }
        isGenerating = true
        await reminderManager?.ensureReminders(for: selectedDate)
        isGenerating = false
      }
    }
  }

  // MARK: - Week strip

  private var weekStrip: some View {
    HStack(spacing: 0) {
      ForEach(0..<7, id: \.self) { offset in
        let day = Calendar.current.date(byAdding: .day, value: offset, to: displayedWeekStart) ?? displayedWeekStart
        WeekDayCell(
          date: day,
          isSelected: Calendar.current.isDate(day, inSameDayAs: selectedDate)
        )
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
          withAnimation(.easeInOut(duration: 0.2)) {
            selectedDate = day
          }
        }
      }
    }
    .padding(.horizontal, 24)
    .gesture(
      DragGesture(minimumDistance: 20)
        .onEnded { value in
          let calendar = Calendar.current
          if value.translation.width < -50 {
            withAnimation(.easeInOut(duration: 0.2)) {
              displayedWeekStart = calendar.date(byAdding: .day, value: 7, to: displayedWeekStart) ?? displayedWeekStart
            }
          } else if value.translation.width > 50 {
            withAnimation(.easeInOut(duration: 0.2)) {
              displayedWeekStart = calendar.date(byAdding: .day, value: -7, to: displayedWeekStart) ?? displayedWeekStart
            }
          }
        }
    )
  }

  // MARK: - Date header

  private var dateHeader: some View {
    VStack(spacing: 4) {
      if isToday {
        Text("Today")
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(Color(.textTertiary).opacity(0.5))
      }
      Text(dateHeaderMainText)
        .font(.system(size: 26, weight: .black, design: .default))
        .foregroundColor(Color(.textTertiary))
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 24)
  }

  // MARK: - Timeline

  private var timelineList: some View {
    List {
      ForEach(timelineEntries) { entry in
        switch entry {
        case .hour(let date):
          CalendarTimelineRow(
            time: date.formatted(date: .omitted, time: .shortened),
            isMainTime: true
          )
          .listRowInsets(EdgeInsets())
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)

        case .reminder(let reminder):
          CalendarTimelineRow(
            time: reminder.reminderDate.formatted(date: .omitted, time: .shortened),
            title: reminder.text,
            subtitle: "For \(reminder.eventTitle) at \(reminder.eventDate.formatted(date: .omitted, time: .shortened))",
            isMainTime: false
          )
          .listRowInsets(EdgeInsets())
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)
          .contentShape(Rectangle())
          .onTapGesture { editingReminder = reminder }
          .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
              reminderManager?.remove(reminder)
            } label: {
              Image(systemName: "trash")
            }
            .tint(.red)
          }
        }
      }

      Color.clear
        .frame(height: 40)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .scrollIndicators(.hidden)
    .background(Color.clear)
  }

  // MARK: - Actions

  private func reload() async {
    isReloading = true
    await syncManager?.syncNow()
    isGenerating = true
    await reminderManager?.regenerate(for: selectedDate)
    isGenerating = false
    isReloading = false
  }

  // MARK: - Row views

  private struct WeekDayCell: View {
    var date: Date
    var isSelected: Bool

    private var dayLetter: String {
      let formatter = DateFormatter()
      formatter.dateFormat = "EEEEE"
      return formatter.string(from: date)
    }

    private var dayNumber: String {
      let formatter = DateFormatter()
      formatter.dateFormat = "d"
      return formatter.string(from: date)
    }

    var body: some View {
      VStack(spacing: 10) {
        Text(dayLetter)
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(Color(.textTertiary).opacity(0.5))

        Text(dayNumber)
          .font(.system(size: 20, weight: .bold))
          .foregroundColor(isSelected ? Color(.textPrimary) : Color(.textTertiary))
          .frame(width: 36, height: 36)
          .background(
            Circle().fill(isSelected ? Color(.textTertiary) : Color.clear)
          )
      }
    }
  }

  private struct CalendarTimelineRow: View {
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
          .foregroundColor(isMainTime ? Color(.textSecondary) : Color(.textSecondary).opacity(0.5))
          .frame(width: 80, alignment: .trailing)

        // Timeline Center
        ZStack {
          Rectangle()
            .fill(Color(.textQuarternary))
            .frame(width: 4)

          if title != nil {
            Circle()
              .fill(Color.accentColor)
              .frame(width: 10, height: 10)
          }
        }
        .frame(width: 20)
        .padding(.horizontal, 8)

        // Right Column: Event Box
        if let title = title {
          HStack(spacing: 0) {
            Rectangle()
              .fill(Color.accentColor)
              .frame(width: 12, height: 1) // Connecting line

            VStack(alignment: .leading, spacing: 4) {
              Text(title)
                .font(.system(size: 13, weight: isImportant ? .black : .bold))
                .foregroundColor(Color(.textSecondary))
              if let subtitle = subtitle {
                Text(subtitle)
                  .font(.system(size: 10, weight: .bold))
                  .foregroundColor(Color(.textQuarternary))
              }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.textPrimary))
            .cornerRadius(8)
            .overlay(
              RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor, lineWidth: 1)
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
}

private extension Calendar {
  /// Sunday-anchored start of the week containing `date`, using a fixed
  /// Sunday-first calendar regardless of device locale — the week strip's
  /// layout (S M T W T F S) should stay consistent for every user.
  static func weekStart(containing date: Date) -> Date {
    var calendar = Calendar.current
    calendar.firstWeekday = 1
    let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
    return calendar.date(from: components) ?? date
  }
}

#Preview {
  NavigationStack {
    CalendarView()
  }
  .modelContainer(for: CalendarEvent.self, inMemory: true)
}
