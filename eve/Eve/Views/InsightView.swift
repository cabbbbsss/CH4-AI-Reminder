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
      Color(hex: "#E0ECF7").ignoresSafeArea()

      VStack(spacing: 0) {
        // Top Nav
        HStack {
          Button(action: {
            dismiss()
          }) {
            Image(systemName: "chevron.backward.circle.fill")
              .font(.system(size: 32))
              .foregroundColor(Color(hex: "#1D3557"))
              .background(Circle().fill(Color.white))
          }

          Spacer()

          Text("Insight")
            .font(.system(size: 17, weight: .bold))
            .foregroundColor(.black)

          Spacer()

          // placeholder to balance the back button
          Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)

        // Character + Chat Bubble
        HStack(alignment: .center, spacing: 16) {
          // Robot Face Group
          ZStack {
            Circle()
              .fill(Color.clear)
              .frame(width: 79, height: 79)

            Circle()
              .fill(Color.white)
              .frame(width: 70, height: 70)

            // Screen
            Ellipse()
              .fill(Color(hex: "#1A1916"))
              .frame(width: 54, height: 36)
              .offset(y: -2)

            // Face details
            VStack(spacing: 4) {
              HStack(spacing: 14) {
                Ellipse().fill(Color(hex: "#E0ECF7")).frame(width: 5, height: 3)
                Ellipse().fill(Color(hex: "#E0ECF7")).frame(width: 5, height: 3)
              }
              Rectangle().fill(Color(hex: "#E0ECF7")).frame(width: 13, height: 2)
            }
            .offset(y: -2)
          }

          // Chat Bubble
          ZStack(alignment: .leading) {
            // The triangle pointing left
            Path { path in
              path.move(to: CGPoint(x: 10, y: 15))
              path.addLine(to: CGPoint(x: 0, y: 25))
              path.addLine(to: CGPoint(x: 10, y: 35))
            }
            .fill(Color.white)
            .offset(x: -8)

            Text("Here’s what I’ve learned\nabout you!")
              .font(.system(size: 13, weight: .bold))
              .foregroundColor(Color(hex: "#1D3557"))
              .padding(.horizontal, 16)
              .padding(.vertical, 12)
              .background(Color.white)
              .cornerRadius(12)
          }
          Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 24)

        // Dark Blue Container
        ZStack(alignment: .top) {
          Color(hex: "#1D3557")
            .cornerRadius(32, corners: [.topLeft, .topRight])
            .ignoresSafeArea(edges: .bottom)

          VStack {
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
              }
            }

            // Button
            NavigationLink(destination: HistoryView()) {
              Text("View History")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(hex: "#E0ECF7"))
                .frame(width: 200, height: 44)
                .background(Color(hex: "#368BC8"))
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

  private var emptyState: some View {
    VStack(spacing: 12) {
      Image(systemName: "brain")
        .font(.system(size: 44))
        .foregroundColor(Color(hex: "#E8F3FF").opacity(0.6))
      Text("No insights yet")
        .font(.system(size: 18, weight: .bold))
        .foregroundColor(Color(hex: "#E8F3FF"))
      Text("Tap Eve on the home screen and I'll start learning your routine. What I learn appears here — always yours to correct.")
        .font(.system(size: 14))
        .foregroundColor(Color(hex: "#E8F3FF").opacity(0.7))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.top, 60)
    .padding(.horizontal, 40)
    .frame(maxHeight: .infinity, alignment: .top)
  }
}

/// One belief, in the designed light-on-navy style, tappable to edit.
struct InsightRow: View {
  let insight: AIInsight

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      Image(systemName: insight.isUserEdited ? "checkmark.seal.fill" : "checkmark.circle")
        .font(.system(size: 20))
        .foregroundColor(Color(hex: "#EDF3FA"))
        .padding(.top, 2)

      VStack(alignment: .leading, spacing: 4) {
        Text(insight.value)
          .font(.system(size: 18, weight: .medium))
          .foregroundColor(Color(hex: "#E8F3FF"))
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)

        Text(insight.isUserEdited
             ? "Confirmed by you"
             : "\(Int(insight.confidence * 100))% confident")
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(Color(hex: "#9FB6D1"))
      }

      Image(systemName: "chevron.right")
        .font(.system(size: 12, weight: .bold))
        .foregroundColor(Color(hex: "#9FB6D1"))
        .padding(.top, 4)
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
