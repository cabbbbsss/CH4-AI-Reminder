import SwiftUI

// MARK: - Main Settings hub (Sketch artboard 5CF849E7)

struct SettingsView: View {
    @Bindable var permissionManager = PermissionManager.shared
    @State private var name = "John"

    var body: some View {
        SettingsScaffold(title: "Settings") {
            VStack(spacing: 28) {
                // Allow EVE to Access
                SettingsSection(header: "Allow EVE to Access") {
                    SettingsCard {
                        SettingsNavRow(icon: "apple.intelligence", label: "Apple Intelligence") {
                            AppleIntelligenceSettingsView()
                        }
                        SettingsDivider()
                        SettingsNavRow(icon: "location.fill", label: "Location") {
                            LocationSettingsView()
                        }
                        SettingsDivider()
                        SettingsNavRow(icon: "bell.badge.fill", label: "Notification") {
                            NotificationSettingsView()
                        }
                    }
                }

                // Profile
                SettingsSection(header: "Profile") {
                    SettingsCard {
                        SettingsValueRow(label: "Name", value: $name, trailingIcon: "pencil", isEditable: true)
                        SettingsDivider()
                        SettingsNavRow(label: "Saved Address") {
                            SavedAddressView()
                        }
                    }
                }

                // General App
                SettingsSection(header: "General App") {
                    SettingsCard {
                        SettingsRow(label: "Language")
                        SettingsDivider()
                        SettingsRow(label: "Legal & Privacy")
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Shared settings chrome (reused by every settings screen)

/// Background + custom nav bar + scrolling content, matching the EVE design language.
struct SettingsScaffold<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(hex: "#E0ECF7").ignoresSafeArea()

            VStack(spacing: 0) {
                SettingsNavBar(title: title) { dismiss() }

                ScrollView(showsIndicators: false) {
                    content
                }
            }
        }
        .navigationBarHidden(true)
    }
}

struct SettingsNavBar: View {
    let title: String
    var onBack: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.black)

            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color(hex: "#1D3557"))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .frame(height: 64)
    }
}

struct SettingsSection<Content: View>: View {
    let header: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(header)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Color(hex: "#1D3557"))
                .padding(.horizontal, 24)

            content
        }
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Color(hex: "#E8F3FF"))
        .cornerRadius(20)
        .padding(.horizontal, 20)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(hex: "#1D3557").opacity(0.06))
            .frame(height: 1)
            .padding(.leading, 18)
    }
}

/// A plain informational row (label + chevron).
struct SettingsRow: View {
    var icon: String? = nil
    var label: String
    var showChevron: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundColor(Color(hex: "#1D3557"))
                    .frame(width: 26)
            }
            Text(label)
                .font(.system(size: 17))
                .foregroundColor(Color(hex: "#1D3557"))
            Spacer()
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "#ADC0D3"))
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
    }
}

/// A row that displays a value (and optional trailing glyph) instead of a chevron.
/// When `isEditable` is true, tapping the trailing icon turns the value into an editable text field.
struct SettingsValueRow: View {
    var label: String
    @Binding var value: String
    var trailingIcon: String? = nil
    var isEditable: Bool = false

    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 17))
                .foregroundColor(Color(hex: "#1D3557"))
            Spacer()
            if isEditing {
                TextField("", text: $value)
                    .font(.system(size: 17))
                    .foregroundColor(Color(hex: "#1D3557"))
                    .multilineTextAlignment(.trailing)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit { isEditing = false }
            } else {
                Text(value)
                    .font(.system(size: 17))
                    .foregroundColor(Color(hex: "#1D3557").opacity(0.7))
            }
            if let trailingIcon, isEditable {
                Button {
                    isEditing.toggle()
                    isFocused = isEditing
                } label: {
                    Image(systemName: isEditing ? "checkmark" : trailingIcon)
                        .font(.system(size: 15))
                        .foregroundColor(Color(hex: "#1D3557").opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
    }
}

/// A tappable row that pushes a destination.
struct SettingsNavRow<Destination: View>: View {
    var icon: String? = nil
    var label: String
    @ViewBuilder var destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            SettingsRow(icon: icon, label: label)
        }
        .buttonStyle(.plain)
    }
}

/// Custom pill switch matching the design's blue toggle.
struct EVEToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .tint(Color(hex: "#3FA9F5"))
    }
}

/// A row with a trailing blue switch.
struct SettingsToggleRow: View {
    var label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(Color(hex: "#1D3557"))
            Spacer()
            EVEToggle(isOn: $isOn)
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
    }
}

/// A selectable row with a leading checkmark when chosen.
struct SettingsChoiceRow: View {
    var label: String
    var isSelected: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: "#1D3557"))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "#0091FF"))
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
