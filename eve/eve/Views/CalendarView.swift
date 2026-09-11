import Combine
import SwiftData
import SwiftUI

private struct CalendarReminderGroup: Identifiable {
    let occurrenceID: String
    let reminderDate: Date
    let reminders: [CalendarReminder]
    var id: String { "\(occurrenceID)-\(reminderDate.timeIntervalSince1970)" }
}

private struct DayCanvasItem: Identifiable {
    enum Kind { case event(CalendarEvent), reminder(CalendarReminderGroup) }
    let id: String
    let startMinute: Int
    let endMinute: Int
    let kind: Kind
}

private struct CalendarSwipePager<Content: View>: View {
    let content: (Int) -> Content
    let onCommit: (Int) -> Void
    @State private var dragOffset: CGFloat = 0
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            HStack(spacing: 0) {
                content(-1).frame(width: width, height: proxy.size.height)
                content(0).frame(width: width, height: proxy.size.height)
                content(1).frame(width: width, height: proxy.size.height)
            }
            .offset(x: -width + dragOffset)
            .simultaneousGesture(dragGesture(width: width))
        }
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard !isAnimating, abs(value.translation.width) > abs(value.translation.height) else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                guard !isAnimating else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    withAnimation(.easeOut(duration: 0.18)) { dragOffset = 0 }
                    return
                }
                let direction: Int?
                if value.translation.width < -(width * 0.22) { direction = 1 }
                else if value.translation.width > width * 0.22 { direction = -1 }
                else { direction = nil }
                guard let direction else {
                    withAnimation(.easeOut(duration: 0.18)) { dragOffset = 0 }
                    return
                }
                isAnimating = true
                withAnimation(.easeInOut(duration: 0.25)) { dragOffset = CGFloat(-direction) * width }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    onCommit(direction)
                    dragOffset = 0
                    isAnimating = false
                }
            }
    }
}

struct CalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \CalendarEvent.startDate) private var events: [CalendarEvent]
    @Query(sort: \CalendarReminder.eventDate) private var reminders: [CalendarReminder]

    @State private var selectedDate: Date = .now
    @State private var displayedWeekStart: Date = Calendar.weekStart(containing: .now)
    @State private var isShowingDatePicker = false
    @State private var isGenerating = false
    @State private var editingReminder: CalendarReminder?
    @State private var selectedEvent: CalendarEvent?
    @State private var isAddingReminder = false
    @State private var currentTime: Date = .now
    @State private var reminderManager: CalendarReminderManager?
    @State private var syncManager: EventKitSyncManager?

    private var palette: CalendarPalette { CalendarPalette(colorScheme: colorScheme) }
    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                calendarHeader
                    .padding(.top, Theme.Spacing.l)
                    .padding(.horizontal, Theme.Spacing.gutter)

                calendarCard
                .padding(.top, 18)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isShowingDatePicker) {
            NavigationStack {
                DatePicker("Select Date", selection: $selectedDate, displayedComponents: [.date])
                    .datePickerStyle(.graphical).padding()
                    .navigationTitle("Select Date").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { isShowingDatePicker = false } } }
            }.presentationDetents([.medium, .large])
        }
        .sheet(item: $editingReminder) { CalendarReminderEditSheet(reminder: $0, manager: reminderManager) }
        .sheet(item: $selectedEvent) { CalendarEventDetailSheet(event: $0) }
        .sheet(isPresented: $isAddingReminder) { CalendarReminderAddSheet(date: selectedDate) }
        .onChange(of: selectedDate) { _, date in displayedWeekStart = Calendar.weekStart(containing: date) }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { currentTime = $0 }
        .task {
            if reminderManager == nil { reminderManager = CalendarReminderManager(context: modelContext) }
            if syncManager == nil {
                syncManager = EventKitSyncManager(context: modelContext)
                await syncManager?.start()
            }
        }
        .task(id: selectedDate) {
            if reminderManager == nil { reminderManager = CalendarReminderManager(context: modelContext) }
            isGenerating = true
            await reminderManager?.ensureReminders(for: selectedDate)
            isGenerating = false
        }
    }

    /// Kept outside `ToolbarItem` so iOS cannot wrap the button in the
    /// navigation bar's wide automatic Liquid Glass capsule. The button uses
    /// the exact same view structure and modifiers as Home's Settings button.
    private var calendarHeader: some View {
        ZStack {
            Text("Calendar")
                .font(.headline.weight(.semibold))
                .foregroundStyle(palette.primaryText)

            HStack {
                Spacer()

                Button { isAddingReminder = true } label: {
                    Image(systemName: "plus")
                        .font(.title3)
                        .foregroundStyle(Color.eveOnSurface)
                        .padding(Theme.Spacing.xs)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Add reminder")
            }
        }
    }

    private var calendarCard: some View {
        VStack(spacing: 0) {
            monthButton
                .padding(.top, 18)
                .padding(.bottom, 12)

            weekStrip
                .padding(.vertical, 7)
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .padding(.horizontal, 0)
                .padding(.bottom, 10)

            if isGenerating {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Preparing EVE reminders…")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(palette.secondaryText)
                .padding(.bottom, 8)
                .accessibilityElement(children: .combine)
            }

            dayPager
        }
        .background(palette.canvas.opacity(colorScheme == .dark ? 0.96 : 0.88))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(colorScheme == .dark ? 0.08 : 0.28), lineWidth: 0.8)
        }
    }

    private var monthButton: some View {
        Button { isShowingDatePicker = true } label: {
            HStack(spacing: 6) {
                Text(selectedDate.formatted(.dateTime.month(.wide)))
                Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.bold))
            }
            .font(.title2.weight(.bold)).foregroundStyle(palette.primaryText)
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(selectedDate.formatted(.dateTime.month(.wide))) calendar")
        .accessibilityHint("Opens date picker")
    }

    private var weekStrip: some View {
        CalendarSwipePager(
            content: { offset in weekRow(for: date(byAddingDays: offset * 7, to: displayedWeekStart)) },
            onCommit: { direction in displayedWeekStart = date(byAddingDays: direction * 7, to: displayedWeekStart) }
        ).frame(height: 66)
    }

    private var dayPager: some View {
        CalendarSwipePager(
            content: { offset in
                let date = date(byAddingDays: offset, to: selectedDate)
                return DayTimeline(
                    date: date, events: events, reminders: reminders, currentTime: currentTime,
                    palette: palette,
                    onEventTap: { selectedEvent = $0 },
                    onReminderTap: { editingReminder = $0 },
                    onToggleReminder: { reminderManager?.toggleCompletion(for: $0) }
                )
            },
            onCommit: { direction in
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedDate = date(byAddingDays: direction, to: selectedDate)
                }
            }
        )
    }

    private func weekRow(for weekStart: Date) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { offset in
                let date = date(byAddingDays: offset, to: weekStart)
                Button { withAnimation(.easeInOut(duration: 0.2)) { selectedDate = date } } label: {
                    VStack(spacing: 5) {
                        Text(date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(.medium)).foregroundStyle(palette.secondaryText)
                        Text(date.formatted(.dateTime.day()))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Calendar.current.isDate(date, inSameDayAs: selectedDate) ? .white : palette.primaryText)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Calendar.current.isDate(date, inSameDayAs: selectedDate) ? palette.accent : .clear))
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                .accessibilityAddTraits(Calendar.current.isDate(date, inSameDayAs: selectedDate) ? .isSelected : [])
            }
        }.padding(.horizontal, 22)
    }

    private func date(byAddingDays days: Int, to date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }

}

