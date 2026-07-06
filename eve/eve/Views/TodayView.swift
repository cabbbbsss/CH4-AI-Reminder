//
//  TodayView.swift
//  Eve
//
//  Created by cabsss on 06/07/26.
//

import SwiftUI
import SwiftData

struct TodayView: View {

    @Environment(\.modelContext)
    private var modelContext

    @State private var viewModel: TodayViewModel?

    @State private var answerText = ""

    @Query(sort: \CalendarEvent.startDate)
    private var events: [CalendarEvent]

    @Query
    private var reminders: [ReminderItem]

    private var sortedReminders: [ReminderItem] {
        reminders.sorted {
            ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                assistantSection
                statusSection
                eventsSection
                remindersSection
            }
            .navigationTitle("Eve")
            .refreshable {
                await viewModel?.sync.syncNow()
            }
        }
        .task {

            guard viewModel == nil else { return }

            let vm = TodayViewModel(context: modelContext)

            viewModel = vm

            await vm.start()

        }
    }

    // MARK: - Assistant

    private var assistantSection: some View {
        Section("Assistant") {

            if viewModel?.assistant.isThinking == true {

                HStack {
                    ProgressView()
                    Text("Eve is thinking…")
                        .foregroundStyle(.secondary)
                }

            } else {

                Button {
                    Task { await viewModel?.askEve() }
                } label: {
                    Label("Ask Eve now", systemImage: "sparkles")
                }
                .disabled(viewModel == nil)

            }

            if let error = viewModel?.assistant.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let decision = viewModel?.assistant.lastDecision {

                VStack(alignment: .leading, spacing: 4) {

                    Label(
                        decision.shouldNotify
                            ? "Reminder sent"
                            : "No reminder needed right now",
                        systemImage: decision.shouldNotify
                            ? "bell.fill"
                            : "bell.slash"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text(decision.title)
                        .font(.headline)

                    Text(decision.body)

                }

            }

            if let question = viewModel?.assistant.pendingQuestion {

                VStack(alignment: .leading, spacing: 8) {

                    Label(question, systemImage: "questionmark.bubble")
                        .font(.headline)

                    HStack {

                        TextField("Your answer", text: $answerText)
                            .textFieldStyle(.roundedBorder)

                        Button("Send") {
                            viewModel?.assistant
                                .answerPendingQuestion(with: answerText)
                            answerText = ""
                        }
                        .disabled(answerText.isEmpty)

                    }

                }

            }

        }
    }

    // MARK: - Status & context

    private var statusSection: some View {
        Section("Context") {

            if let place = viewModel?.location.currentPlace {
                LabeledContent("Current place", value: place)
            } else if viewModel?.location.accessDenied == true {
                Text("Location access denied — enable it in Settings.")
                    .foregroundStyle(.red)
            } else {
                Text("Locating…")
                    .foregroundStyle(.secondary)
            }

            if let lastSync = viewModel?.sync.lastSync {
                LabeledContent(
                    "Last sync",
                    value: lastSync.formatted(date: .abbreviated, time: .shortened)
                )
            }

            if viewModel?.sync.hasCalendarAccess == false {
                Text("Calendar access denied — enable it in Settings.")
                    .foregroundStyle(.red)
            }

            if viewModel?.sync.hasReminderAccess == false {
                Text("Reminders access denied — enable it in Settings.")
                    .foregroundStyle(.red)
            }

        }
    }

    // MARK: - Data

    private var eventsSection: some View {
        Section("Events (±33 days) — \(events.count)") {
            ForEach(events) { event in
                VStack(alignment: .leading) {

                    Text(event.title)

                    Text(
                        event.startDate.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                }
            }
        }
    }

    private var remindersSection: some View {
        Section("Reminders — \(reminders.count)") {
            ForEach(sortedReminders) { reminder in
                VStack(alignment: .leading) {

                    Text(reminder.title)

                    if let dueDate = reminder.dueDate {
                        Text(
                            dueDate.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                }
            }
        }
    }

}
