import Combine
import SwiftData
import SwiftUI
import UIKit

/// All of one event's AI-generated prep reminders share an `occurrenceID`,
/// `eventTitle`, and `eventDate` (and so the same `reminderDate` — it's
/// derived from `eventDate`) — they're one notification's worth of prep
/// items, not separate events, so the timeline shows them as one card.
private struct CalendarReminderGroup: Identifiable {
  var occurrenceID: String
  var eventTitle: String
  var eventDate: Date
  var reminderDate: Date
  var reminders: [CalendarReminder]

  var id: String { occurrenceID }
}

/// A single row on the timeline: an on-the-hour tick mark, a group of
/// reminders for one event occurrence, or the live "now" indicator —
/// merged and sorted by their actual (shown) time.
private enum CalendarTimelineEntry: Identifiable {
  case hour(Date)
  case reminderGroup(CalendarReminderGroup)
  case now(Date)

  var id: String {
    switch self {
    case .hour(let date): return "hour-\(date.timeIntervalSince1970)"
    case .reminderGroup(let group): return "group-\(group.id)"
    case .now: return "now-line"
    }
  }

  var sortDate: Date {
    switch self {
    case .hour(let date): return date
    case .reminderGroup(let group): return group.reminderDate
    case .now(let date): return date
    }
  }
}

/// A horizontally-paged carousel: renders the previous/current/next page
/// (offsets -1, 0, 1) side by side and slides between them on drag,
/// snapping to a full page instead of cross-fading in place. Both
/// directions are live — the system's edge swipe-to-go-back gesture is
/// disabled separately (see `PopGestureGuard`) so a rightward swipe here
/// can never be mistaken for backing out of Calendar.
private struct SwipeCarousel<Content: View>: View {
  let content: (Int) -> Content
  let onCommit: (Int) -> Void
  var useSimultaneousGesture: Bool = false

  @State private var dragOffset: CGFloat = 0
  @State private var isAnimating = false

  var body: some View {
    GeometryReader { geo in
      let width = max(geo.size.width, 1)

      let pages = HStack(spacing: 0) {
        content(-1).frame(width: width, height: geo.size.height)
        content(0).frame(width: width, height: geo.size.height)
        content(1).frame(width: width, height: geo.size.height)
      }
      .offset(x: -width + dragOffset)

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
        guard abs(value.translation.width) > abs(value.translation.height) else { return }
        dragOffset = value.translation.width
      }
      .onEnded { value in
        guard !isAnimating else { return }
        guard abs(value.translation.width) > abs(value.translation.height) else {
          withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
          return
        }
        let threshold = width * 0.22
        if value.translation.width < -threshold {
          commit(direction: 1, width: width)
        } else if value.translation.width > threshold {
          commit(direction: -1, width: width)
        } else {
          withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
        }
      }
  }

  private func commit(direction: Int, width: CGFloat) {
    isAnimating = true
    withAnimation(.easeOut(duration: 0.28)) {
      dragOffset = CGFloat(-direction) * width
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
      onCommit(direction)
      dragOffset = 0
      isAnimating = false
    }
  }
}

/// Suppresses the navigation controller's interactive swipe-to-go-back
/// gesture while Calendar is on screen, restoring it on the way out.
/// Calendar has its own full-width bidirectional swipe for day/week
/// paging; without this, a swipe that merely starts near the left edge is
/// sometimes claimed by the screen-edge pop gesture instead — popping back
/// to Home when the user only meant to page to the previous day.
///
/// Mirrors what Apple's own Calendar does on its day view: no swipe ever
/// navigates back to the month — horizontal swipes page days, and the only
/// way back is the "< July" button.
///
/// Earlier, narrower attempts still let swipes through. Why each part of
/// this version matters:
///  - iOS 26 split swipe-back into TWO gesture recognizers: the classic
///    edge pan (`interactivePopGestureRecognizer`) and a full-content-area
///    pan (`interactiveContentPopGestureRecognizer`) that triggers a pop
///    from a rightward swipe anywhere on screen. Both must be suppressed;
///    disabling only the edge one is why right-swipes kept "sometimes"
///    popping to Home.
///  - Sweeps *every* `UINavigationController` reachable from all window
///    scenes, not just `self.navigationController` — SwiftUI may host our
///    content outside the nav controller's view-controller subtree, so
///    resolving a single `navigationController` could land on nil / the
///    wrong one, silently disabling nothing.
///  - Sets `isEnabled = false` AND installs itself as each recognizer's
///    delegate, returning false from `gestureRecognizerShouldBegin`.
///    `NavigationStack` may flip `isEnabled` back on during its own layout
///    passes, so the delegate refusal is the layer that holds.
///  - Driven from the SwiftUI view's `onAppear`/`onDisappear` (plus a
///    one-runloop retry and periodic re-asserts), rather than a hosted
///    helper view controller whose lifecycle timing proved unreliable.
private final class PopGestureGuard: NSObject, UIGestureRecognizerDelegate {