private struct DayTimeline: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let date: Date
    let events: [CalendarEvent]
    let reminders: [CalendarReminder]
    let currentTime: Date
    let palette: CalendarPalette
    let onEventTap: (CalendarEvent) -> Void
    let onReminderTap: (CalendarReminder) -> Void
    let onToggleReminder: (CalendarReminder) -> Void
    @State private var didInitialScroll = false

    private var hourHeight: CGFloat { dynamicTypeSize.isAccessibilitySize ? 72 : 56 }
    private let timeGutter: CGFloat = 58
    private var dayStart: Date { Calendar.current.startOfDay(for: date) }
    private var dayEnd: Date { Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400) }
    private var allDayEvents: [CalendarEvent] { events.filter { $0.isAllDay && $0.startDate < dayEnd && $0.endDate > dayStart } }
    private var timedEvents: [CalendarEvent] { events.filter { !$0.isAllDay && $0.startDate < dayEnd && $0.endDate > dayStart } }

    private var reminderGroups: [CalendarReminderGroup] {
        let dayReminders = reminders.filter { Calendar.current.isDate($0.reminderDate, inSameDayAs: date) }
        return Dictionary(grouping: dayReminders) { "\($0.occurrenceID)-\($0.reminderDate.timeIntervalSince1970)" }
            .compactMap { _, values in
                guard let first = values.first else { return nil }
                return CalendarReminderGroup(occurrenceID: first.occurrenceID, reminderDate: first.reminderDate, reminders: values.sorted { $0.createdAt < $1.createdAt })
            }.sorted { $0.reminderDate < $1.reminderDate }
    }

    private var canvasItems: [DayCanvasItem] {
        let eventItems = timedEvents.map { event -> DayCanvasItem in
            let start = minuteOffset(for: max(event.startDate, dayStart))
            let end = max(minuteOffset(for: min(event.endDate, dayEnd)), start + 24)
            return DayCanvasItem(id: "event-\(event.occurrenceID)", startMinute: start, endMinute: end, kind: .event(event))
        }
        let reminderItems = reminderGroups.map { group -> DayCanvasItem in
            let start = minuteOffset(for: group.reminderDate)
            return DayCanvasItem(id: "reminder-\(group.id)", startMinute: start, endMinute: min(1_440, start + max(30, group.reminders.count * 30)), kind: .reminder(group))
        }
        return eventItems + reminderItems
    }

    var body: some View {
        VStack(spacing: 0) {
            if !allDayEvents.isEmpty { allDayLane.padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6) }
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    GeometryReader { geometry in dayCanvas(width: geometry.size.width) }
                        .frame(height: hourHeight * 24)
                }
                .scrollIndicators(.hidden).background(palette.canvas)
                .task(id: date) {
                    didInitialScroll = false
                    await scrollInitially(using: proxy)
                }
            }
        }.background(palette.canvas)
    }

    private var allDayLane: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("ALL-DAY").font(.caption2.weight(.semibold)).foregroundStyle(palette.secondaryText)
            ForEach(allDayEvents) { event in
                Button { onEventTap(event) } label: {
                    Text(event.title).font(.caption.weight(.semibold)).foregroundStyle(palette.eventText).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 9).padding(.vertical, 7)
                        .background(palette.eventFill).clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func dayCanvas(width: CGFloat) -> some View {
        let placements = CalendarDayLayout.placements(for: canvasItems.map { CalendarDayInterval(id: $0.id, startMinute: $0.startMinute, endMinute: $0.endMinute) })
        let placementByID = Dictionary(uniqueKeysWithValues: placements.map { ($0.id, $0) })
        let contentWidth = max(width - timeGutter - 10, 1)
        ZStack(alignment: .topLeading) {
            ForEach(0..<24, id: \.self) { hour in hourRule(hour: hour, contentWidth: contentWidth).id("hour-\(hour)") }
            ForEach(canvasItems) { item in
                if let placement = placementByID[item.id] {
                    let columnWidth = (contentWidth - CGFloat(placement.columnCount - 1) * 3) / CGFloat(placement.columnCount)
                    dayItem(item)
                        .frame(width: columnWidth, height: blockHeight(for: item))
                        .offset(x: timeGutter + CGFloat(placement.column) * (columnWidth + 3), y: yPosition(for: item.startMinute))
                }
            }
            if Calendar.current.isDateInToday(date) {
                let minute = minuteOffset(for: currentTime)
                if (0...1_440).contains(minute) { nowLine(minute: minute, width: contentWidth) }
            }
        }.background(palette.canvas)
    }

    private func hourRule(hour: Int, contentWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(hourDate(hour).formatted(date: .omitted, time: .shortened))
                .font(.caption2).foregroundStyle(palette.secondaryText).frame(width: timeGutter - 8, alignment: .trailing).offset(y: -7)
            Rectangle().fill(palette.gridLine).frame(width: contentWidth, height: 0.5)
        }.offset(y: CGFloat(hour) * hourHeight)
    }

    @ViewBuilder private func dayItem(_ item: DayCanvasItem) -> some View {
        switch item.kind {
        case .event(let event):
            EventBlock(event: event, palette: palette).onTapGesture { onEventTap(event) }
                .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
        case .reminder(let group):
            ReminderBlock(group: group, palette: palette, onTap: onReminderTap, onToggle: onToggleReminder)
        }
    }

    private func nowLine(minute: Int, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(currentTime.formatted(date: .omitted, time: .shortened)).font(.caption2.weight(.bold)).foregroundStyle(palette.accent)
                .frame(width: timeGutter - 4, alignment: .trailing).padding(.trailing, 4)
            Circle().fill(palette.accent).frame(width: 8, height: 8)
            Rectangle().fill(palette.accent).frame(width: width - 4, height: 1.5)
        }.offset(y: yPosition(for: minute) - 4).accessibilityHidden(true)
    }

    private func yPosition(for minutes: Int) -> CGFloat { CGFloat(minutes) / 60 * hourHeight }
    private func blockHeight(for item: DayCanvasItem) -> CGFloat { max(32, CGFloat(item.endMinute - item.startMinute) / 60 * hourHeight - 2) }
    private func minuteOffset(for date: Date) -> Int { max(0, min(1_440, Int(date.timeIntervalSince(dayStart) / 60))) }
    private func hourDate(_ hour: Int) -> Date { Calendar.current.date(byAdding: .hour, value: hour, to: dayStart) ?? dayStart }

    private func scrollInitially(using proxy: ScrollViewProxy) async {
        guard !didInitialScroll else { return }
        didInitialScroll = true
        let target: Int
        if Calendar.current.isDateInToday(date) { target = max(0, Calendar.current.component(.hour, from: currentTime) - 1) }
        else if let first = canvasItems.map(\.startMinute).min() { target = max(0, first / 60 - 1) }
        else { target = 8 }
        await Task.yield()
        proxy.scrollTo("hour-\(target)", anchor: .top)
    }
}

