import SwiftUI
import SwiftData

struct ContextualCustomizeView: View {
    let eventType: String
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var items: [String] = []
    @State private var newItem: String = ""
    
    var body: some View {
        SettingsScaffold(title: "Event Micro-Reminders") {
            VStack(spacing: 28) {
                SettingsSection(header: "Items for \(eventType)") {
                    SettingsCard {
                        ForEach(items.indices, id: \.self) { index in
                            HStack(spacing: 12) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                                    .onTapGesture {
                                        items.remove(at: index)
                                    }
                                Text(items[index])
                                    .font(.system(size: 17))
                                    .foregroundColor(Color(.textPrimary))
                                Spacer()
                            }
                            .padding(.horizontal, 18)
                            .frame(height: 52)
                            
                            SettingsDivider()
                        }
                        
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.accentColor)
                            TextField("Add item...", text: $newItem)
                                .font(.system(size: 17))
                                .foregroundColor(Color(.textPrimary))
                                .submitLabel(.done)
                                .onSubmit {
                                    let trimmed = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmed.isEmpty {
                                        items.append(trimmed)
                                        newItem = ""
                                    }
                                }
                        }
                        .padding(.horizontal, 18)
                        .frame(height: 52)
                    }
                }
                
                Button {
                    saveAndDismiss()
                } label: {
                    Text("Save & Confirm")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.accentColor)
                        .cornerRadius(12)
                        .padding(.horizontal, 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)
        }
        .task {
            loadItems()
        }
    }
    
    private func loadItems() {
        let prefs = (try? modelContext.fetch(FetchDescriptor<ContextualPreference>())) ?? []
        if let pref = prefs.first(where: { $0.eventType == eventType }) {
            self.items = pref.items
        }
    }
    
    private func saveAndDismiss() {
        let prefs = (try? modelContext.fetch(FetchDescriptor<ContextualPreference>())) ?? []
        if let pref = prefs.first(where: { $0.eventType == eventType }) {
            pref.items = items
            pref.isUserConfirmed = true
            pref.confidence = 1.0
        } else {
            let newPref = ContextualPreference(eventType: eventType, items: items, confidence: 1.0, isUserConfirmed: true)
            modelContext.insert(newPref)
        }
        try? modelContext.save()
        dismiss()
    }
}
