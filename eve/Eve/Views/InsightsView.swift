//
//  InsightsView.swift
//  Eve
//
//  Created by cabsss on 06/07/26.
//

import SwiftUI
import SwiftData

/// Everything Eve believes about the user — visible, editable, deletable.
struct InsightsView: View {

    @Environment(\.modelContext)
    private var modelContext

    @Query(sort: \AIInsight.lastUpdated, order: .reverse)
    private var insights: [AIInsight]

    @State private var editingInsight: AIInsight?

    var body: some View {
        NavigationStack {
            Group {

                if insights.isEmpty {

                    ContentUnavailableView(
                        "No insights yet",
                        systemImage: "brain",
                        description: Text(
                            "Ask Eve on the Today tab. What it learns about you appears here — always editable, always yours to correct."
                        )
                    )

                } else {

                    List {
                        ForEach(insights) { insight in
                            Button {
                                editingInsight = insight
                            } label: {
                                InsightRow(insight: insight)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: delete)
                    }

                }

            }
            .navigationTitle("AI Insights")
            .sheet(item: $editingInsight) { insight in
                InsightEditSheet(insight: insight)
            }
        }
    }

    private func delete(at offsets: IndexSet) {

        let manager = InsightManager(context: modelContext)

        for index in offsets {
            try? manager.delete(insights[index])
        }

    }

}

private struct InsightRow: View {

    let insight: AIInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            HStack {

                Text(insight.title)
                    .font(.headline)

                Spacer()

                Text(insight.category.rawValue.capitalized)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.thinMaterial, in: Capsule())

            }

            Text(insight.value)

            if insight.isUserEdited {

                Label("Confirmed by you", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.green)

            } else {

                HStack {

                    ProgressView(value: insight.confidence)

                    Text("\(Int(insight.confidence * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                }

            }

            Text(insight.sourceSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(
                "Updated \(insight.lastUpdated.formatted(date: .abbreviated, time: .shortened))"
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)

        }
        .padding(.vertical, 4)
    }

}

private struct InsightEditSheet: View {

    @Environment(\.modelContext)
    private var modelContext

    @Environment(\.dismiss)
    private var dismiss

    let insight: AIInsight

    @State private var value = ""

    var body: some View {
        NavigationStack {
            Form {

                Section("What Eve believes") {

                    LabeledContent("Title", value: insight.title)

                    TextField("Value", text: $value)

                }

                Section("Why Eve believes this") {
                    Text(insight.sourceSummary)
                }

            }
            .navigationTitle("Edit Insight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {

                        try? InsightManager(context: modelContext)
                            .recordUserEdit(insight, newValue: value)

                        dismiss()

                    }
                    .disabled(value.isEmpty)
                }

            }
            .onAppear {
                value = insight.value
            }
        }
    }

}
