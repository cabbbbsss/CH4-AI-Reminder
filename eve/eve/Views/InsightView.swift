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
  @Environment(\.modelContext) private var modelContext

  // Everything Eve believes about the user — newest first.
  @Query(sort: \AIInsight.lastUpdated, order: .reverse)
  private var insights: [AIInsight]

  @State private var editingInsight: AIInsight?
  @State private var expandedInsightID: PersistentIdentifier?

  var body: some View {
    ZStack {
      AuroraBackground(focus: 0.1)

      VStack(spacing: Theme.Spacing.l) {
        speechBubble
        insightsCard
      }
      .padding(.top, Theme.Spacing.l)
    }
    .navigationTitle("Insight")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
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

  // MARK: - Bubble

  /// The same bubble shape Home uses, so Eve speaks the same way on every
  /// screen rather than in a differently-shaped box per tab.
  private var speechBubble: some View {
    HStack(alignment: .top, spacing: Theme.Spacing.s) {
      Image("Avatar")
        .resizable()
        .scaledToFit()
        .frame(width: 70, height: 70)

      Text("Here's what I've \(Text("learned").fontWeight(.bold)) about you!")
        .font(.eveBody)
        .foregroundStyle(Color.eveOnSurface)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.m)
        .background(Color.eveSurface)
        .cornerRadius(Theme.Radius.card, corners: [.topRight, .bottomLeft, .bottomRight])
        .cornerRadius(Theme.Spacing.xxs, corners: [.topLeft])
    }
    .padding(.horizontal, Theme.Spacing.gutter)
    .accessibilityElement(children: .combine)
  }

  // MARK: - Card

  /// An inset card holding the beliefs and the History link.
  ///
  /// Rounded on every corner and held off the edges, rather than the
  /// full-bleed bottom sheet this used to be — the History button now sits
  /// inside it, so the card reads as one panel instead of a sheet with a
  /// button floating under it.
  private var insightsCard: some View {
    VStack(spacing: 0) {

      if insights.isEmpty {
        emptyState
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
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
          .padding(.horizontal, Theme.Spacing.l)
          .padding(.vertical, Theme.Spacing.l)
        }
        .scrollIndicators(.hidden)
      }

      viewHistoryButton
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.l)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.eveSurface)
    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
    .padding(.horizontal, Theme.Spacing.gutter)
    .padding(.bottom, Theme.Spacing.gutter)
  }

  private var viewHistoryButton: some View {
    NavigationLink(destination: HistoryView()) {
      Text("View History")
        .font(.eveButton)
        .foregroundStyle(.white)
        // Grows with the label rather than a fixed 200×44 box, so it doesn't
        // clip at larger Dynamic Type sizes.
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.s)
        .background(Capsule().fill(Color.accentColor))
    }
  }

  private var emptyState: some View {
    VStack(spacing: Theme.Spacing.s) {
      Image(systemName: "brain")
        .font(.system(size: 44))
        .foregroundStyle(Color.eveOnSurfaceFaint)

      Text("No insights yet")
        .font(.eveSectionTitle)
        .foregroundStyle(Color.eveOnSurface)

      Text("Eve learns your routine as your days go by. What she picks up appears here — always yours to correct.")
        .font(.eveDetail)
        .foregroundStyle(Color.eveOnSurfaceMuted)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.top, Theme.Spacing.xxl)
    .padding(.horizontal, Theme.Spacing.xxl)
    .frame(maxHeight: .infinity, alignment: .top)
  }
}

/// One belief: a tappable line that reveals Eve's reasoning — and edit/delete
/// — when expanded.
struct InsightRow: View {
  let insight: AIInsight
  var isExpanded: Bool
  var onTap: () -> Void
  var onEdit: () -> Void
  var onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {

      // ── Header (tap to expand) ─────────────────────────────
      Button(action: onTap) {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
          Image(systemName: "checkmark.circle.fill")
            .font(.title3)
            .foregroundStyle(Color.accentColor)

          Text(insight.value)
            .font(.eveBody)
            .foregroundStyle(Color.eveOnSurface)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)

          // The only thing telling the user a row opens. Without it the
          // reasoning and the edit/delete actions are invisible.
          Image(systemName: "chevron.right")
            .font(.eveDetail.weight(.semibold))
            .foregroundStyle(Color.eveOnSurfaceMuted)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .padding(.top, 4)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      // ── Expanded reasoning + actions ───────────────────────
      if isExpanded {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {

          VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text("Why Eve believes this")
              .font(.eveCaption)
              .foregroundStyle(Color.eveOnSurfaceMuted)

            Text(insight.sourceSummary)
              .font(.eveDetail)
              .foregroundStyle(Color.eveOnSurface)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          HStack(spacing: Theme.Spacing.l) {
            Button(action: onEdit) {
              Label("Edit", systemImage: "pencil")
                .font(.eveCaption)
                .foregroundStyle(Color.accentColor)
            }
            Button(role: .destructive, action: onDelete) {
              Label("Delete", systemImage: "trash")
                .font(.eveCaption)
                .foregroundStyle(.red)
            }
            Spacer(minLength: 0)
          }
          .buttonStyle(.plain)
        }
        // Lines the reasoning up under the belief's text, past the tick.
        .padding(.leading, 34)
        .padding(.top, Theme.Spacing.s)
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
