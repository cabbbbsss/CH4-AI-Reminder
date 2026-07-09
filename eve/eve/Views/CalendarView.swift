import Combine
import SwiftData
import SwiftUI

/// A single row on the timeline: an on-the-hour tick mark, an AI reminder,
/// or the live "now" indicator — merged and sorted by their actual (shown) time.
private enum CalendarTimelineEntry: Identifiable {
  case hour(Date)
  case reminder(CalendarReminder)
  case now(Date)

  var id: String {
    switch self {
    case .hour(let date): return "hour-\(date.timeIntervalSince1970)"
    case .reminder(let reminder): return "reminder-\(reminder.id)"
    case .now: return "now-line"
    }
  }

  var sortDate: Date {
    switch self {
    case .hour(let date): return date
    case .reminder(let reminder): return reminder.reminderDate
    case .now(let date): return date
    }
  }
}

/// A horizontally-paged carousel, forward-only: renders the current page
/// (0) and the next one (1) side by side and slides to the next on a
/// leftward drag, snapping to a full page instead of cross-fading in
/// place. There is no backward page — swiping right is inert, so it can
/// never be mistaken for, or fought over with, the system's edge
/// swipe-to-go-back gesture.
private struct SwipeCarousel<Content: View>: View {
  let content: (Int) -> Content
  let onCommit: () -> Void
  var useSimultaneousGesture: Bool = false

  @State private var dragOffset: CGFloat = 0
  @State private var isAnimating = false

  var body: some View {
    GeometryReader { geo in
      let width = max(geo.size.width, 1)

      let pages = HStack(spacing: 0) {
        content(0).frame(width: width, height: geo.size.height)
        content(1).frame(width: width, height: geo.size.height)
      }
      .offset(x: dragOffset)

      if useSimultaneousGesture {
        pages.simultaneousGesture(dragGesture(width: width))
      } else {
        pages.gesture(dragGesture(width: width))
      }
    }
  }

