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

  /// The insight a swipe-to-delete is waiting on. Deleting a belief is
  /// irreversible, so the row asks before it goes.
  @State private var pendingDelete: AIInsight?

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
    // An alert rather than a confirmation dialog: on a list row the dialog
    // anchors as a popover off the row, and this should sit centred.
    .alert(
      "Are you sure you want to delete?",
      isPresented: Binding(
        get: { pendingDelete != nil },
        set: { if !$0 { pendingDelete = nil } }
      ),
      presenting: pendingDelete
    ) { insight in
      Button("Delete Insight", role: .destructive) { delete(insight) }
      Button("Cancel", role: .cancel) { }
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
        // A List rather than a ScrollView, because swipe actions only
        // exist on List rows. Its own chrome is stripped so it reads as
        // lines on the card, not a table inside it.
        List {
          ForEach(insights) { insight in
            InsightRow(insight: insight)
              .listRowBackground(Color.clear)
              .listRowSeparator(.hidden)
              .listRowInsets(EdgeInsets(
                top: Theme.Spacing.s, leading: Theme.Spacing.l,
                bottom: Theme.Spacing.s, trailing: Theme.Spacing.l
              ))
              // Swiping the row towards the leading edge uncovers these.
              // Edit and delete are the only two things you can do to a
              // belief, so they need no chevron, no disclosure, nothing on
              // the row at rest.
              .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                  pendingDelete = insight
                } label: {
                  Label("Delete", systemImage: "trash")
                }
                // The destructive role alone inherits the accent here, so
                // the red is said outright.
                .tint(.red)
                Button {
                  editingInsight = insight
                } label: {
                  Label("Edit", systemImage: "pencil")
                }
                .tint(Color.accentColor)
              }
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .padding(.top, Theme.Spacing.s)
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

/// One belief. Just the line — what can be done to it lives behind a swipe.
struct InsightRow: View {
  let insight: AIInsight

  var body: some View {
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
    }
  }
}

/// Correcting a belief: Eve's version stays on screen, read-only, above a
/// field for what she should have known. Saving makes the user's version
/// ground truth — user-confirmed, never overwritten.
private struct InsightEditSheet: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss

  let insight: AIInsight

  /// The correction. Starts empty rather than prefilled: the point of the
  /// sheet is what Eve *should* know, and a prefilled copy of what she
  /// currently believes invites a one-word tweak of the wrong sentence.
  @State private var correction = ""
  @FocusState private var isEditing: Bool

  @State private var isConfirmingDelete = false

  private var canSave: Bool {
    !correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    NavigationStack {
      ZStack {
        AuroraBackground()

        ScrollView {
          VStack(spacing: Theme.Spacing.m) {
            card(title: "Eve's Insight") {
              Text(insight.value)
                .font(.eveBody)
                .foregroundStyle(Color.eveOnSurface)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            card(title: "What Eve should know") {
              TextField("Tell Eve what she needs to know", text: $correction, axis: .vertical)
                .font(.eveBody)
                .foregroundStyle(Color.eveOnSurface)
                .lineLimit(1...5)
                .focused($isEditing)
            }

            Button {
              isConfirmingDelete = true
            } label: {
              Text("Delete insight")
                .font(.eveBody)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.m)
                .background(Color.eveSurface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
            .buttonStyle(.plain)
          }
          .padding(.horizontal, Theme.Spacing.m)
          .padding(.top, Theme.Spacing.xs)
        }
        .scrollDismissesKeyboard(.interactively)
      }
      .navigationTitle("Edit Insight")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button { dismiss() } label: { Image(systemName: "xmark") }
            .accessibilityLabel("Cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            try? InsightManager(context: modelContext)
              .recordUserEdit(insight, newValue: correction.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
          } label: {
            Image(systemName: "checkmark")
          }
          .buttonStyle(.glassProminent)
          .disabled(!canSave)
          .accessibilityLabel("Save")
        }
      }
      .alert(
        "Are you sure you want to delete?",
        isPresented: $isConfirmingDelete
      ) {
        Button("Delete Insight", role: .destructive) {
          try? InsightManager(context: modelContext).delete(insight)
          dismiss()
        }
        Button("Cancel", role: .cancel) { }
      }
      .onAppear { isEditing = true }
    }
  }

  /// A titled card: the brain glyph and a muted heading, then whatever
  /// the card holds. Both cards on the sheet share it so they line up.
  private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
      Label(title, systemImage: "brain")
        .font(.eveCardTitle)
        .foregroundStyle(Color.eveOnSurfaceMuted)

      content()
    }
    .padding(Theme.Spacing.m)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.eveSurface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
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