private struct EventBlock: View {
    let event: CalendarEvent
    let palette: CalendarPalette
    var body: some View {
        HStack(spacing: 0) {
            Capsule().fill(palette.accent).frame(width: 3).padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.caption.weight(.bold)).lineLimit(2)
                Text("\(event.startDate.formatted(date: .omitted, time: .shortened)) – \(event.endDate.formatted(date: .omitted, time: .shortened))").font(.caption2).lineLimit(1)
                if let location = event.location, !location.isEmpty { Text(location).font(.caption2).lineLimit(1) }
            }.foregroundStyle(palette.eventText).padding(.horizontal, 7).padding(.vertical, 6)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.eventFill).clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct ReminderBlock: View {
    let group: CalendarReminderGroup
    let palette: CalendarPalette
    let onTap: (CalendarReminder) -> Void
    let onToggle: (CalendarReminder) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(group.reminders) { reminder in
                HStack(spacing: 7) {
                    Button { onToggle(reminder) } label: {
                        Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(reminder.isCompleted ? palette.secondaryText : palette.accent).font(.body)
                    }.buttonStyle(.plain).accessibilityLabel(reminder.isCompleted ? "Mark reminder incomplete" : "Complete reminder")
                    Button { onTap(reminder) } label: {
                        Text(reminder.text).font(.caption.weight(.semibold)).strikethrough(reminder.isCompleted)
                            .foregroundStyle(reminder.isCompleted ? palette.secondaryText : palette.primaryText).lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).accessibilityLabel("Edit reminder: \(reminder.text)")
                }.opacity(reminder.isCompleted ? 0.55 : 1)
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.reminderFill)
        .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(palette.reminderStroke, lineWidth: 1) }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct CalendarEventDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let event: CalendarEvent
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Starts", value: event.startDate.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Ends", value: event.endDate.formatted(date: .abbreviated, time: .shortened))
                    if let location = event.location, !location.isEmpty { LabeledContent("Location", value: location) }
                    if let attendees = event.attendees, !attendees.isEmpty { LabeledContent("Attendees", value: attendees) }
                }
                if let notes = event.notes, !notes.isEmpty { Section("Notes") { Text(notes) } }
            }
            .navigationTitle(event.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct CalendarPalette {
    let colorScheme: ColorScheme
    var background: LinearGradient { LinearGradient(colors: colorScheme == .dark ? [Color(red: 0.035, green: 0.10, blue: 0.18), Color(red: 0.08, green: 0.19, blue: 0.31)] : [Color(red: 0.72, green: 0.85, blue: 0.96), Color(red: 0.89, green: 0.94, blue: 0.99)], startPoint: .bottom, endPoint: .top) }
    var canvas: Color { colorScheme == .dark ? Color(red: 0.08, green: 0.16, blue: 0.25) : Color(red: 0.90, green: 0.95, blue: 1.0) }
    var accent: Color { colorScheme == .dark ? Color(red: 0.31, green: 0.67, blue: 1.0) : Color(red: 0.18, green: 0.58, blue: 0.94) }
    var primaryText: Color { colorScheme == .dark ? Color(red: 0.91, green: 0.96, blue: 1.0) : Color(red: 0.09, green: 0.22, blue: 0.38) }
    var secondaryText: Color { colorScheme == .dark ? Color(red: 0.57, green: 0.70, blue: 0.83) : Color(red: 0.42, green: 0.56, blue: 0.71) }
    var gridLine: Color { colorScheme == .dark ? Color.white.opacity(0.18) : Color(red: 0.44, green: 0.62, blue: 0.80).opacity(0.42) }
    var eventFill: Color { colorScheme == .dark ? Color(red: 0.12, green: 0.31, blue: 0.50) : Color(red: 0.76, green: 0.85, blue: 0.94) }
    var eventText: Color { primaryText }
    var reminderFill: Color { colorScheme == .dark ? Color(red: 0.09, green: 0.21, blue: 0.33) : Color.white.opacity(0.62) }
    var reminderStroke: Color { accent.opacity(colorScheme == .dark ? 0.65 : 0.45) }
    var toolbarTint: Color { accent.opacity(0.2) }
}

private extension Calendar {
    static func weekStart(containing date: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 1
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }
}

#Preview {
    NavigationStack { CalendarView() }
        .modelContainer(for: [CalendarEvent.self, CalendarReminder.self], inMemory: true)
}
