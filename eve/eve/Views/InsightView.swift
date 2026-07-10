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
  @State private var expandedInsightID: PersistentIdentifier?

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
                    InsightRow(
                      insight: insight,
                      isExpanded: expandedInsightID == insight.persistentModelID,
                      onTap: { toggle(insight) },
                      onEdit: { editingInsight = insight },
                      onDelete: { delete(insight) }
                    )
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

  /// Expand one insight at a time to reveal its reasoning.
  private func toggle(_ insight: AIInsight) {
    withAnimation(.easeInOut(duration: 0.2)) {
      expandedInsightID = expandedInsightID == insight.persistentModelID
        ? nil
        : insight.persistentModelID
    }
  }

  private func delete(_ insight: AIInsight) {
    try? InsightManager(context: modelContext).delete(insight)
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

/// One insight: a tappable headline + confidence that reveals the AI's
/// reasoning (and edit/delete) when expanded.
struct InsightRow: View {
  let insight: AIInsight
  var isExpanded: Bool
  var onTap: () -> Void
  var onEdit: () -> Void
  var onDelete: () -> Void

  /// "Confirmed by you" once the user has corrected it, otherwise the model's confidence.
  private var confidenceText: String {
    insight.isUserEdited
      ? "Confirmed by you"
      : "\(Int((insight.confidence * 100).rounded()))% confident"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {

      // ── Header (tap to expand) ─────────────────────────────
      Button(action: onTap) {
        HStack(alignment: .top, spacing: 16) {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 24))
            .foregroundColor(.accentColor)
            .padding(.top, 2)

          VStack(alignment: .leading, spacing: 4) {
            Text(insight.value)
              .font(.system(size: 17, weight: .regular))
              .foregroundColor(Color(.textPrimary))
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
              .multilineTextAlignment(.leading)

            Text(confidenceText)
              .font(.system(size: 13))
              .foregroundColor(Color(.textTertiary))
          }

          Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(Color(.textTertiary))
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .padding(.top, 6)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      // ── Expanded reasoning + actions ───────────────────────
      if isExpanded {
        VStack(alignment: .leading, spacing: 14) {

          VStack(alignment: .leading, spacing: 4) {
            Text("Why Eve believes this")
              .font(.system(size: 12, weight: .semibold))
              .foregroundColor(Color(.textTertiary))

            Text(insight.sourceSummary)
              .font(.system(size: 14))
              .foregroundColor(Color(.textPrimary))
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          HStack(spacing: 20) {
            Button(action: onEdit) {
              Label("Edit", systemImage: "pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.accentColor)
            }
            Button(role: .destructive, action: onDelete) {
              Label("Delete", systemImage: "trash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.red)
            }
            Spacer()
          }
          .buttonStyle(.plain)
        }
        .padding(.leading, 40)
        .padding(.top, 12)
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
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
    ZStack {
      Color(.bgPrimary)
        .ignoresSafeArea()

      NavigationStack {
        Form {
          // ── What Eve believes ──────────────────────────────
          Section {
            LabeledContent("Title", value: insight.title)
              .foregroundColor(Color(.textPrimary))

            LabeledContent("Answer") {
              TextField("Enter answer", text: $value)
                .multilineTextAlignment(.trailing)
                .foregroundColor(Color(.textTertiary))
            }
            .foregroundColor(Color(.textPrimary))
          } header: {
            Text("What Eve believes")
              .foregroundColor(Color(.textTertiary))
          }
          .listRowBackground(Color(.bgSecondary))

          // ── Why Eve believes this (read-only AI reasoning) ─
          Section {
            HStack(alignment: .top, spacing: 12) {
              Image(systemName: "brain.head.profile")
                .font(.system(size: 20))
                .foregroundColor(Color(.textTertiary))
                .padding(.top, 2)

              VStack(alignment: .leading, spacing: 4) {
                Text("Eve's reasoning")
                  .font(.system(size: 12, weight: .semibold))
                  .foregroundColor(Color(.textTertiary))
                  .textCase(nil)

                Text(insight.sourceSummary)
                  .font(.system(size: 14))
                  .foregroundColor(Color(.textPrimary))
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
            .padding(.vertical, 4)
          } header: {
            Text("Why Eve believes this")
              .foregroundColor(Color(.textTertiary))
          }
          .listRowBackground(Color(.bgSecondary))

          // ── Delete ─────────────────────────────────────────
          Section {
            Button("Delete this insight", role: .destructive) {
              try? InsightManager(context: modelContext).delete(insight)
              dismiss()
            }
          }
          .listRowBackground(Color(.bgSecondary))
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Edit Insight")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
              .foregroundColor(Color(.textPrimary))
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
              try? InsightManager(context: modelContext)
                .recordUserEdit(insight, newValue: value)
              dismiss()
            }
            .disabled(value.isEmpty)
            .foregroundColor(.accentColor)
          }
        }
        .onAppear { value = insight.value }
      }
    }
  }
}

#Preview {
  NavigationStack {
    InsightView()
  }
}

// Enable native swipe-to-go-back gesture when navigation bar is hidden
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return viewControllers.count > 1
    }
}
