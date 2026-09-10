import Combine
import SwiftUI
import SwiftData

struct HomeView: View {

    @Environment(\.modelContext) private var modelContext

    // The composition root ported from TodayView: owns the sync,
    // location and assistant managers and starts them in order.
    @State private var viewModel: TodayViewModel?

    /// Generates the day's reminders from the calendar. Home doesn't list
    /// calendar events — it lists what Eve decided you need to do about them.
    @State private var reminderManager: CalendarReminderManager?

    /// Every reminder Eve holds. `reminderDate` is computed (an hour before
    /// its event), so it can't be a SwiftData sort key — today's are filtered
    /// and ordered in `todaysReminders` instead.
    @Query private var allReminders: [CalendarReminder]

    /// Whether to show the PLUS badge.
    ///
    /// A placeholder for the subscription that doesn't exist yet: nothing sets
    /// it, so the badge stays hidden until a real entitlement check does.
    /// When StoreKit lands, this is the single line that should start reading
    /// from it instead of local storage.
    @AppStorage("isPlusUser") private var isPlusUser = false

    @State private var isAddingItem = false

    /// The reminder whose Details sheet is open.
    @State private var editingReminder: CalendarReminder?

    /// Keeps notifications in step with edits and grows repeating series.
    @State private var scheduler: ReminderScheduler?

    /// Which row's title is being edited, by reminder id.
    ///
    /// Held here rather than inside `RoutineRow` because dismissing the
    /// keyboard is a screen-level concern: a tap on the background has no way
    /// to reach a `@FocusState` that lives inside whichever row happens to
    /// own it. Keyed by id so `.focused(_:equals:)` still routes to one row.
    @FocusState private var focusedReminderID: UUID?

    /// The reminders due today, in the order they'll come up.
    ///
    /// Filtered on `reminderDate` rather than the event's own date: a reminder
    /// for a 00:30 event fires at 23:30 the night before, and it belongs to
    /// the day the user will actually see it.
    private var todaysReminders: [CalendarReminder] {
        allReminders
            .filter { Calendar.current.isDateInToday($0.reminderDate) }
            .sorted { $0.reminderDate < $1.reminderDate }
    }