  private func dragGesture(width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 16)
      .onChanged { value in
        guard !isAnimating else { return }
        guard value.translation.width < 0 else { return }
        guard abs(value.translation.width) > abs(value.translation.height) else { return }
        dragOffset = value.translation.width
      }
      .onEnded { value in
        guard !isAnimating else { return }
        guard value.translation.width < 0,
              abs(value.translation.width) > abs(value.translation.height) else {
          withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
          return
        }
        let threshold = width * 0.22
        if value.translation.width < -threshold {
          commit(width: width)
        } else {
          withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
        }
      }
  }

  private func commit(width: CGFloat) {
    isAnimating = true
    withAnimation(.easeOut(duration: 0.28)) {
      dragOffset = -width
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
      onCommit()
      dragOffset = 0
      isAnimating = false
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
  @State private var isAddingReminder = false
  @State private var currentTime: Date = .now

  @State private var reminderManager: CalendarReminderManager?
  @State private var syncManager: EventKitSyncManager?

  private func dayEvents(_ date: Date) -> [CalendarEvent] {
    events.filter { Calendar.current.isDate($0.startDate, inSameDayAs: date) }
  }

  private func dayReminders(_ date: Date) -> [CalendarReminder] {
    reminders
      .filter { Calendar.current.isDate($0.eventDate, inSameDayAs: date) }
      .sorted { $0.reminderDate < $1.reminderDate }
  }

  private func date(byAddingDays days: Int, to date: Date) -> Date {
    Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
  }

  private var isToday: Bool {
    Calendar.current.isDateInToday(selectedDate)
  }

  private var dateHeaderMainText: String {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE, d MMMM yyyy"
    return formatter.string(from: selectedDate)
  }

  private func timelineEntries(for date: Date, reminders dayReminders: [CalendarReminder]) -> [CalendarTimelineEntry] {
    guard let first = dayReminders.first, let last = dayReminders.last else { return [] }

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

    entries.append(contentsOf: dayReminders.map { .reminder($0) })

    if calendar.isDateInToday(date), currentTime >= startHour, currentTime <= endHour.addingTimeInterval(3600) {
      entries.append(.now(currentTime))
    }

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

            daySwipeArea
              .frame(maxHeight: .infinity)
          }
        }
      }
      .overlay(alignment: .bottomLeading) {
        if !isToday {
          todayButton
        }
      }
      .overlay(alignment: .bottomTrailing) {
        addReminderButton
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
      .sheet(isPresented: $isAddingReminder) {
        CalendarReminderAddSheet(date: selectedDate)
      }
      .onChange(of: selectedDate) { _, newDate in
        displayedWeekStart = Calendar.weekStart(containing: newDate)
      }
      .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
        currentTime = date
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
    SwipeCarousel(
      content: { offset in
        weekRow(for: date(byAddingDays: offset * 7, to: displayedWeekStart))
      },
      onCommit: {
        displayedWeekStart = date(byAddingDays: 7, to: displayedWeekStart)
      }
    )
    .frame(height: 72)
  }

  private func weekRow(for weekStart: Date) -> some View {
    HStack(spacing: 0) {
      ForEach(0..<7, id: \.self) { offset in
        let day = Calendar.current.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
        WeekDayCell(
          date: day,
          isSelected: Calendar.current.isDate(day, inSameDayAs: selectedDate),
          isToday: Calendar.current.isDateInToday(day)
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
  }

  // MARK: - Date header

  private var dateHeader: some View {
    VStack(spacing: 4) {
      Text(dateHeaderMainText)
        .font(.system(size: 26, weight: .black, design: .default))
        .foregroundColor(Color(.textTertiary))
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 24)
  }

  // MARK: - Day content (swipeable)

  private var daySwipeArea: some View {
    SwipeCarousel(
      content: { offset in
        dayContent(for: date(byAddingDays: offset, to: selectedDate))
      },
      onCommit: {
        selectedDate = date(byAddingDays: 1, to: selectedDate)
      },
      useSimultaneousGesture: true
    )
  }

  private func dayContent(for date: Date) -> some View {
    let dayEventsForDate = dayEvents(date)
    let dayRemindersForDate = dayReminders(date)
    let generating = Calendar.current.isDate(date, inSameDayAs: selectedDate) && isGenerating

    return VStack(spacing: 0) {
      if dayEventsForDate.isEmpty {
        Text("No events synced for this day.")
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(Color(.textQuarternary))
          .padding(.top, 20)
        Spacer()
      } else if dayRemindersForDate.isEmpty && generating {
        HStack(spacing: 12) {
          Image(systemName: "sparkles")
            .foregroundColor(Color(.textQuarternary))
          Text("Eve is preparing your reminders…")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(Color(.textQuarternary))
        }
        .padding(.top, 20)
        Spacer()
      } else if dayRemindersForDate.isEmpty {
        Text("Nothing to prepare for this day.")
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(Color(.textQuarternary))
          .padding(.top, 20)
        Spacer()
      } else {
        timelineList(for: date, reminders: dayRemindersForDate)
      }
    }
  }

  // MARK: - Timeline

  private func timelineList(for date: Date, reminders dayReminders: [CalendarReminder]) -> some View {
    List {
      ForEach(timelineEntries(for: date, reminders: dayReminders)) { entry in
        switch entry {
        case .hour(let hourDate):
          CalendarTimelineRow(
            time: hourDate.formatted(date: .omitted, time: .shortened),
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

        case .now(let nowDate):
          CalendarNowLineRow(time: nowDate.formatted(date: .omitted, time: .shortened))
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .allowsHitTesting(false)
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

  // MARK: - Floating buttons

  /// Bottom-left "Today" button, mirroring native Calendar — only shown
  /// once the user has navigated away from today, jumps straight back.
  private var todayButton: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.2)) {
        selectedDate = .now
      }
    } label: {
      Text("Today")
        .font(.system(size: 15, weight: .bold))
        .padding(.horizontal, 6)
        .frame(height: 28)
    }
    .buttonStyle(.glass)
    .buttonBorderShape(.capsule)
    .controlSize(.large)
    .tint(Color(.textPrimary))
    .padding(.leading, 24)
    .padding(.bottom, 24)
    .transition(.opacity.combined(with: .move(edge: .leading)))
  }

  /// Bottom-right "+" button — opens a dedicated sheet to add a reminder
  /// by hand for the day currently on screen.
  private var addReminderButton: some View {
    Button {
      isAddingReminder = true
    } label: {
      Image(systemName: "plus")
        .font(.system(size: 20, weight: .semibold))
        .frame(width: 24, height: 24)
    }
    .buttonStyle(.glassProminent)
    .buttonBorderShape(.circle)
    .controlSize(.large)
    .tint(Color.accentColor)
    .padding(.trailing, 24)
    .padding(.bottom, 24)
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
    var isToday: Bool

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

    /// Selected takes priority (shown via the filled circle); otherwise
    /// today is called out in red — the same red used by the live "now"
    /// line on the timeline — since the accent tint read too close to the
    /// default text color to register as a distinct state.
    private var numberColor: Color {
      if isSelected { return Color(.textPrimary) }
      if isToday { return .red }
      return Color(.textTertiary)
    }

    var body: some View {
      VStack(spacing: 10) {
        Text(dayLetter)
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(Color(.textTertiary).opacity(0.5))

        Text(dayNumber)
          .font(.system(size: 20, weight: .bold))
          .foregroundColor(numberColor)
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
            // Connecting line — ties this card to its exact dot/time on the
            // spine so its time is never ambiguous, capped with a small
            // node right at the card's edge.
            HStack(spacing: 0) {
              Rectangle()
                .fill(Color.accentColor)
                .frame(width: 20, height: 2)
              Circle()
                .fill(Color.accentColor)
                .frame(width: 5, height: 5)
            }

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
                .stroke(Color.accentColor, lineWidth: 1.5)
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

  /// The live "current time" indicator, mirroring the red now-line in
  /// Apple's Calendar app. Aligned to the same time/center columns as
  /// `CalendarTimelineRow` so it reads as a line running through the day.
  private struct CalendarNowLineRow: View {
    var time: String

    var body: some View {
      HStack(alignment: .center, spacing: 0) {
        Text(time)
          .font(.system(size: 12, weight: .bold))
          .foregroundColor(.red)
          .frame(width: 80, alignment: .trailing)

        ZStack {
          Circle()
            .fill(Color.red)
            .frame(width: 8, height: 8)
        }
        .frame(width: 20)
        .padding(.horizontal, 8)

        Rectangle()
          .fill(Color.red)
          .frame(height: 1.5)
          .padding(.trailing, 24)
      }
      .frame(minHeight: 20)
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
