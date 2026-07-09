//
//  InsightView.swift
//  Eve
//
//  Created by Ketut Agus Cahyadi Nanda on 07/07/26.
//  Design + real AIInsight data (merged from InsightsView).
//

import SwiftUI
import SwiftData

struct InsightView: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) private var modelContext

  // Everything Eve believes about the user — newest first.
  @Query(sort: \AIInsight.lastUpdated, order: .reverse)
  private var insights: [AIInsight]

  @State private var editingInsight: AIInsight?

  var body: some View {
    ZStack {
      LinearGradient(
        stops: [
          .init(color: Color(.bgPrimary), location: 0.75),
          .init(color: Color(.bgSecondary), location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()

      VStack(spacing: 0) {
        // ── Top Nav ──────────────────────────────────────────
        HStack {
          Button(action: {
            dismiss()
          }) {
            Image(systemName: "chevron.backward.circle.fill")
              .font(.system(size: 32))
              .symbolRenderingMode(.palette)
              .foregroundStyle(
                Color(.textPrimary),
                Color(.bgSecondary)
              )
          }

          Spacer()

          Text("Insight")
            .font(.system(size: 17, weight: .bold))
            .foregroundColor(Color(.textPrimary))

          Spacer()

          // placeholder to balance the back button
          Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)

        // ── Character + Chat Bubble ─────────────────────────
        HStack(alignment: .center, spacing: 16) {
          // Avatar from xcassets
          Image("Avatar")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 79, height: 79)

          // Chat Bubble
          ZStack(alignment: .leading) {
            // The triangle pointing left
//            Path { path in
//              path.move(to: CGPoint(x: 10, y: 15))
//              path.addLine(to: CGPoint(x: 0, y: 25))
//              path.addLine(to: CGPoint(x: 10, y: 35))
//            }
//            .fill(Color(.bgSecondary))
//            .offset(x: -8)

            bubbleText
              .padding(.horizontal, 16)
              .padding(.vertical, 12)
              .background(Color(.bgSecondary))
              .cornerRadius(12)
          }
          Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 24)

        // ── Insights Card Container ─────────────────────────
        ZStack(alignment: .top) {
          Color(.bgSecondary)
            .cornerRadius(64, corners: [.topLeft, .topRight])
            .ignoresSafeArea(edges: .bottom)

          VStack(spacing: 0) {
            if insights.isEmpty {
              emptyState
            } else {
              ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                  ForEach(insights) { insight in
                    Button {
                      editingInsight = insight
                    } label: {
                      InsightRow(insight: insight)
                    }
                    .buttonStyle(.plain)
                  }
                }
                .padding(.top, 40)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
              }
            }

            // View History button
            NavigationLink(destination: HistoryView()) {
              Text("View History")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 200, height: 44)
                .background(Color.accentColor)
                .cornerRadius(22)
            }
            .padding(.bottom, 40)
            .padding(.top, 20)
          }
        }
      }
    }
    .navigationBarHidden(true)
    .sheet(item: $editingInsight) { insight in
      InsightEditSheet(insight: insight)
    }
  }

  // Chat bubble with partial bold text
  private var bubbleText: some View {
    Text("Here's what I've \(Text("learned").fontWeight(.bold))\nabout you!")
      .font(.system(size: 13))
      .foregroundColor(Color(.textPrimary))
  }


  private var emptyState: some View {
    VStack(spacing: 12) {
      Image(systemName: "brain")
        .font(.system(size: 44))
        .foregroundColor(Color(.textQuarternary))
      Text("No insights yet")
        .font(.system(size: 18, weight: .bold))
        .foregroundColor(Color(.textPrimary))
      Text("Tap Eve on the home screen and I'll start learning your routine. What I learn appears here — always yours to correct.")
        .font(.system(size: 14))
        .foregroundColor(Color(.textTertiary))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.top, 60)
    .padding(.horizontal, 40)
    .frame(maxHeight: .infinity, alignment: .top)
  }
}

/// One insight row with an accent-colored checkmark, matching the sketch design.
struct InsightRow: View {
  let insight: AIInsight

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 24))
        .foregroundColor(.accentColor)
        .padding(.top, 2)

      Text(insight.value)
        .font(.system(size: 16, weight: .regular))
        .foregroundColor(Color(.textPrimary))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
    }
  }
}

/// Editing a belief makes it ground truth: it becomes user-confirmed
/// and Eve will never overwrite it.
private struct InsightEditSheet: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss

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

        Section {
          Button("Delete this insight", role: .destructive) {
            try? InsightManager(context: modelContext).delete(insight)
            dismiss()
          }
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
      .onAppear { value = insight.value }
    }
  }
}

#Preview {
  NavigationStack {
    InsightView()
  }
}
