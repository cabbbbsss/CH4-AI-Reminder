//
//  NewReminderRow.swift
//  Eve
//
//  The dashed "add" row at the end of a list of reminders, as a field rather
//  than a button: type a title and press return, and the reminder is there.
//  The ⓘ that appears while typing carries the draft into the Details sheet
//  for anything beyond a title — the same shape as an existing row's edit.
//

import SwiftUI

struct NewReminderRow<ID: Hashable>: View {

    /// This row's key in the screen's shared focus state. Screens have one
    /// add row per section, so each needs its own.
    var focusID: ID

    /// Shared with the screen so a background tap can end the edit, and so
    /// only one field is live at a time.
    var focused: FocusState<ID?>.Binding

    var font: Font = .eveBody

    /// A title was entered: make the reminder. The row has already cleared
    /// itself, ready for the next one.
    var onCommit: (String) -> Void

    /// ⓘ was tapped with this much typed; open Details with it filled in.
    var onOpenDetails: (String) -> Void

    @State private var draft = ""

    private var isEditing: Bool { focused.wrappedValue == focusID }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {

            // Dotted, not dashed: a round cap with a near-zero dash length
            // draws dots rather than the stubby ticks a plain dash gives.
            // Tapping it is the same as tapping into the field.
            Button {
                focused.wrappedValue = focusID
            } label: {
                Circle()
                    .strokeBorder(
                        Color.eveOnSurfaceFaint.opacity(0.7),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.5, 3])
                    )
                    .frame(width: 18, height: 18)
                    // Lines the circle up with the checkboxes above it.
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a reminder")

            TextField("Add a reminder…", text: $draft)
                .font(font)
                .foregroundStyle(Color.eveOnSurface)
                .focused(focused, equals: focusID)
                .submitLabel(.done)
                .onSubmit(commit)

            // Only while typing — at rest the row is just its placeholder.
            // Collapsed rather than removed: a view taken out of the tree
            // mid-tap never delivers its action.
            Button {
                let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                // Cleared first, so the focus loss the sheet causes below
                // finds nothing to commit — otherwise the draft would be
                // added here *and* opened there.
                draft = ""
                onOpenDetails(title)
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Details")
            .opacity(isEditing ? 1 : 0)
            .frame(width: isEditing ? nil : 0)
            .allowsHitTesting(isEditing)
            .accessibilityHidden(!isEditing)
            .animation(.easeInOut(duration: 0.15), value: isEditing)
        }
        // Tapping away keeps what was typed rather than silently dropping it,
        // the same as an existing row's title.
        .onChange(of: focused.wrappedValue) { previous, current in
            if previous == focusID && current != focusID { commit() }
        }
    }

    private func commit() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        guard !title.isEmpty else { return }
        onCommit(title)
    }
}