  /// One recognizer's original state, so it can be restored faithfully
  /// even if several nav controllers were swept.
  private final class Capture {
    weak var gesture: UIGestureRecognizer?
    let wasEnabled: Bool
    weak var previousDelegate: UIGestureRecognizerDelegate?
    init(_ gesture: UIGestureRecognizer) {
      self.gesture = gesture
      self.wasEnabled = gesture.isEnabled
      self.previousDelegate = gesture.delegate
    }
  }

  private var captures: [Capture] = []
  private var capturedIDs = Set<ObjectIdentifier>()

  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    false
  }

  func disable() {
    for gesture in Self.popRecognizers() {
      // Capture each recognizer's original state exactly once, before we
      // touch it, so a repeated disable() never records our own values.
      if capturedIDs.insert(ObjectIdentifier(gesture)).inserted {
        captures.append(Capture(gesture))
      }
      gesture.isEnabled = false
      gesture.delegate = self
    }
  }

  func restore() {
    for capture in captures {
      guard let gesture = capture.gesture else { continue }
      gesture.isEnabled = capture.wasEnabled
      gesture.delegate = capture.previousDelegate
    }
    captures.removeAll()
    capturedIDs.removeAll()
  }

  /// Every navigation controller's pop recognizer anywhere in the app's
  /// window hierarchy, de-duplicated.
  private static func popRecognizers() -> [UIGestureRecognizer] {
    var navigationControllers: [UINavigationController] = []
    var seen = Set<ObjectIdentifier>()

    func walk(_ viewController: UIViewController?) {
      guard let viewController else { return }
      if let nav = viewController as? UINavigationController,
         seen.insert(ObjectIdentifier(nav)).inserted {
        navigationControllers.append(nav)
      }
      viewController.children.forEach(walk)
      walk(viewController.presentedViewController)
    }

    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows {
        walk(window.rootViewController)
      }
    }

    // iOS 26 split swipe-back into TWO recognizers: the classic edge pan
    // (`interactivePopGestureRecognizer`) plus a new full-content-area pan
    // (`interactiveContentPopGestureRecognizer`) that recognizes a
    // rightward swipe ANYWHERE on screen. Suppressing only the edge one —
    // all this guard did before — leaves every mid-screen right-swipe free
    // to pop; that was exactly the intermittent escape-to-Home. Grab both.
    return navigationControllers.flatMap { nav in
      [nav.interactivePopGestureRecognizer, nav.interactiveContentPopGestureRecognizer]
        .compactMap { $0 }
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

  /// Kills the swipe-to-go-back gesture while Calendar owns the screen, so
  /// paging the date can't be misread as backing out. See `PopGestureGuard`.
  @State private var popGuard = PopGestureGuard()

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

  /// Bundles same-occurrence reminders into one card, ordered by creation
  /// so bullets stay in the order they were generated, then by reminderDate
  /// so the groups themselves are chronological.
  private func reminderGroups(from dayReminders: [CalendarReminder]) -> [CalendarReminderGroup] {
    Dictionary(grouping: dayReminders, by: \.occurrenceID)
      .compactMap { occurrenceID, items -> CalendarReminderGroup? in
        guard let first = items.first else { return nil }
        return CalendarReminderGroup(
          occurrenceID: occurrenceID,
          eventTitle: first.eventTitle,
          eventDate: first.eventDate,
          reminderDate: first.reminderDate,
          reminders: items.sorted { $0.createdAt < $1.createdAt }
        )
      }
      .sorted { $0.reminderDate < $1.reminderDate }
  }

  private func timelineEntries(for date: Date, reminders dayReminders: [CalendarReminder]) -> [CalendarTimelineEntry] {
    let groups = reminderGroups(from: dayReminders)
    guard let first = groups.first, let last = groups.last else { return [] }

    let calendar = Calendar.current

    let startHour = calendar.date(
      bySettingHour: calendar.component(.hour, from: first.reminderDate),
      minute: 0, second: 0, of: first.reminderDate
    ) ?? first.reminderDate

    let endHour = calendar.date(
      bySettingHour: calendar.component(.hour, from: last.reminderDate),
      minute: 0, second: 0, of: last.reminderDate
    ) ?? last.reminderDate

    // A group already shows its own time next to its card — an hour tick
    // for that same hour would just repeat the number right next to it,
    // and reads worse the taller a multi-reminder card gets. Skip it.
    let occupiedHours = Set(groups.map { calendar.component(.hour, from: $0.reminderDate) })

    var entries: [CalendarTimelineEntry] = []
    var cursor = startHour

    while cursor <= endHour {
      if !occupiedHours.contains(calendar.component(.hour, from: cursor)) {
        entries.append(.hour(cursor))
      }
      cursor = calendar.date(byAdding: .hour, value: 1, to: cursor) ?? endHour.addingTimeInterval(3600)
    }

    entries.append(contentsOf: groups.map { .reminderGroup($0) })

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
        // NavigationStack can reassert gesture state during its own
        // updates — re-suppress after every page so the guard never lapses.
        popGuard.disable()
      }
      .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
        currentTime = date
        popGuard.disable()
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
      .onAppear {
        popGuard.disable()
        // The nav hierarchy may not be fully wired on the first tick of a
        // push; re-apply next runloop so we don't miss the recognizer.
        DispatchQueue.main.async { popGuard.disable() }
      }
      .onDisappear {
        popGuard.restore()
      }
    }
  }

  // MARK: - Week strip

  private var weekStrip: some View {
    SwipeCarousel(
      content: { offset in
        weekRow(for: date(byAddingDays: offset * 7, to: displayedWeekStart))
      },
      onCommit: { direction in
        displayedWeekStart = date(byAddingDays: direction * 7, to: displayedWeekStart)
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
      onCommit: { direction in
        selectedDate = date(byAddingDays: direction, to: selectedDate)
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
          CalendarTimelineRow(time: hourDate.formatted(date: .omitted, time: .shortened))
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

        case .reminderGroup(let group):
          CalendarReminderGroupRow(
            time: group.reminderDate.formatted(date: .omitted, time: .shortened),
            subtitle: "For \(group.eventTitle) at \(group.eventDate.formatted(date: .omitted, time: .shortened))",
            reminders: group.reminders,
            onSelect: { reminder in editingReminder = reminder }
          )
          .listRowInsets(EdgeInsets())
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)

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

    /// Today is always called out in red — the same red used by the live
    /// "now" line on the timeline — whether or not it's also selected, so
    /// selecting today doesn't lose that distinction.
    private var circleFillColor: Color {
      guard isSelected else { return .clear }
      return isToday ? .red : Color(.textTertiary)
    }

    private var numberColor: Color {
      if isSelected { return isToday ? .white : Color(.textPrimary) }
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
            Circle().fill(circleFillColor)
          )
      }
    }
  }

  /// An on-the-hour tick: just the time and a spine segment. Suppressed
  /// entirely for any hour a reminder group already occupies (see
  /// `timelineEntries`), so it never duplicates a card's own time label.
  private struct CalendarTimelineRow: View {
    var time: String

    var body: some View {
      HStack(alignment: .center, spacing: 0) {
        // Dimmer than a reminder's own time label — this row is just a
        // bare hour marker, nothing is actually scheduled on it.
        Text(time)
          .font(.system(size: 15, weight: .bold))
          .foregroundColor(Color(.textSecondary).opacity(0.5))
          .frame(width: 80, alignment: .trailing)

        ZStack {
          Rectangle()
            .fill(Color(.textQuarternary))
            .frame(width: 4)
        }
        .frame(width: 20)
        .padding(.horizontal, 8)

        Spacer()
          .frame(maxWidth: .infinity)
      }
      .frame(minHeight: 60)
    }
  }

  /// One card per event occurrence: every reminder generated for that
  /// event (a single notification's worth of prep items) is listed inside
  /// it as its own tappable row, rather than each getting a separate card
  /// with a repeated time label.
  private struct CalendarReminderGroupRow: View {
    var time: String
    var subtitle: String
    var reminders: [CalendarReminder]
    var onSelect: (CalendarReminder) -> Void

    var body: some View {
      HStack(alignment: .top, spacing: 0) {
        // Left Column: Time — brighter than a bare hour tick, since this
        // row actually has something scheduled on it.
        Text(time)
          .font(.system(size: 15, weight: .bold))
          .foregroundColor(Color(.textSecondary))
          .frame(width: 80, alignment: .trailing)
          .padding(.top, 12)

        // Timeline Center
        ZStack {
          Rectangle()
            .fill(Color(.textQuarternary))
            .frame(width: 4)
          Circle()
            .fill(Color.accentColor)
            .frame(width: 10, height: 10)
        }
        .frame(width: 20)
        .padding(.horizontal, 8)
        .padding(.top, 12)

        // Right Column: Card. The connector to the spine is a stripe
        // fused to the card's own leading edge, not a separately
        // positioned floating shape — it's part of the card's body, so
        // it can never misalign or fail to render independently of it.
        VStack(alignment: .leading, spacing: 8) {
          Text(subtitle)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(Color(.textQuarternary))

          VStack(alignment: .leading, spacing: 8) {
            ForEach(reminders) { reminder in
              HStack(alignment: .top, spacing: 8) {
                Circle()
                  .fill(Color.accentColor)
                  .frame(width: 5, height: 5)
                  .padding(.top, 5)
                Text(reminder.text)
                  .font(.system(size: 13, weight: .bold))
                  .foregroundColor(Color(.textPrimary))
                  .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
              }
              .contentShape(Rectangle())
              .onTapGesture { onSelect(reminder) }
            }
          }
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A card fill matching the surrounding panel would make the
        // border pointless — bgSecondary is the panel's inverse in
        // both light and dark mode, so the card always visibly pops.
        .background(Color(.bgSecondary))
        .cornerRadius(8)
        .overlay(alignment: .leading) {
          Capsule()
            .fill(Color.accentColor)
            .frame(width: 5)
            .padding(.vertical, 8)
        }
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color.accentColor, lineWidth: 1.5)
        )
        .padding(.trailing, 24)
        .padding(.vertical, 8)
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