    /// The AI suggestion bubble text.
    ///
    /// Distinguishes "no read yet" from "looked, nothing needed" and "looked,
    /// it failed" — otherwise a successful-but-quiet decision and a silent
    /// failure would look identical, and there's no longer a tap that would
    /// tell them apart.
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
                : "Nothing urgent right now — I'll speak up when something needs you."
        }
        return "Getting a read on your day…"
    }

    var body: some View {
        TabView {
            NavigationStack {
                homeTab
                    .navigationBarHidden(true)
            }
            .tabItem {
                Label("Routine", systemImage: "list.bullet")
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
                Label("Insights", systemImage: "clock.arrow.circlepath")
            }
        }
        .tint(Color.accentColor)
        .task {
            // Create the managers once, then start syncing + monitoring.
            guard viewModel == nil else { return }
            let vm = TodayViewModel(context: modelContext)
            viewModel = vm
            await vm.start()

            // The routine is generated, not imported: without this the list
            // would stay empty until the user happened to open the Calendar
            // tab, which is what triggers generation there.
            let manager = CalendarReminderManager(context: modelContext)
            reminderManager = manager

            let scheduler = ReminderScheduler(context: modelContext)
            self.scheduler = scheduler

            // These two don't depend on each other — one builds the day's
            // routine from the calendar, the other asks the model what matters
            // right now. Both can take seconds on device, and in sequence the
            // user waits for their sum, so they run together.
            //
            // The second is silent: opening Home never fires a notification.
            async let generated: Void = manager.ensureReminders(for: .now)
            async let read: Void = vm.assistant.generateInitialInsights(
                currentPlace: vm.location.currentPlace
            )
            _ = await (generated, read)

            // Rebuild the pending notifications from the store — without this a
            // reinstall or a reboot leaves every existing reminder silent.
            //
            // Deliberately not awaited. Nothing on screen waits for it, and
            // while it *was* part of this chain its permission prompt suspended
            // startup until the user answered — leaving the routine and the
            // suggestion bubble stuck behind a dialog on first launch. It no
            // longer prompts at all (see `syncAll`), and now it also can't
            // delay anything if it turns slow.
            Task { await scheduler.syncAll() }
        }
    }

    private var homeTab: some View {
        ZStack(alignment: .top) {
            AuroraBackground(focus: 0.1)

            VStack(spacing: Theme.Spacing.l) {
                header
                suggestionBubble
                routineList
            }
            .padding(.top, Theme.Spacing.l)
        }
        // A tap on anything that isn't a row or a control ends the edit.
        // Buttons and text fields are hit first, so this only ever catches the
        // gaps between them.
        .contentShape(Rectangle())
        .onTapGesture { focusedReminderID = nil }
        .sheet(isPresented: $isAddingItem) {
            ReminderDetailsView(defaultDate: .now)
        }
        .sheet(item: $editingReminder) { reminder in
            ReminderDetailsView(reminder: reminder)
        }
        // --- Automatic re-reads -------------------------------------------
        // The bubble is no longer tappable, so it has to keep itself current.
        // Eve re-reads the day whenever something that could change what
        // matters moves: where the user is, what's on the routine, or simply
        // time passing (the next thing gets closer, so urgency changes).
        .onChange(of: viewModel?.location.currentPlace) { _, _ in
            refreshSuggestion()
        }
        .onChange(of: todaysReminders.map(\.id)) { _, _ in
            refreshSuggestion()
        }
        .onReceive(
            Timer.publish(every: 600, on: .main, in: .common).autoconnect()
        ) { _ in
            refreshSuggestion()
        }
    }

    /// Re-asks Eve for the day's most urgent thing, silently. Skipped while a
    /// read is already running so overlapping triggers can't stack up model
    /// calls.
    private func refreshSuggestion() {
        guard let viewModel, viewModel.assistant.isThinking == false else { return }
        Task {
            await viewModel.assistant.generateInitialInsights(
                currentPlace: viewModel.location.currentPlace
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text("Today")
                .font(.eveScreenTitle.bold())
                .foregroundStyle(Color.eveOnSurface)

            Spacer(minLength: Theme.Spacing.xs)

            if isPlusUser {
                plusBadge
            }

            #if DEBUG
            NavigationLink(destination: PromptTesterView()) {
                Image(systemName: "ladybug.fill")
                    .font(.title3)
                    .foregroundStyle(Color.eveOnSurface)
                    .padding(Theme.Spacing.xs)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            #endif

            NavigationLink(destination: SettingsView()) {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(Color.eveOnSurface)
                    .padding(Theme.Spacing.xs)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, Theme.Spacing.gutter)
    }

    private var plusBadge: some View {
        Text("PLUS")
            .font(.eveCaption)
            .tracking(1)
            .foregroundStyle(Color.eveOnInverseSurface)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Capsule().fill(Color.eveInverseSurface))
            .accessibilityLabel("Eve Plus subscriber")
    }

    // MARK: - Suggestion bubble

    /// Eve's read on the day. Not a button any more: it refreshes itself when
    /// the day, the place or the clock moves (see the modifiers on `homeTab`),
    /// so there is nothing for a tap to do.
    private var suggestionBubble: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            ZStack {
                Image("Avatar")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 70, height: 70)

                if viewModel?.assistant.isThinking == true {
                    ProgressView()
                        .tint(Color.eveOnInverseSurface)
                }
            }

            // Capped so an over-long model response can't push the routine off
            // the screen. The prompt asks for one sentence under 18 words,
            // which fits in three lines here — this is the guarantee for when
            // it doesn't comply, since nothing about a generated string is
            // certain.
            Text(suggestionText)
                .font(.eveBody)
                .foregroundStyle(Color.eveOnSurface)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.m)
                .background(Color.eveSurface)
                .cornerRadius(Theme.Radius.card, corners: [.topRight, .bottomLeft, .bottomRight])
                .cornerRadius(Theme.Spacing.xxs, corners: [.topLeft])
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .animation(.easeInOut, value: suggestionText)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Routine

    /// The parts of the day that actually have something in them. Held here so
    /// the divider below can tell which section is the last one — a rule under
    /// the final section would be a line with nothing after it.
    private var visibleParts: [DayPart] {
        DayPart.allCases.filter { part in
            todaysReminders.contains { part.contains($0.reminderDate) }
        }
    }

    private var routineList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {

                if todaysReminders.isEmpty {

                    Text("Nothing to prepare for today.")
                        .font(.eveBody)
                        .foregroundStyle(Color.eveOnSurfaceMuted)
                        .padding(.top, Theme.Spacing.m)

                    addRow

                } else {

                    ForEach(Array(visibleParts.enumerated()), id: \.element.id) { index, part in
                        section(
                            part,
                            todaysReminders.filter { part.contains($0.reminderDate) },
                            // A rule under the last section would be a line
                            // with nothing after it.
                            showsDivider: index < visibleParts.count - 1
                        )
                    }

                }

            }
            .padding(.horizontal, Theme.Spacing.gutter)
            // Clears the tab bar, so the last add row isn't sitting under it
            // when the list happens to end near the bottom of the screen.
            .padding(.bottom, Theme.Spacing.xxl * 2)
        }
        .scrollIndicators(.hidden)
        // Dragging the list away from a field dismisses too, which is what
        // every other iOS list does.
        .scrollDismissesKeyboard(.interactively)
    }

    private func section(
        _ part: DayPart,
        _ items: [CalendarReminder],
        showsDivider: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {

            Text(part.title)
                .font(.eveBody.weight(.semibold))
                .foregroundStyle(Color.eveOnSurfaceMuted)

            ForEach(items) { reminder in
                RoutineRow(
                    reminder: reminder,
                    focused: $focusedReminderID,
                    onToggleCompleted: { toggleCompleted(reminder) },
                    onCommitTitle: { commitTitle($0, on: reminder) },
                    onOpenDetails: { editingReminder = reminder }
                )
            }

            addRow

            // Inside the section rather than between them, so the rule picks up
            // this stack's tighter spacing and sits just under the add circle —
            // the outer stack's gap left it floating midway to the next heading.
            if showsDivider {
                sectionDivider
            }
        }
    }

    /// The "add something here" affordance: an empty, dotted checkbox sitting
    /// where the next reminder's own checkbox would be, labelled so it reads
    /// as an invitation rather than an unexplained circle.
    ///
    /// Opens the same sheet the ⓘ button does, which writes a reminder — so
    /// whatever is added lands straight back in this list.
    private var addRow: some View {
        Button {
            isAddingItem = true
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                // Dotted, not dashed: a round cap with a near-zero dash length
                // draws dots rather than the stubby ticks a plain dash gives.
                Circle()
                    .strokeBorder(
                        Color.eveOnSurfaceFaint.opacity(0.7),
                        style: StrokeStyle(
                            lineWidth: 1.5,
                            lineCap: .round,
                            dash: [0.5, 3]
                        )
                    )
                    .frame(width: 18, height: 18)
                    // Lines the circle up with the checkboxes above it.
                    .frame(width: 22, height: 22)

                // Styled like a placeholder, because that is what it is — the
                // title the next reminder would have.
                Text("Add a reminder…")
                    .font(.eveBody)
                    .foregroundStyle(Color.eveOnSurfaceFaint)

                Spacer(minLength: 0)
            }
            // The whole width is the target, which is both easier to hit than
            // an 18pt circle and why the row no longer needs padding tricks to
            // reach a usable size without growing taller than the rule below.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a reminder")
    }

    /// Rules off one part of the day from the next. Sits below that section's
    /// add row and above the next section's heading, spanning the full column.
    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.eveOnSurfaceFaint.opacity(0.4))
            .frame(height: 1)
            // Sits close under the add circle and leaves more air beneath, so
            // it reads as closing this section rather than as belonging to the
            // heading that follows it.
            .padding(.bottom, Theme.Spacing.s)
    }

    // MARK: - Actions

    /// Ticking a row off runs through the scheduler, not just the model: a
    /// completed reminder's notification has to be cancelled, and a repeating
    /// one has to put its next instance on the calendar.
    private func toggleCompleted(_ reminder: CalendarReminder) {
        let scheduler = scheduler ?? ReminderScheduler(context: modelContext)
        Task { await scheduler.setCompleted(reminder, !reminder.isCompleted) }
    }

    /// Saves a title edited in place on the row.
    ///
    /// An emptied title is rejected rather than saved — a row with no text is
    /// unreadable and there is no undo here. The field reverts on its own.
    private func commitTitle(_ newTitle: String, on reminder: CalendarReminder) {

        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != reminder.text else { return }

        reminder.text = trimmed
        // Editing makes the row the user's, so a calendar reload won't
        // regenerate over the top of it.
        reminder.isSystemManaged = false
        try? modelContext.save()

        let scheduler = scheduler ?? ReminderScheduler(context: modelContext)
        Task { await scheduler.sync(reminder) }
    }
}

// MARK: - Day parts

/// The three buckets the routine is grouped into.
private enum DayPart: String, CaseIterable, Identifiable {
    case morning, afternoon, evening

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        }
    }

    private var hours: Range<Int> {
        switch self {
        case .morning: return 0..<12
        case .afternoon: return 12..<17
        case .evening: return 17..<24
        }
    }

    func contains(_ date: Date) -> Bool {
        hours.contains(Calendar.current.component(.hour, from: date))
    }
}

// MARK: - Routine row

private struct RoutineRow: View {
    var reminder: CalendarReminder

    /// Shared with every other row and with the screen, so exactly one title
    /// is editable at a time and a background tap can clear it.
    var focused: FocusState<UUID?>.Binding

    var onToggleCompleted: () -> Void
    var onCommitTitle: (String) -> Void
    var onOpenDetails: () -> Void

    /// The title is edited in place, so the row needs its own copy to type
    /// into — binding a `TextField` straight at the model would write on every
    /// keystroke and save a half-typed title if the view went away mid-edit.
    @State private var draftTitle = ""

    private var isEditingTitle: Bool { focused.wrappedValue == reminder.id }

    private var titleColor: Color {
        reminder.isCompleted ? .eveOnSurfaceFaint : .eveOnSurface
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {

            Button(action: onToggleCompleted) {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(reminder.isCompleted ? Color.accentColor : Color.eveOnSurfaceFaint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(reminder.isCompleted ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {

                TextField("Title", text: $draftTitle, axis: .vertical)
                    .font(.eveBody)
                    .foregroundStyle(titleColor)
                    .strikethrough(reminder.isCompleted, color: .eveOnSurfaceFaint)
                    .focused(focused, equals: reminder.id)
                    .submitLabel(.done)
                    .onSubmit { commit() }

                // Home shows title, notes and time — nothing else. The rest of
                // the reminder lives behind the ⓘ button.
                if let notes = reminder.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.eveDetail)
                        .foregroundStyle(Color.eveOnSurfaceMuted)
                        .lineLimit(2)
                }

                Text(reminder.hasTime
                    ? reminder.reminderDate.formatted(date: .omitted, time: .shortened)
                    : "All day")
                    .font(.eveCardTitle)
                    .foregroundStyle(titleColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Only while the title is being edited — a row at rest is just
            // its text.
            //
            // Collapsed rather than removed with an `if`: the tap that opens
            // Details is also what ends the edit, and a view taken out of the
            // hierarchy mid-gesture never delivers its action. Holding it in
            // the tree at zero width keeps the button's identity — and so its
            // in-flight tap — intact while it animates away.
            Button {
                // The edit is ending either way, so bank it before leaving.
                // `commit` is a no-op when nothing changed.
                commit()
                onOpenDetails()
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Details")
            .opacity(isEditingTitle ? 1 : 0)
            .frame(width: isEditingTitle ? nil : 0)
            .allowsHitTesting(isEditingTitle)
            .accessibilityHidden(!isEditingTitle)
            .animation(.easeInOut(duration: 0.15), value: isEditingTitle)
        }
        .onAppear { draftTitle = reminder.text }
        // Keeps the field in step when the reminder changes underneath it —
        // an edit saved from the Details sheet, or a sync rewriting the row.
        .onChange(of: reminder.text) { _, newValue in
            if !isEditingTitle { draftTitle = newValue }
        }
        .onChange(of: focused.wrappedValue) { previous, current in
            // Committing when this row loses focus as well as on Return, so
            // tapping away keeps the edit rather than silently dropping it.
            if previous == reminder.id && current != reminder.id { commit() }
        }
    }

    private func commit() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draftTitle = reminder.text
            return
        }
        onCommitTitle(trimmed)
    }
}

#Preview {
    HomeView()
}
